#!/usr/bin/env bash

# Library-friendly manage-labs script
# - Defines manage_labs() so other scripts can source this file and then
#   set/override variables (e.g. SCRIPT_DIR, ACTION, ASSUME_YES, FULL,
#   DEMO_FOLDER) before calling.
# - When executed directly, parses CLI args and calls manage_labs.

# Enable strict mode only when executed directly (not when sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <demo-folder>

Apply or delete the Kubernetes manifests for a demo.

By default only manifests inside <demo-folder>/setup/ are processed.
Pass --full to process the whole demo folder recursively.

Positional:
  <demo-folder>     Demo folder name (resolved relative to the script
                    directory) or an explicit path to a demo folder.

Options:
  -a, --apply       Apply manifests (default)
  -d, --delete      Delete manifests (matches 'oc delete')
  -f, --full        Process the whole demo folder, not just setup/
  -y, --yes         Skip the confirmation prompt when deleting
  -h, --help        Show this help

Examples:
  $(basename "$0") my-demo                # apply my-demo/setup/
  $(basename "$0") --full my-demo         # apply everything under my-demo/
  $(basename "$0") --delete -y my-demo    # delete my-demo/setup/, no prompt
  $(basename "$0") -d -f my-demo          # delete everything under my-demo/

Notes:
  - A file named namespace.yaml (or .yml) inside <demo-folder>/setup/
    is applied first (and deleted last) so dependent resources land in
    the namespace they expect.
  - Manifest discovery is recursive within the chosen target.
EOF
}

# Best-effort extract of metadata.name from a single-document YAML
_extract_ns_name() {
  local file="$1"
  awk '
    /^metadata:/ { in_meta=1; next }
    in_meta && /^[[:space:]]*name:/ {
      sub(/^[[:space:]]*name:[[:space:]]*/, "")
      gsub(/"/, "")
      sub(/[[:space:]]+$/, "")
      print
      exit
    }
    /^[^[:space:]]/ && in_meta { in_meta=0 }
  ' "$file" 2>/dev/null
}

manage_labs() {
  local SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
  local ACTION="${ACTION:-apply}"
  local ASSUME_YES="${ASSUME_YES:-false}"
  local FULL="${FULL:-false}"
  local DEMO_FOLDER="${DEMO_FOLDER:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--apply)  ACTION=apply; shift ;;
      -d|--delete) ACTION=delete; shift ;;
      -f|--full)   FULL=true; shift ;;
      -y|--yes)    ASSUME_YES=true; shift ;;
      -h|--help)   usage; return 0 ;;
      --)
        shift
        if [[ -n "${1:-}" ]]; then
          DEMO_FOLDER="$1"
          shift
        fi
        break
        ;;
      -*)
        echo "Unknown option: $1" >&2
        usage
        return 2
        ;;
      *)
        if [[ -n "$DEMO_FOLDER" ]]; then
          echo "Error: only one demo folder may be specified (got '$DEMO_FOLDER' and '$1')" >&2
          return 2
        fi
        DEMO_FOLDER="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$DEMO_FOLDER" ]]; then
    echo "Error: <demo-folder> is required" >&2
    usage
    return 2
  fi

  # Resolve demo folder: try as-given (relative to CWD), then under SCRIPT_DIR.
  local demo_path=""
  if [[ -d "$DEMO_FOLDER" ]]; then
    demo_path=$(cd "$DEMO_FOLDER" && pwd)
  elif [[ -d "$SCRIPT_DIR/$DEMO_FOLDER" ]]; then
    demo_path=$(cd "$SCRIPT_DIR/$DEMO_FOLDER" && pwd)
  else
    echo "Error: demo folder not found: '$DEMO_FOLDER'" >&2
    echo "       (searched current directory and '$SCRIPT_DIR')" >&2
    return 2
  fi

  if ! command -v oc >/dev/null 2>&1; then
    echo "Error: oc not found in PATH. Install the OpenShift CLI and try again." >&2
    return 3
  fi

  # Pick the target directory (setup-only by default, full demo with --full)
  local target_dir
  if [[ "$FULL" == true ]]; then
    target_dir="$demo_path"
  else
    target_dir="$demo_path/setup"
    if [[ ! -d "$target_dir" ]]; then
      echo "Error: setup folder not found: $target_dir" >&2
      echo "Hint: pass --full to process the whole demo folder, or create a setup/ subfolder." >&2
      return 2
    fi
  fi

  # Confirm destructive action
  if [[ "$ACTION" == "delete" && "$ASSUME_YES" != true ]]; then
    echo "About to 'oc delete' resources defined under: $target_dir"
    read -r -p "Continue? [y/N] " ans
    case "$ans" in
      [yY]|[yY][eE][sS]) ;;
      *) echo "Cancelled."; return 0 ;;
    esac
  fi

  # Locate the namespace file (prefer setup/namespace.* even in --full mode)
  local ns_file=""
  local cand
  for cand in \
      "$demo_path/setup/namespace.yaml" \
      "$demo_path/setup/namespace.yml" \
      "$target_dir/namespace.yaml" \
      "$target_dir/namespace.yml"; do
    if [[ -f "$cand" ]]; then
      ns_file="$cand"
      break
    fi
  done

  local ns_name=""
  if [[ -n "$ns_file" ]]; then
    ns_name=$(_extract_ns_name "$ns_file")
  fi

  # Collect manifests (recursive) excluding the namespace file
  local files=()
  local f
  while IFS= read -r f; do
    if [[ -n "$ns_file" && "$f" == "$ns_file" ]]; then
      continue
    fi
    files+=("$f")
  done < <(find "$target_dir" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' \) | LC_ALL=C sort)

  echo "Action: $ACTION"
  echo "Target: $target_dir"
  [[ -n "$ns_file" ]] && echo "Namespace file: $ns_file${ns_name:+ (name=$ns_name)}"
  echo "Manifest files: ${#files[@]}"

  if [[ "$ACTION" == "apply" ]]; then
    if [[ -n "$ns_file" ]]; then
      echo "oc apply -f $(basename "$ns_file")  # namespace first"
      if ! oc apply -f "$ns_file"; then
        echo "Warning: failed to apply namespace file" >&2
      elif [[ -n "$ns_name" ]]; then
        echo "Waiting for namespace '$ns_name'..."
        local i
        for i in 1 2 3 4 5 6; do
          if oc get namespace "$ns_name" >/dev/null 2>&1; then
            break
          fi
          sleep 5
        done
        if ! oc get namespace "$ns_name" >/dev/null 2>&1; then
          echo "Warning: namespace '$ns_name' not visible after waiting" >&2
        fi
      fi
    fi
    for f in "${files[@]}"; do
      echo "oc apply -f $(basename "$f")"
      if ! oc apply -f "$f"; then
        echo "Warning: 'oc apply -f $(basename "$f")' failed; continuing" >&2
      fi
    done
  else
    # delete: namespaced resources first, then namespace last
    for f in "${files[@]}"; do
      echo "oc delete -f $(basename "$f")"
      if ! oc delete -f "$f" --ignore-not-found; then
        echo "Warning: 'oc delete -f $(basename "$f")' failed; continuing" >&2
      fi
    done
    if [[ -n "$ns_file" ]]; then
      echo "oc delete -f $(basename "$ns_file")  # namespace last"
      oc delete -f "$ns_file" --ignore-not-found || true
      if [[ -n "$ns_name" ]]; then
        local i
        for i in 1 2 3 4 5 6; do
          if ! oc get namespace "$ns_name" >/dev/null 2>&1; then
            echo "Namespace '$ns_name' removed"
            break
          fi
          sleep 5
        done
        if oc get namespace "$ns_name" >/dev/null 2>&1; then
          echo "Warning: namespace '$ns_name' still exists; you may need cluster privileges to remove it" >&2
        fi
      fi
    fi
  fi

  return 0
}

# If executed (not sourced), run the function with provided args
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  manage_labs "$@"
  exit $?
fi
