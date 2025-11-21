#!/bin/bash
# Generate image-manifest.json from build-config.yaml for Terraform consumption
# This script creates a JSON file with all ECR image URIs for Terraform to reference

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/build-config.yaml"
OUTPUT_FILE="${SCRIPT_DIR}/image-manifest.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found"
    exit 1
fi

echo "Generating image manifest from $CONFIG_FILE..."

python3 << EOF
import yaml
import json
import sys

with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)

aws_config = cfg.get('aws', {})
ecr_registry = aws_config.get('ecr_registry')
images = cfg.get('images', {})

if not ecr_registry:
    print("Error: ecr_registry not found in config")
    sys.exit(1)

manifest = {}
for name, config in images.items():
    repo_name = config.get('repo_name')
    if not repo_name:
        print(f"Error: Image '{name}' missing repo_name")
        sys.exit(1)

    ecr_uri = f'{ecr_registry}/{repo_name}:latest'
    manifest[name] = ecr_uri

# Write manifest
with open('$OUTPUT_FILE', 'w') as f:
    json.dump(manifest, f, indent=2)

print(f"Successfully generated {len(manifest)} image URIs in image-manifest.json")
print()
print("Image URIs (for Terraform):")
for name, uri in manifest.items():
    print(f"  {name:25} = {uri}")
EOF

echo ""
echo "Manifest saved to: $OUTPUT_FILE"
echo ""
echo "Usage in Terraform:"
echo "  locals {"
echo "    image_manifest = jsondecode(file(\"\${path.module}/image-manifest.json\"))"
echo "    registry_image = local.image_manifest[\"registry\"]"
echo "  }"
