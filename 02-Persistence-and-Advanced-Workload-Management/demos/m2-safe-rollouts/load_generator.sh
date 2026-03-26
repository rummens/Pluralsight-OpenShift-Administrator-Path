#!/usr/bin/env bash
# Load generator for OpenShift route
# - Fetches the route host once, then starts multiple background workers that
#   continuously curl the host to generate load.
# - Configurable via env/args: CONCURRENCY, REQUEST_DELAY, ROUTE_NAME, NAMESPACE, SCHEME

set -euo pipefail

# Defaults (can be overridden by env vars or CLI args)
CONCURRENCY=${CONCURRENCY:-10}
REQUEST_DELAY=${REQUEST_DELAY:-0}   # seconds to sleep between requests in each worker (float supported)
ROUTE_NAME=${ROUTE_NAME:-website}
NAMESPACE=${NAMESPACE:-}
SCHEME=${SCHEME:-https}
PAGE=${PAGE:-/}
SHOW_BODY=${SHOW_BODY:-false}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options (can also be set via env vars):
  -c, --concurrency N    Number of parallel workers (default: $CONCURRENCY)
  -d, --delay S          Delay between requests per worker in seconds (default: $REQUEST_DELAY)
  -r, --route NAME       Route name to query (default: $ROUTE_NAME)
  -n, --namespace NS     Namespace where the route lives (default: current project)
  -s, --scheme SCHEME    http or https (default: $SCHEME)
  -p, --page PATH        Page/path to request on the host (default: $PAGE)
  -b, --body             Print the response body instead of only the HTTP status code (default: off)
  -h, --help             Show this help

Examples:
  CONCURRENCY=50 ./load_generator.sh
  ./load_generator.sh -c 20 -d 0.1 -r website -n myproject -p /some/page
  ./load_generator.sh -b   # show response bodies
EOF
}

# Parse CLI args (simple)
while [[ ${#} -gt 0 ]]; do
  case "$1" in
    -c|--concurrency)
      CONCURRENCY="$2"; shift 2;;
    -d|--delay)
      REQUEST_DELAY="$2"; shift 2;;
    -r|--route)
      ROUTE_NAME="$2"; shift 2;;
    -n|--namespace)
      NAMESPACE="$2"; shift 2;;
    -s|--scheme)
      SCHEME="$2"; shift 2;;
    -p|--page)
      PAGE="$2"; shift 2;;
    -b|--body)
      SHOW_BODY=true; shift 1;;
    -h|--help)
      usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 2;;
  esac
done

# Determine namespace arg for oc if provided
OC_NS_ARG=()
if [ -n "$NAMESPACE" ]; then
  OC_NS_ARG=( -n "$NAMESPACE" )
fi

# Fetch route host once, retry a few times if needed
get_route_host() {
  local tries=0
  local max_tries=6
  local host
  while ((tries < max_tries)); do
    if host=$(oc get route "$ROUTE_NAME" -o jsonpath='{.spec.host}' "${OC_NS_ARG[@]}" 2>/dev/null || true); then
      if [ -n "$host" ]; then
        printf '%s' "$host"
        return 0
      fi
    fi
    tries=$((tries+1))
    echo "Could not get route '$ROUTE_NAME' (attempt $tries/$max_tries). Retrying in 2s..." >&2
    sleep 2
  done
  return 1
}

HOST=$(get_route_host) || { echo "Failed to resolve route '$ROUTE_NAME'. Exiting." >&2; exit 3; }

# Normalize page to start with a leading slash
if [ -z "$PAGE" ]; then
  PAGE="/"
fi
case "$PAGE" in
  /*) ;; # already has leading slash
  *) PAGE="/$PAGE";;
esac

TARGET="$SCHEME://$HOST$PAGE"

echo "Starting load generator"
echo "  target: $TARGET"
echo "  concurrency: $CONCURRENCY"
echo "  per-worker delay: ${REQUEST_DELAY}s"

PIDS=()

# Cleanup function to kill background workers
cleanup() {
  echo "Stopping workers..."
  for pid in "${PIDS[@]:-}"; do
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done
  # give them a moment
  sleep 0.5
  # ensure they are dead
  for pid in "${PIDS[@]:-}"; do
    if kill -0 "$pid" >/dev/null 2>&1; then
      echo "Killing lingering pid $pid" >&2
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
  done
  exit 0
}
trap cleanup INT TERM

# Worker function (runs in background)
worker() {
  local id="$1"
  local target="$2"
  local delay="$3"
  while true; do
    if [ "${SHOW_BODY}" = "true" ]; then
      # Print the response body (default behavior if user passed -b/--body or set SHOW_BODY=true)
      body=$(curl -k -sS "$target")
      rc=$?
      if [ "$rc" -ne 0 ]; then
        echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [worker $id] ERROR curl rc=$rc"
      else
        # Header line followed by the body; body may be multi-line
        echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [worker $id] BODY"
        echo "$body"
      fi
    else
      # Default: print concise HTTP status code
      status=$(curl -k -sS -o /dev/null -w '%{http_code}' "$target")
      rc=$?
      if [ "$rc" -ne 0 ]; then
        # network/connection error
        echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [worker $id] ERROR curl rc=$rc status=${status:-000}"
      else
        echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [worker $id] HTTP $status"
      fi
    fi

    # Optional per-request delay (supports floating point via sleep)
    if (( $(echo "$delay > 0" | bc -l) )); then
      sleep "$delay"
    fi
  done
}

# Start workers
for i in $(seq 1 "$CONCURRENCY"); do
  worker "$i" "$TARGET" "$REQUEST_DELAY" &
  PIDS+=("$!")
done

echo "Spawned ${#PIDS[@]} workers (pids: ${PIDS[*]})"

echo "Press Ctrl-C to stop"

# Wait for background workers (wait on the last PID will wait but we want to wait for signals)
# Use an infinite sleep to keep the script running; trap will handle cleanup
while true; do sleep 3600; done

