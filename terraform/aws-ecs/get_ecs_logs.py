#!/usr/bin/env python3
"""
ECS and ALB Logs Retrieval Tool

This utility fetches real-time and historical logs from:
- ECS task CloudWatch logs (Auth, Registry, Keycloak services)
- ALB access logs from S3
- Provides filtering, following, and formatted output
"""

import argparse
import json
import logging
import os
import subprocess
import sys
from datetime import datetime
from datetime import timedelta
from typing import Optional

import boto3


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s,p%(process)s,{%(filename)s:%(lineno)d},%(levelname)s,%(message)s",
)
logger = logging.getLogger(__name__)

# AWS Clients
REGION = os.getenv("AWS_REGION", "us-east-1")
CLUSTER_NAME = "mcp-gateway-ecs-cluster"

ecs_client = boto3.client("ecs", region_name=REGION)
logs_client = boto3.client("logs", region_name=REGION)
elbv2_client = boto3.client("elbv2", region_name=REGION)
s3_client = boto3.client("s3", region_name=REGION)


# Color codes
class Colors:
    """ANSI color codes for terminal output"""

    BLUE = "\033[0;34m"
    GREEN = "\033[0;32m"
    RED = "\033[0;31m"
    YELLOW = "\033[1;33m"
    NC = "\033[0m"

    @staticmethod
    def blue(text: str) -> str:
        return f"{Colors.BLUE}{text}{Colors.NC}"

    @staticmethod
    def green(text: str) -> str:
        return f"{Colors.GREEN}{text}{Colors.NC}"

    @staticmethod
    def red(text: str) -> str:
        return f"{Colors.RED}{text}{Colors.NC}"

    @staticmethod
    def yellow(text: str) -> str:
        return f"{Colors.YELLOW}{text}{Colors.NC}"


def _get_log_group_name(service: str) -> str:
    """Get the CloudWatch log group name for a service"""
    return f"/ecs/mcp-gateway-ecs-{service}"


def _list_running_tasks(
    service: Optional[str] = None,
) -> list[str]:
    """List running task ARNs in the cluster"""
    try:
        if service:
            response = ecs_client.list_tasks(
                cluster=CLUSTER_NAME,
                serviceName=service,
            )
        else:
            response = ecs_client.list_tasks(cluster=CLUSTER_NAME)

        return response.get("taskArns", [])
    except Exception as e:
        logger.error(f"Failed to list tasks: {e}")
        return []


def _get_task_details(task_arn: str) -> dict:
    """Get detailed information about a task"""
    try:
        response = ecs_client.describe_tasks(
            cluster=CLUSTER_NAME,
            tasks=[task_arn],
        )
        return response.get("tasks", [{}])[0]
    except Exception as e:
        logger.error(f"Failed to get task details: {e}")
        return {}


def _list_services() -> list[str]:
    """List all services in the cluster"""
    try:
        response = ecs_client.list_services(cluster=CLUSTER_NAME)
        return response.get("serviceArns", [])
    except Exception as e:
        logger.error(f"Failed to list services: {e}")
        return []


def _get_service_details(service_arn: str) -> dict:
    """Get detailed information about a service"""
    try:
        response = ecs_client.describe_services(
            cluster=CLUSTER_NAME,
            services=[service_arn],
        )
        return response.get("services", [{}])[0]
    except Exception as e:
        logger.error(f"Failed to get service details: {e}")
        return {}


def _log_group_exists(log_group_name: str) -> bool:
    """Check if a log group exists"""
    try:
        logs_client.describe_log_groups(
            logGroupNamePrefix=log_group_name,
        )
        return True
    except logs_client.exceptions.ResourceNotFoundException:
        return False
    except Exception as e:
        logger.error(f"Failed to check log group: {e}")
        return False


def get_ecs_logs(
    service: str,
    follow: bool = False,
    minutes: int = 30,
    tail_lines: int = 100,
    filter_pattern: Optional[str] = None,
) -> None:
    """Fetch ECS CloudWatch logs for a service"""
    log_group = _get_log_group_name(service)

    logger.info(f"Fetching logs for service: {Colors.blue(service)}")
    logger.info(f"Log group: {Colors.blue(log_group)}")

    if not _log_group_exists(log_group):
        logger.warning(f"Log group not found: {log_group}")
        return

    try:
        if follow:
            logger.info("Following logs in real-time (Ctrl+C to stop)...")

            # Use AWS CLI for better streaming
            cmd = [
                "aws",
                "logs",
                "tail",
                log_group,
                "--follow",
                "--region",
                REGION,
                "--format",
                "short",
            ]
            subprocess.run(cmd, check=False)
        else:
            # Get historical logs
            cmd = [
                "aws",
                "logs",
                "tail",
                log_group,
                "--region",
                REGION,
                "--since",
                f"{minutes}m",
                "--format",
                "short",
                "--max-items",
                str(tail_lines),
            ]

            if filter_pattern:
                cmd.extend(["--filter-pattern", filter_pattern])

            subprocess.run(cmd, check=False)

    except KeyboardInterrupt:
        logger.info("Stopped following logs")
    except Exception as e:
        logger.error(f"Failed to fetch logs: {e}")


def list_services() -> None:
    """List all ECS services in the cluster"""
    logger.info(f"Listing ECS services in cluster: {Colors.blue(CLUSTER_NAME)}")

    services = _list_services()

    if not services:
        logger.warning("No services found")
        return

    for service_arn in services:
        service_name = service_arn.split("/")[-1]
        service_details = _get_service_details(service_arn)
        running_count = service_details.get("runningCount", 0)
        desired_count = service_details.get("desiredCount", 0)

        status_color = Colors.green if running_count == desired_count else Colors.yellow
        print(
            f"Service: {Colors.green(service_name)}\n"
            f"  Running: {status_color(str(running_count))}/{desired_count}\n"
            f"  ARN: {service_arn}\n"
        )


def list_tasks() -> None:
    """List all running tasks in the cluster"""
    logger.info(f"Listing running tasks in cluster: {Colors.blue(CLUSTER_NAME)}")

    tasks = _list_running_tasks()

    if not tasks:
        logger.warning("No running tasks found")
        return

    for task_arn in tasks:
        task_details = _get_task_details(task_arn)
        task_def_arn = task_details.get("taskDefinitionArn", "")
        task_name = task_def_arn.split("/")[-1] if task_def_arn else "unknown"
        task_id = task_arn.split("/")[-1]
        status = task_details.get("lastStatus", "unknown")

        status_color = Colors.green if status == "RUNNING" else Colors.yellow
        print(
            f"Task: {Colors.green(task_name)}\n"
            f"  ID: {Colors.blue(task_id)}\n"
            f"  Status: {status_color(status)}\n"
            f"  ARN: {task_arn}\n"
        )


def get_alb_logs(alb_name: str = "registry") -> None:
    """Fetch ALB access logs from S3"""
    logger.info(f"Fetching ALB access logs for: {Colors.blue(alb_name)}")

    try:
        # Get ALB ARN
        response = elbv2_client.describe_load_balancers()
        alb_arn = None

        for alb in response.get("LoadBalancers", []):
            if alb_name in alb["LoadBalancerName"]:
                alb_arn = alb["LoadBalancerArn"]
                break

        if not alb_arn:
            logger.error(f"ALB not found: {alb_name}")
            return

        logger.info(f"ALB ARN: {Colors.blue(alb_arn)}")

        # Get ALB attributes
        attr_response = elbv2_client.describe_load_balancer_attributes(
            LoadBalancerArn=alb_arn,
        )

        logs_bucket = None
        logs_prefix = ""

        for attr in attr_response.get("Attributes", []):
            if attr["Key"] == "access_logs.s3.bucket":
                logs_bucket = attr["Value"]
            elif attr["Key"] == "access_logs.s3.prefix":
                logs_prefix = attr.get("Value", "")

        if not logs_bucket:
            logger.warning(f"ALB logging not enabled for: {alb_name}")
            return

        logger.info(f"ALB logs bucket: {Colors.blue(logs_bucket)}")
        logger.info(f"ALB logs prefix: {Colors.blue(logs_prefix)}")

        # List recent logs in S3
        logger.info("Recent ALB logs in S3:")
        response = s3_client.list_objects_v2(
            Bucket=logs_bucket,
            Prefix=logs_prefix,
            MaxKeys=20,
        )

        contents = response.get("Contents", [])
        if contents:
            for obj in contents[-5:]:
                key = obj["Key"]
                size = obj["Size"]
                modified = obj["LastModified"]
                print(
                    f"  {Colors.blue(key)}\n"
                    f"    Modified: {modified}, Size: {size} bytes\n"
                )

            # Show how to download and view latest log
            latest_key = contents[-1]["Key"]
            filename = latest_key.split("/")[-1]
            print(
                f"\nTo download and view the latest log:\n"
                f"  aws s3 cp s3://{logs_bucket}/{latest_key} . --region {REGION}\n"
                f"  gunzip {filename}\n"
                f"  cat {filename.replace('.gz', '')}\n"
            )
        else:
            logger.warning("No logs found in S3")

    except Exception as e:
        logger.error(f"Failed to fetch ALB logs: {e}")


def get_all_logs(follow: bool = False, minutes: int = 30) -> None:
    """Fetch logs from all services"""
    services = ["auth-server", "registry", "keycloak"]

    for service in services:
        logger.info("=" * 50)
        logger.info(f"Logs for service: {Colors.blue(service)}")
        logger.info("=" * 50)
        get_ecs_logs(service, follow=follow, minutes=minutes)
        print()


def main() -> None:
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Fetch ECS task logs and ALB access logs",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Get last 100 lines of registry logs
  python -m get_ecs_logs registry-logs

  # Follow auth service logs in real-time
  python -m get_ecs_logs auth-logs --follow

  # Get last 30 minutes of logs filtered by 'error'
  python -m get_ecs_logs registry-logs --filter "error"

  # Get ALB logs with error-only filter
  python -m get_ecs_logs alb-logs --alb registry

  # List all running tasks
  python -m get_ecs_logs list-tasks

  # List all services
  python -m get_ecs_logs list-services

  # Get logs from all services
  python -m get_ecs_logs all-logs --follow
        """,
    )

    subparsers = parser.add_subparsers(
        dest="command",
        help="Command to execute",
    )

    # ECS logs command
    ecs_parser = subparsers.add_parser(
        "ecs-logs",
        help="Get logs from all ECS services",
    )
    ecs_parser.add_argument(
        "--follow",
        action="store_true",
        help="Follow logs in real-time",
    )
    ecs_parser.add_argument(
        "--minutes",
        type=int,
        default=30,
        help="Show logs from last N minutes (default: 30)",
    )
    ecs_parser.add_argument(
        "--tail",
        type=int,
        default=100,
        help="Show last N lines (default: 100)",
    )

    # Auth logs command
    auth_parser = subparsers.add_parser(
        "auth-logs",
        help="Get auth service logs",
    )
    auth_parser.add_argument(
        "--follow",
        action="store_true",
        help="Follow logs in real-time",
    )
    auth_parser.add_argument(
        "--minutes",
        type=int,
        default=30,
        help="Show logs from last N minutes (default: 30)",
    )
    auth_parser.add_argument(
        "--filter",
        help="Filter logs by pattern",
    )

    # Registry logs command
    registry_parser = subparsers.add_parser(
        "registry-logs",
        help="Get registry service logs",
    )
    registry_parser.add_argument(
        "--follow",
        action="store_true",
        help="Follow logs in real-time",
    )
    registry_parser.add_argument(
        "--minutes",
        type=int,
        default=30,
        help="Show logs from last N minutes (default: 30)",
    )
    registry_parser.add_argument(
        "--filter",
        help="Filter logs by pattern",
    )

    # Keycloak logs command
    keycloak_parser = subparsers.add_parser(
        "keycloak-logs",
        help="Get Keycloak service logs",
    )
    keycloak_parser.add_argument(
        "--follow",
        action="store_true",
        help="Follow logs in real-time",
    )
    keycloak_parser.add_argument(
        "--minutes",
        type=int,
        default=30,
        help="Show logs from last N minutes (default: 30)",
    )
    keycloak_parser.add_argument(
        "--filter",
        help="Filter logs by pattern",
    )

    # All logs command
    all_parser = subparsers.add_parser(
        "all-logs",
        help="Get logs from all services",
    )
    all_parser.add_argument(
        "--follow",
        action="store_true",
        help="Follow logs in real-time",
    )
    all_parser.add_argument(
        "--minutes",
        type=int,
        default=30,
        help="Show logs from last N minutes (default: 30)",
    )

    # ALB logs command
    alb_parser = subparsers.add_parser(
        "alb-logs",
        help="Get ALB access logs",
    )
    alb_parser.add_argument(
        "--alb",
        default="registry",
        choices=["registry", "keycloak"],
        help="ALB to fetch logs from (default: registry)",
    )

    # List tasks command
    subparsers.add_parser(
        "list-tasks",
        help="List running ECS tasks",
    )

    # List services command
    subparsers.add_parser(
        "list-services",
        help="List ECS services",
    )

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    try:
        if args.command == "ecs-logs":
            get_all_logs(
                follow=args.follow,
                minutes=args.minutes,
            )
        elif args.command == "auth-logs":
            get_ecs_logs(
                "auth-server",
                follow=args.follow,
                minutes=args.minutes,
                filter_pattern=getattr(args, "filter", None),
            )
        elif args.command == "registry-logs":
            get_ecs_logs(
                "registry",
                follow=args.follow,
                minutes=args.minutes,
                filter_pattern=getattr(args, "filter", None),
            )
        elif args.command == "keycloak-logs":
            get_ecs_logs(
                "keycloak",
                follow=args.follow,
                minutes=args.minutes,
                filter_pattern=getattr(args, "filter", None),
            )
        elif args.command == "all-logs":
            get_all_logs(
                follow=args.follow,
                minutes=args.minutes,
            )
        elif args.command == "alb-logs":
            get_alb_logs(alb_name=args.alb)
        elif args.command == "list-tasks":
            list_tasks()
        elif args.command == "list-services":
            list_services()

    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
