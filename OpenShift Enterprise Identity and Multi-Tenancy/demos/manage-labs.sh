#!/usr/bin/env bash
# Wrapper to source the reusable manage-labs library and forward CLI args.
# Do not hardcode params here — set env vars before calling or pass CLI args.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source the base implementation (three levels up)
source "$SCRIPT_DIR/../../manage-labs-base.sh"

# Forward all CLI args to the function. Users may also set env vars like
# SCRIPT_DIR, ACTION, ASSUME_YES before calling this wrapper to override defaults.
manage_labs "$@"

