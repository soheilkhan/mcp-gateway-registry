# Keycloak HTTPS Setup Guide

## Overview
This document outlines the configuration needed for Keycloak to work properly with HTTPS behind an AWS ALB.

## Key Configuration Changes Made

### 1. Terraform Configuration (ecs-services.tf)

Added `KC_HOSTNAME_ADMIN` environment variable to the Keycloak container:

```hcl
{
  name  = "KC_HOSTNAME"
  value = "kc.mycorp.click"
},
{
  name  = "KC_HOSTNAME_PORT"
  value = "443"
},
{
  name  = "KC_HOSTNAME_ADMIN"
  value = "kc.mycorp.click"
},
{
  name  = "KC_HOSTNAME_STRICT"
  value = "false"
},
{
  name  = "KC_HOSTNAME_STRICT_HTTPS"
  value = "true"
},
```

### 2. Post-Deployment Configuration

After Terraform deployment, run the init script to configure the security-admin-console client:

```bash
cd /home/ubuntu/repos/mcp-gateway-registry/terraform/aws-ecs
./init-keycloak-https.sh
```

This script:
- Retrieves the Keycloak admin password from AWS Secrets Manager
- Configures redirect URIs for both the custom domain and ALB URL
- Sets explicit `rootUrl`, `adminUrl`, and `baseUrl` values
- Adds both HTTPS custom domain and ALB URLs to valid redirect URIs

### 3. Required Files

- `init-keycloak-https.sh` - Updated to set explicit URLs and include ALB URLs
- `store-resources.sh` - Captures Terraform outputs for use by other scripts
- `get-ecs-logs.sh` - For monitoring Keycloak logs

## Deployment Steps

1. **Deploy with Terraform:**
   ```bash
   cd /home/ubuntu/repos/mcp-gateway-registry/terraform/aws-ecs
   terraform apply
   ```

2. **Wait for Keycloak to initialize (5-10 minutes)**

3. **Run resource discovery:**
   ```bash
   ./store-resources.sh
   ```

4. **Configure Keycloak client:**
   ```bash
   ./init-keycloak-https.sh
   ```

5. **Access admin console:**
   - URL: https://kc.mycorp.click/admin/master/console/
   - Username: admin
   - Password: Retrieved from AWS Secrets Manager

## Troubleshooting

### Check Keycloak logs:
```bash
./get-ecs-logs.sh keycloak-logs --tail 50
```

### Check running tasks:
```bash
./get-ecs-logs.sh list-tasks
```

### Verify Keycloak environment variables:
```bash
aws ecs describe-task-definition --task-definition mcp-gateway-keycloak --region us-east-1 \
  --query 'taskDefinition.containerDefinitions[0].environment[?contains(name, `KC_HOSTNAME`)]'
```

## Common Issues

1. **Redirect loop/spinner**: Clear browser cache or use incognito mode
2. **Invalid redirect URI**: Run `init-keycloak-https.sh` again
3. **Admin API not accessible**: Wait 5-10 minutes after deployment for full initialization

## Important Notes

- The `KC_HOSTNAME_ADMIN` setting is critical for the admin console to work properly with HTTPS
- Both the custom domain and ALB URLs must be in the redirect URIs list
- The `init-keycloak-https.sh` script must be run after each fresh deployment
