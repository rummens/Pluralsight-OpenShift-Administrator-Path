#!/usr/bin/env bash
set -euo pipefail

# Defaults (override by exporting env vars)
: "${GHCR_USER:=rummens}"
: "${REPO_NAME:=pluralsight-openshift-fundamentals-and-workload-deployment}"
: "${GHCR_IMAGE:=ghcr.io/${GHCR_USER}/${REPO_NAME}}"
: "${TAG:=$(git rev-parse --short HEAD 2>/dev/null || echo latest)}"
: "${PLATFORMS:=linux/amd64,linux/arm64}"
BUILDER_NAME="ghcr-builder"

# Token: prefer CR_PAT, fallback to GITHUB_TOKEN
if [ -z "${CR_PAT:-}" ] && [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "Error: set CR_PAT or GITHUB_TOKEN in the environment" >&2
  exit 1
fi
TOKEN="${CR_PAT:-$GITHUB_TOKEN}"

echo "Image: ${GHCR_IMAGE}:${TAG}"
echo "Platforms: ${PLATFORMS}"

# Ensure docker buildx exists
if ! docker buildx version >/dev/null 2>&1; then
  echo "Error: docker buildx not available. Install Docker Desktop or enable buildx." >&2
  exit 1
fi

# Create or use builder
if ! docker buildx inspect "${BUILDER_NAME}" >/dev/null 2>&1; then
  docker buildx create --use --name "${BUILDER_NAME}"
else
  docker buildx use "${BUILDER_NAME}"
fi

# Register QEMU for cross-building (best-effort)
docker run --rm --privileged tonistiigi/binfmt --install all >/dev/null 2>&1 || true

# Login to GitHub Container Registry
echo "${TOKEN}" | docker login ghcr.io -u "${GHCR_USER}" --password-stdin

# Build and push multi-arch image
FULL_TAG="${GHCR_IMAGE}:${TAG}"
docker buildx build \
  --platform "${PLATFORMS}" \
  -t "${FULL_TAG}" \
  --push \
  .

echo "Pushed ${FULL_TAG}"