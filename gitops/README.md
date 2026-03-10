# GitOps Deployment Guide

This directory contains Flux CD manifests for deploying the MCP Gateway Registry using GitOps practices.

## Architecture

The `mcp-gateway-registry` umbrella Helm chart manages three subcharts:

| Subchart | Role | Ingress | Port |
|----------|------|---------|------|
| `registry` | API + React UI + nginx reverse proxy | External (ALB) | 8080 |
| `auth-server` | OAuth/OIDC authentication service | External (ALB) | 8080 |
| `mcpgw` | MCP protocol gateway proxy (internal) | None (ClusterIP) | 8003 |

Traffic flow: Client -> ALB -> registry (nginx) -> mcpgw (internal) -> upstream MCP servers

## Choose Your Deployment Guide

Select the guide that matches your deployment target:

### Local Deployment
**For:** Local Kubernetes clusters (Minikube, Kind, Docker Desktop)

**Features:**
- Simple setup with minimal configuration
- No Karpenter (not needed locally)
- Uses `/etc/hosts` for DNS
- File-based storage backend (no external DB)
- Single ingress for the registry service

**Quick start:**
1. Copy `helmrelease-local.yaml` to your Flux config repo
2. Update image tags and hostnames as needed
3. Add hostname to `/etc/hosts`:
   ```
   127.0.0.1  mcp-gateway-registry.local.zetaglobal.io
   ```
4. Deploy with Flux

---

### Preprod/AWS Deployment
**For:** AWS EKS preprod/QA environments

**Features:**
- Full Karpenter autoscaling configuration
- Horizontal Pod Autoscaling (HPA) per subchart
- External DNS integration
- ALB ingress with proper tagging
- Multiple hostnames for service discovery
- Production-ready resource limits
- ServiceMonitor for Prometheus metrics

**Quick start:**
1. Copy `helmrelease-preprod.yaml` to your Flux config repo
2. Update ECR image tags, hostnames, and Karpenter settings
3. Verify security group and subnet tags match your cluster
4. Deploy with Flux

---

## Files in This Directory

| File | Purpose |
|------|---------|
| `helmrelease-local.yaml` | HelmRelease for local/dev deployments |
| `helmrelease-preprod.yaml` | HelmRelease for AWS preprod/QA deployments |
| `helmrepository.yaml` | OCI Helm repository (ECR) configuration |
| `README.md` | This guide |

## Key Differences Between Local and Preprod

| Feature | Local | Preprod/AWS |
|---------|-------|-------------|
| **Karpenter** | Disabled | Enabled with NodePool + EC2NodeClass |
| **Autoscaling** | Disabled (fixed replicas) | HPA enabled per subchart |
| **DNS** | `/etc/hosts` | External DNS (automatic) |
| **Registry Ingress** | Single hostname | Two hostnames (user-friendly + service discovery) |
| **Auth-server Ingress** | Disabled | ALB with External DNS |
| **mcpgw Ingress** | Disabled (internal) | Disabled (internal) |
| **Storage** | File-based | File-based (configurable) |
| **Resources** | Minimal | Production-ready |
| **ServiceMonitor** | Disabled | Enabled |

## Namespace

All resources deploy into the `assistants` namespace. Create it before deploying:

```bash
kubectl create namespace assistants
```

## Customizing Values

Since this is an umbrella chart, subchart values are nested under the subchart name:

```yaml
values:
  global:
    environment: preprod
  registry:
    image:
      tag: "1.0.0"
  auth-server:
    image:
      tag: "1.0.0"
  mcpgw:
    image:
      tag: "1.0.0"
```
