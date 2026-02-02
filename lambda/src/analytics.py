"""
Analytics Lambda Function
IaC Secure Gate - Phase 2

Purpose: Analyze remediation history and generate daily reports
- Query DynamoDB for remediation events
- Calculate success rates and mean time to remediate
- Identify repeat offenders (resources with multiple violations)
- Generate and publish analytics report via SNS

Author: IaC Secure Gate Team
Version: 1.0.0
"""

import json
import logging
import os
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any

import boto3
from botocore.exceptions import ClientError

# ==================================================================
# Configuration
# ==================================================================

# Environment variables
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
ANALYSIS_DAYS = int(os.environ.get("ANALYSIS_DAYS", "30"))

# Configure logging
logger = logging.getLogger()
logger.setLevel(getattr(logging, LOG_LEVEL.upper(), logging.INFO))

# AWS clients (initialized outside handler for connection reuse)
dynamodb = boto3.resource("dynamodb")
sns = boto3.client("sns")


# ==================================================================
# Helper Classes
# ==================================================================

class DecimalEncoder(json.JSONEncoder):
    """JSON encoder that handles Decimal types from DynamoDB."""
    def default(self, obj: Any) -> Any:
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)


# ==================================================================
# Analytics Functions
# ==================================================================

def get_remediation_events(table_name: str, days: int) -> list[dict]:
    """
    Query DynamoDB for remediation events within the specified time range.

    Args:
        table_name: DynamoDB table name
        days: Number of days to look back

    Returns:
        List of remediation event records
    """
    if not table_name:
        logger.warning("No DynamoDB table configured, returning empty results")
        return []

    table = dynamodb.Table(table_name)
    cutoff_time = datetime.now(timezone.utc) - timedelta(days=days)
    cutoff_iso = cutoff_time.isoformat()

    all_items = []
    violation_types = ["IAM_WILDCARD_POLICY", "S3_PUBLIC_BUCKET", "SECURITY_GROUP_OPEN"]

    for violation_type in violation_types:
        try:
            # Query each partition separately for efficiency
            response = table.query(
                KeyConditionExpression="violation_type = :vt AND #ts >= :cutoff",
                ExpressionAttributeNames={"#ts": "timestamp"},
                ExpressionAttributeValues={
                    ":vt": violation_type,
                    ":cutoff": cutoff_iso
                }
            )
            all_items.extend(response.get("Items", []))

            # Handle pagination
            while "LastEvaluatedKey" in response:
                response = table.query(
                    KeyConditionExpression="violation_type = :vt AND #ts >= :cutoff",
                    ExpressionAttributeNames={"#ts": "timestamp"},
                    ExpressionAttributeValues={
                        ":vt": violation_type,
                        ":cutoff": cutoff_iso
                    },
                    ExclusiveStartKey=response["LastEvaluatedKey"]
                )
                all_items.extend(response.get("Items", []))

        except ClientError as e:
            logger.error(f"Error querying DynamoDB for {violation_type}: {e}")
            continue

    logger.info(f"Retrieved {len(all_items)} remediation events from last {days} days")
    return all_items


def calculate_statistics(events: list[dict]) -> dict:
    """
    Calculate remediation statistics from event data.

    Args:
        events: List of remediation event records

    Returns:
        Dictionary containing calculated statistics
    """
    if not events:
        return {
            "total_remediations": 0,
            "successful": 0,
            "failed": 0,
            "success_rate": 0.0,
            "by_type": {},
            "mean_time_to_remediate_seconds": None
        }

    total = len(events)
    successful = sum(1 for e in events if e.get("remediation_status") == "SUCCESS")
    failed = sum(1 for e in events if e.get("remediation_status") in ["FAILED", "ERROR"])
    skipped = sum(1 for e in events if e.get("remediation_status") == "SKIPPED")

    success_rate = (successful / total * 100) if total > 0 else 0.0

    # Count by violation type
    by_type = {}
    for event in events:
        vtype = event.get("violation_type", "Unknown")
        if vtype not in by_type:
            by_type[vtype] = {"total": 0, "successful": 0, "failed": 0}
        by_type[vtype]["total"] += 1
        if event.get("remediation_status") == "SUCCESS":
            by_type[vtype]["successful"] += 1
        elif event.get("remediation_status") in ["FAILED", "ERROR"]:
            by_type[vtype]["failed"] += 1

    # Calculate mean time to remediate (if detection_time and remediation_time exist)
    remediation_times = []
    for event in events:
        if event.get("detection_time") and event.get("remediation_time"):
            try:
                detection = datetime.fromisoformat(event["detection_time"].replace("Z", "+00:00"))
                remediation = datetime.fromisoformat(event["remediation_time"].replace("Z", "+00:00"))
                delta = (remediation - detection).total_seconds()
                if delta >= 0:
                    remediation_times.append(delta)
            except (ValueError, TypeError):
                continue

    mean_time = sum(remediation_times) / len(remediation_times) if remediation_times else None

    return {
        "total_remediations": total,
        "successful": successful,
        "failed": failed,
        "skipped": skipped,
        "success_rate": round(success_rate, 2),
        "by_type": by_type,
        "mean_time_to_remediate_seconds": round(mean_time, 2) if mean_time else None
    }


def identify_repeat_offenders(events: list[dict], threshold: int = 3) -> list[dict]:
    """
    Identify resources with multiple violations.

    Args:
        events: List of remediation event records
        threshold: Minimum number of violations to be considered a repeat offender

    Returns:
        List of repeat offender resources with violation counts
    """
    resource_counts: dict[str, dict] = {}

    for event in events:
        resource_arn = event.get("resource_arn", "")
        if not resource_arn:
            continue

        if resource_arn not in resource_counts:
            resource_counts[resource_arn] = {
                "resource_arn": resource_arn,
                "violation_count": 0,
                "violation_types": set(),
                "last_violation": None
            }

        resource_counts[resource_arn]["violation_count"] += 1
        resource_counts[resource_arn]["violation_types"].add(event.get("violation_type", "Unknown"))

        event_time = event.get("timestamp")
        if event_time:
            current_last = resource_counts[resource_arn]["last_violation"]
            if not current_last or event_time > current_last:
                resource_counts[resource_arn]["last_violation"] = event_time

    # Filter to resources exceeding threshold and convert sets to lists
    repeat_offenders = []
    for resource in resource_counts.values():
        if resource["violation_count"] >= threshold:
            repeat_offenders.append({
                "resource_arn": resource["resource_arn"],
                "violation_count": resource["violation_count"],
                "violation_types": list(resource["violation_types"]),
                "last_violation": resource["last_violation"]
            })

    # Sort by violation count descending
    repeat_offenders.sort(key=lambda x: x["violation_count"], reverse=True)

    logger.info(f"Identified {len(repeat_offenders)} repeat offenders (threshold: {threshold})")
    return repeat_offenders[:10]  # Return top 10


def calculate_trend(events: list[dict], days: int) -> dict:
    """
    Calculate remediation trend over time.

    Args:
        events: List of remediation event records
        days: Number of days to analyze

    Returns:
        Dictionary with daily counts and trend direction
    """
    if not events:
        return {"daily_counts": {}, "trend": "stable", "change_percent": 0}

    # Group by date
    daily_counts: dict[str, int] = {}
    for event in events:
        timestamp = event.get("timestamp", "")
        if timestamp:
            try:
                date = timestamp[:10]  # Extract YYYY-MM-DD
                daily_counts[date] = daily_counts.get(date, 0) + 1
            except (IndexError, TypeError):
                continue

    if len(daily_counts) < 2:
        return {"daily_counts": daily_counts, "trend": "insufficient_data", "change_percent": 0}

    # Calculate trend (compare first half vs second half)
    sorted_dates = sorted(daily_counts.keys())
    mid = len(sorted_dates) // 2

    first_half_avg = sum(daily_counts[d] for d in sorted_dates[:mid]) / mid if mid > 0 else 0
    second_half_avg = sum(daily_counts[d] for d in sorted_dates[mid:]) / (len(sorted_dates) - mid) if (len(sorted_dates) - mid) > 0 else 0

    if first_half_avg == 0:
        change_percent = 100 if second_half_avg > 0 else 0
    else:
        change_percent = ((second_half_avg - first_half_avg) / first_half_avg) * 100

    if change_percent > 10:
        trend = "increasing"
    elif change_percent < -10:
        trend = "decreasing"
    else:
        trend = "stable"

    return {
        "daily_counts": daily_counts,
        "trend": trend,
        "change_percent": round(change_percent, 2)
    }


def generate_report(stats: dict, repeat_offenders: list, trend: dict, days: int) -> dict:
    """
    Generate the analytics report.

    Args:
        stats: Calculated statistics
        repeat_offenders: List of repeat offender resources
        trend: Trend analysis results
        days: Analysis period in days

    Returns:
        Complete analytics report dictionary
    """
    report = {
        "report_type": "remediation_analytics",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "environment": ENVIRONMENT,
        "analysis_period_days": days,
        "summary": {
            "total_remediations": stats["total_remediations"],
            "successful": stats["successful"],
            "failed": stats["failed"],
            "skipped": stats.get("skipped", 0),
            "success_rate_percent": stats["success_rate"],
            "mean_time_to_remediate_seconds": stats["mean_time_to_remediate_seconds"]
        },
        "by_violation_type": stats["by_type"],
        "trend": {
            "direction": trend["trend"],
            "change_percent": trend["change_percent"]
        },
        "repeat_offenders": repeat_offenders,
        "recommendations": generate_recommendations(stats, repeat_offenders, trend)
    }

    return report


def generate_recommendations(stats: dict, repeat_offenders: list, trend: dict) -> list[str]:
    """
    Generate actionable recommendations based on analytics.

    Args:
        stats: Calculated statistics
        repeat_offenders: List of repeat offender resources
        trend: Trend analysis results

    Returns:
        List of recommendation strings
    """
    recommendations = []

    # Check success rate
    if stats["success_rate"] < 90:
        recommendations.append(
            f"Success rate is {stats['success_rate']}% - investigate failed remediations "
            f"and consider expanding Lambda permissions or adjusting remediation logic."
        )

    # Check for repeat offenders
    if repeat_offenders:
        top_offender = repeat_offenders[0]
        recommendations.append(
            f"Resource '{top_offender['resource_arn']}' has {top_offender['violation_count']} violations. "
            f"Consider implementing preventive controls or alerting the resource owner."
        )

    # Check trend
    if trend["trend"] == "increasing" and trend["change_percent"] > 25:
        recommendations.append(
            f"Violations increasing by {trend['change_percent']}%. "
            f"Review recent infrastructure changes and reinforce security training."
        )
    elif trend["trend"] == "decreasing":
        recommendations.append(
            f"Violations decreasing by {abs(trend['change_percent'])}%. "
            f"Security posture improving - continue current practices."
        )

    # Check by type
    for vtype, counts in stats.get("by_type", {}).items():
        if counts["failed"] > 0 and counts["total"] > 0:
            fail_rate = (counts["failed"] / counts["total"]) * 100
            if fail_rate > 20:
                recommendations.append(
                    f"{vtype} remediation has {fail_rate:.1f}% failure rate. "
                    f"Review {vtype} Lambda function logs for issues."
                )

    if not recommendations:
        recommendations.append("No immediate actions required. Security posture is healthy.")

    return recommendations


def format_email_report(report: dict) -> str:
    """
    Format the report for email notification.

    Args:
        report: Analytics report dictionary

    Returns:
        Formatted string for email body
    """
    lines = [
        "=" * 60,
        "IaC SECURE GATE - DAILY ANALYTICS REPORT",
        "=" * 60,
        "",
        f"Generated: {report['generated_at']}",
        f"Environment: {report['environment']}",
        f"Analysis Period: Last {report['analysis_period_days']} days",
        "",
        "-" * 40,
        "SUMMARY",
        "-" * 40,
        f"Total Remediations: {report['summary']['total_remediations']}",
        f"  - Successful: {report['summary']['successful']}",
        f"  - Failed: {report['summary']['failed']}",
        f"  - Skipped: {report['summary']['skipped']}",
        f"Success Rate: {report['summary']['success_rate_percent']}%",
    ]

    mttr = report['summary']['mean_time_to_remediate_seconds']
    if mttr:
        lines.append(f"Mean Time to Remediate: {mttr:.2f} seconds")

    lines.extend([
        "",
        "-" * 40,
        "BY VIOLATION TYPE",
        "-" * 40,
    ])

    for vtype, counts in report.get("by_violation_type", {}).items():
        lines.append(f"{vtype}: {counts['total']} total ({counts['successful']} success, {counts['failed']} failed)")

    lines.extend([
        "",
        "-" * 40,
        "TREND ANALYSIS",
        "-" * 40,
        f"Direction: {report['trend']['direction'].upper()}",
        f"Change: {report['trend']['change_percent']}%",
    ])

    if report.get("repeat_offenders"):
        lines.extend([
            "",
            "-" * 40,
            "TOP REPEAT OFFENDERS",
            "-" * 40,
        ])
        for i, offender in enumerate(report["repeat_offenders"][:5], 1):
            lines.append(f"{i}. {offender['resource_arn']}")
            lines.append(f"   Violations: {offender['violation_count']}")

    lines.extend([
        "",
        "-" * 40,
        "RECOMMENDATIONS",
        "-" * 40,
    ])

    for rec in report.get("recommendations", []):
        lines.append(f"* {rec}")

    lines.extend([
        "",
        "=" * 60,
        "End of Report",
        "=" * 60,
    ])

    return "\n".join(lines)


def publish_report(report: dict, topic_arn: str) -> bool:
    """
    Publish the report to SNS.

    Args:
        report: Analytics report dictionary
        topic_arn: SNS topic ARN

    Returns:
        True if successful, False otherwise
    """
    if not topic_arn:
        logger.warning("No SNS topic configured, skipping publish")
        return False

    try:
        email_body = format_email_report(report)

        response = sns.publish(
            TopicArn=topic_arn,
            Subject=f"[IaC Secure Gate] Daily Analytics Report - {ENVIRONMENT}",
            Message=email_body,
            MessageAttributes={
                "ReportType": {
                    "DataType": "String",
                    "StringValue": "daily_analytics"
                },
                "Environment": {
                    "DataType": "String",
                    "StringValue": ENVIRONMENT
                }
            }
        )

        logger.info(f"Published report to SNS, MessageId: {response['MessageId']}")
        return True

    except ClientError as e:
        logger.error(f"Failed to publish to SNS: {e}")
        return False


# ==================================================================
# Lambda Handler
# ==================================================================

def lambda_handler(event: dict, context: Any) -> dict:
    """
    Main Lambda handler for analytics processing.

    Args:
        event: Lambda event (can be CloudWatch scheduled event or manual trigger)
        context: Lambda context

    Returns:
        Response dictionary with report summary
    """
    logger.info(f"Analytics Lambda invoked, event type: {event.get('source', 'manual')}")

    try:
        # Get analysis period from event or use default
        days = event.get("analysis_days", ANALYSIS_DAYS)

        # Fetch remediation events
        events = get_remediation_events(DYNAMODB_TABLE, days)

        # Calculate statistics
        stats = calculate_statistics(events)

        # Identify repeat offenders
        repeat_offenders = identify_repeat_offenders(events)

        # Calculate trend
        trend = calculate_trend(events, days)

        # Generate report
        report = generate_report(stats, repeat_offenders, trend, days)

        # Log report summary
        logger.info(f"Report generated: {stats['total_remediations']} remediations, "
                   f"{stats['success_rate']}% success rate")

        # Publish to SNS
        published = publish_report(report, SNS_TOPIC_ARN)

        return {
            "statusCode": 200,
            "body": {
                "message": "Analytics report generated successfully",
                "published_to_sns": published,
                "summary": report["summary"],
                "trend": report["trend"],
                "repeat_offenders_count": len(repeat_offenders),
                "recommendations_count": len(report["recommendations"])
            }
        }

    except Exception as e:
        logger.exception(f"Analytics Lambda failed: {e}")
        return {
            "statusCode": 500,
            "body": {
                "error": str(e),
                "message": "Analytics report generation failed"
            }
        }
