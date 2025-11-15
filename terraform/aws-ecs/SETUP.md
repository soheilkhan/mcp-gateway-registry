# ECS Logging - Initial Setup

## One-time Setup

After deploying or updating Terraform:

```bash
cd terraform/aws-ecs
./store-resources.sh
```

This creates `.resources` file with cluster details from your Terraform deployment.

## Then Use Logging Scripts

```bash
# Get logs
./get-ecs-logs.sh registry-logs
./get-ecs-logs.sh auth-logs --follow
./get-ecs-logs.sh keycloak-logs --minutes 60

# List resources
./get-ecs-logs.sh list-tasks
./get-ecs-logs.sh list-services

# Get ALB logs
./get-ecs-logs.sh alb-logs --alb registry
```

See [LOGGING.md](./LOGGING.md) for complete documentation.
