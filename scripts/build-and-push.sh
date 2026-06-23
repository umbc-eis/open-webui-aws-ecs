#!/usr/bin/env bash
set -euo pipefail

# Build the Open WebUI image with document-creation libraries layered on top
# of the upstream image, and push it to the openwebui-umbc ECR repo.
#
# Reads the upstream image tag from terraform.tfvars (open_webui_image_url).
# If that line points at GHCR (initial state), the upstream tag is taken from
# there. If it points at the ECR repo (steady state), the script falls back to
# the OPENWEBUI_UPSTREAM env var, which must be set as e.g. v0.9.5.
#
# Usage:
#   ./scripts/build-and-push.sh
#   ./scripts/build-and-push.sh --tag-suffix extras2
#   OPENWEBUI_UPSTREAM=v0.9.6 ./scripts/build-and-push.sh

REPO_NAME="openwebui-umbc"
PLATFORM="linux/arm64"
TAG_SUFFIX="extras1"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag-suffix) TAG_SUFFIX="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,16p' "$0"
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TFVARS="$REPO_ROOT/terraform.tfvars"

if [[ ! -f "$TFVARS" ]]; then
    echo "ERROR: $TFVARS not found" >&2
    exit 1
fi

CURRENT_IMAGE_URL=$(grep -E '^[[:space:]]*open_webui_image_url' "$TFVARS" | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
if [[ -z "$CURRENT_IMAGE_URL" ]]; then
    echo "ERROR: could not parse open_webui_image_url from $TFVARS" >&2
    exit 1
fi

if [[ -n "${OPENWEBUI_UPSTREAM:-}" ]]; then
    UPSTREAM_TAG="$OPENWEBUI_UPSTREAM"
    UPSTREAM_IMAGE="ghcr.io/open-webui/open-webui:${UPSTREAM_TAG}"
elif [[ "$CURRENT_IMAGE_URL" == ghcr.io/open-webui/open-webui:* ]]; then
    UPSTREAM_IMAGE="$CURRENT_IMAGE_URL"
    UPSTREAM_TAG="${CURRENT_IMAGE_URL##*:}"
else
    echo "ERROR: terraform.tfvars open_webui_image_url already points at ECR." >&2
    echo "       Set OPENWEBUI_UPSTREAM=vX.Y.Z to specify the upstream version." >&2
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
if [[ -z "$AWS_REGION" ]]; then
    echo "ERROR: AWS region not set (export AWS_REGION or set 'aws configure get region')" >&2
    exit 1
fi

ECR_HOST="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_URI="${ECR_HOST}/${REPO_NAME}"
OUTPUT_TAG="${UPSTREAM_TAG}-${TAG_SUFFIX}"

if ! aws ecr describe-repositories --repository-names "$REPO_NAME" >/dev/null 2>&1; then
    echo "ERROR: ECR repo '$REPO_NAME' does not exist in account ${AWS_ACCOUNT_ID}/${AWS_REGION}." >&2
    echo "       Run 'terraform apply' first to create it." >&2
    exit 1
fi

echo "Upstream:   $UPSTREAM_IMAGE"
echo "Target:     ${ECR_URI}:${OUTPUT_TAG}  (also tagged :latest)"
echo "Platform:   $PLATFORM"
echo

if ! docker buildx version >/dev/null 2>&1; then
    echo "ERROR: docker buildx not available. Install Docker Desktop or buildx plugin." >&2
    exit 1
fi

aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$ECR_HOST"

BUILDER_NAME="openwebui-umbc-builder"
if ! docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
    docker buildx create --name "$BUILDER_NAME" --use >/dev/null
else
    docker buildx use "$BUILDER_NAME"
fi

docker buildx build \
    --platform "$PLATFORM" \
    --build-arg "BASE_IMAGE=${UPSTREAM_IMAGE}" \
    --tag "${ECR_URI}:${OUTPUT_TAG}" \
    --tag "${ECR_URI}:latest" \
    --push \
    "$REPO_ROOT/docker"

echo
echo "Pushed: ${ECR_URI}:${OUTPUT_TAG}"
echo
echo "Next step: update terraform.tfvars:"
echo "  open_webui_image_url = \"${ECR_URI}:${OUTPUT_TAG}\""
echo "Then run: terraform apply"
