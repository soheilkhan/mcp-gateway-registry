# Path Reference Guide

To avoid confusion, here's a clear mapping of paths used in the documentation.

## 📁 Repository Locations

### Source Repository (Working Keycloak Code)
```
~/repos/aws-ecs-keycloak/
```

This is where the **working Keycloak implementation** lives. You will **copy files FROM here**.

**Key files**:
- `~/repos/aws-ecs-keycloak/docker/Dockerfile` - Production-ready Keycloak image
- `~/repos/aws-ecs-keycloak/terragrunt/aws/*.tf` - Working Terraform files

### Destination Repository (Where You Work)
```
~/repos/mcp-gateway-registry/
```

This is where you will **make all changes**. You will **copy files TO here**.

**Key directories**:
- `~/repos/mcp-gateway-registry/terraform/aws-ecs/` - Terraform working directory
- `~/repos/mcp-gateway-registry/docker/keycloak/` - Where Dockerfile goes
- `~/repos/mcp-gateway-registry/docs/keycloak-integration/` - This documentation

## 🔄 Common Operations

### Copying Dockerfile
```bash
# FROM (source)
~/repos/aws-ecs-keycloak/docker/Dockerfile

# TO (destination)
~/repos/mcp-gateway-registry/docker/keycloak/Dockerfile
```

### Copying Terraform Files
```bash
# FROM (source)
~/repos/aws-ecs-keycloak/terragrunt/aws/database.tf
~/repos/aws-ecs-keycloak/terragrunt/aws/ecs.tf
# etc.

# TO (destination - renamed)
~/repos/mcp-gateway-registry/terraform/aws-ecs/keycloak-database.tf
~/repos/mcp-gateway-registry/terraform/aws-ecs/keycloak-ecs.tf
# etc.
```

### Working Directory for Terraform Commands
```bash
# Always run terraform commands from here:
cd ~/repos/mcp-gateway-registry/terraform/aws-ecs

terraform init
terraform plan
terraform apply
```

## 🎯 Rule of Thumb

- **Reading/Copying FROM**: `~/repos/aws-ecs-keycloak/`
- **Writing/Working IN**: `~/repos/mcp-gateway-registry/`

## ⚠️ Important

**NEVER modify files in `~/repos/aws-ecs-keycloak/`**

That's the source repository with working code. Keep it pristine as your reference.

All your work happens in:
```
~/repos/mcp-gateway-registry/
```

## 📋 Quick Verification

If you're ever confused about which repo you're in:

```bash
# Check current directory
pwd

# Should be one of:
# /home/ubuntu/repos/mcp-gateway-registry/...    ← Working here
# /home/ubuntu/repos/aws-ecs-keycloak/...        ← Reading from here
```

## 🗺️ Navigation Commands

```bash
# Go to working repository (destination)
cd ~/repos/mcp-gateway-registry

# Go to Terraform working directory
cd ~/repos/mcp-gateway-registry/terraform/aws-ecs

# Go to source repository (reference only)
cd ~/repos/aws-ecs-keycloak

# View source Dockerfile
cat ~/repos/aws-ecs-keycloak/docker/Dockerfile

# View source Terraform files
ls ~/repos/aws-ecs-keycloak/terragrunt/aws/
```

---

**Summary**:
- Source (read only): `~/repos/aws-ecs-keycloak/`
- Destination (your work): `~/repos/mcp-gateway-registry/`
