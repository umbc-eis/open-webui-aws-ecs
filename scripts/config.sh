#!/usr/bin/env bash
set -euo pipefail

# Share terraform.tfvars between operators via the Terraform state bucket.
#
# terraform.tfvars is gitignored because this repo is public and the file
# carries the VPC and subnet ids, the Cognito pool/client ids and the ALB
# certificate ARN. It holds no secrets — the OAuth client secret lives in
# Secrets Manager (see README) — but it is still environment-specific and not
# something to publish.
#
# The state bucket is already versioned, encrypted with AES256 and closed to
# public access, and every operator needs access to it anyway, so it is the
# natural home for the shared copy. The bucket name is read from backend.hcl,
# which is also gitignored, so it never appears in the repo.
#
# Usage:
#   ./scripts/config.sh pull          # fetch shared config to ./terraform.tfvars
#   ./scripts/config.sh push          # publish ./terraform.tfvars as shared
#   ./scripts/config.sh diff          # compare local against shared
#   ./scripts/config.sh versions      # list previous shared versions
#
#   pull/push refuse to clobber differing content; pass --yes to override.

REMOTE_KEY="config/terraform.tfvars"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$REPO_ROOT/backend.hcl"
LOCAL_FILE="$REPO_ROOT/terraform.tfvars"

ASSUME_YES=0
CMD=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        pull | push | diff | versions) CMD="$1"; shift ;;
        --yes | -y) ASSUME_YES=1; shift ;;
        -h | --help)
            sed -n '4,27p' "$0"
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$CMD" ]]; then
    echo "ERROR: expected one of: pull, push, diff, versions (see --help)" >&2
    exit 2
fi

if [[ ! -f "$BACKEND" ]]; then
    echo "ERROR: $BACKEND not found." >&2
    echo "       Copy backend.hcl.example to backend.hcl and fill in the bucket." >&2
    exit 1
fi

hcl_value() {
    # Read a top-level `key = "value"` out of backend.hcl.
    grep -E "^[[:space:]]*$1[[:space:]]*=" "$BACKEND" \
        | head -1 \
        | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/'
}

BUCKET="$(hcl_value bucket)"
REGION="$(hcl_value region)"
: "${REGION:=${AWS_REGION:-us-east-1}}"

if [[ -z "$BUCKET" ]]; then
    echo "ERROR: could not parse 'bucket' from $BACKEND" >&2
    exit 1
fi

S3_URI="s3://${BUCKET}/${REMOTE_KEY}"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

remote_exists() {
    aws s3api head-object --bucket "$BUCKET" --key "$REMOTE_KEY" \
        --region "$REGION" >/dev/null 2>&1
}

fetch_remote() {
    aws s3 cp "$S3_URI" "$TMP" --region "$REGION" --quiet
}

confirm() {
    [[ "$ASSUME_YES" -eq 1 ]] && return 0
    read -r -p "$1 [y/N] " reply
    [[ "$reply" == "y" || "$reply" == "Y" ]]
}

case "$CMD" in
    diff)
        if ! remote_exists; then
            echo "No shared config at $S3_URI yet. Run: $0 push"
            exit 0
        fi
        fetch_remote
        if diff -u "$TMP" "$LOCAL_FILE" --label "shared ($S3_URI)" --label "local (terraform.tfvars)"; then
            echo "Local and shared config are identical."
        fi
        ;;

    pull)
        if ! remote_exists; then
            echo "ERROR: no shared config at $S3_URI. Someone must push first." >&2
            exit 1
        fi
        fetch_remote
        if [[ -f "$LOCAL_FILE" ]] && ! diff -q "$TMP" "$LOCAL_FILE" >/dev/null; then
            echo "Local terraform.tfvars differs from the shared copy:"
            diff -u "$TMP" "$LOCAL_FILE" --label "shared" --label "local" || true
            confirm "Overwrite local terraform.tfvars?" || { echo "Aborted."; exit 1; }
        fi
        cp "$TMP" "$LOCAL_FILE"
        echo "Pulled $S3_URI -> $LOCAL_FILE"
        ;;

    push)
        if [[ ! -f "$LOCAL_FILE" ]]; then
            echo "ERROR: $LOCAL_FILE not found" >&2
            exit 1
        fi
        # A stray secret here would land in the bucket and in its version
        # history, so fail loudly rather than publish it.
        if grep -qE '^[[:space:]]*cognito_app_client_secret[[:space:]]*=[[:space:]]*"..*"' "$LOCAL_FILE"; then
            echo "ERROR: terraform.tfvars still sets cognito_app_client_secret." >&2
            echo "       That variable is gone; the secret belongs in Secrets Manager." >&2
            echo "       Remove the line and see the README before pushing." >&2
            exit 1
        fi
        if remote_exists; then
            fetch_remote
            if diff -q "$TMP" "$LOCAL_FILE" >/dev/null; then
                echo "Shared config already matches local. Nothing to do."
                exit 0
            fi
            echo "Changes to publish:"
            diff -u "$TMP" "$LOCAL_FILE" --label "shared" --label "local" || true
            confirm "Publish local terraform.tfvars to $S3_URI?" || { echo "Aborted."; exit 1; }
        fi
        aws s3 cp "$LOCAL_FILE" "$S3_URI" --region "$REGION" --quiet
        echo "Pushed $LOCAL_FILE -> $S3_URI"
        ;;

    versions)
        aws s3api list-object-versions --bucket "$BUCKET" --prefix "$REMOTE_KEY" \
            --region "$REGION" \
            --query 'reverse(sort_by(Versions,&LastModified))[].{When:LastModified,VersionId:VersionId,Size:Size}' \
            --output table
        echo "Restore one with:"
        echo "  aws s3api get-object --bucket $BUCKET --key $REMOTE_KEY \\"
        echo "    --version-id <VersionId> terraform.tfvars"
        ;;
esac
