#!/usr/bin/env bash
# Library-friendly build-and-push script
# - Defines build_and_push_image() so other scripts can source this file and then
#   set/override variables (e.g. REPO_NAME) before calling the function.
# - When executed directly, enables strict mode and runs the function (backwards compatible).

# When executed directly, enable strict mode. If this file is sourced, do not alter
# the caller's errexit/nounset settings.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi

build_and_push_image() {
  # Defaults (caller may override by setting env vars before sourcing or before calling)
  local GHCR_USER="${GHCR_USER:-rummens}"
  local REPO_NAME="${REPO_NAME:-pluralsight-globomantics-website}"
  local GHCR_IMAGE="${GHCR_IMAGE:-ghcr.io/${GHCR_USER}/${REPO_NAME}}"
  local TAG="${TAG:-v3}"
  local PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
  local BUILDER_NAME="${BUILDER_NAME:-ghcr-builder}"
  local TOKEN

  # Token: prefer CR_PAT, fallback to GITHUB_TOKEN
  if [ -z "${CR_PAT:-}" ] && [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "Error: set CR_PAT or GITHUB_TOKEN in the environment" >&2
    return 1
  fi
  TOKEN="${CR_PAT:-$GITHUB_TOKEN}"

  echo "Image: ${GHCR_IMAGE}:${TAG}"
  echo "Platforms: ${PLATFORMS}"

  # Ensure docker buildx exists
  if ! docker buildx version >/dev/null 2>&1; then
    echo "Error: docker buildx not available. Install Docker Desktop or enable buildx." >&2
    return 1
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
  local FULL_TAG="${GHCR_IMAGE}:${TAG}"
  docker buildx build \
    --platform "${PLATFORMS}" \
    -t "${FULL_TAG}" \
    --push \
    .

  echo "Pushed ${FULL_TAG}"
}

# If executed (not sourced), run the function with any provided args
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  build_and_push_image "$@"
fi
