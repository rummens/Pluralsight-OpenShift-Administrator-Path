#!/usr/bin/env bash

# Library-friendly manage-labs script
# - Defines manage_labs() so other scripts can source this file and then
#   set/override variables (e.g. SCRIPT_DIR, ACTION, ASSUME_YES) before calling.
# - Avoids process substitution so it's safer when invoked from environments
#   that don't support `< <(...)`.

# Enable strict mode only when executed directly (not when sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Apply or remove all Kubernetes manifests found in immediate subfolders (one level) of the script directory.

Options:
  -a, --apply       Apply manifests (default)
  -r, --remove      Remove (delete) manifests
  -y, --yes         Assume yes for destructive actions (skip confirmation for remove)
  -h, --help        Show this help message

Examples:
  $(basename "$0") --apply    # apply all manifests in subfolders
  $(basename "$0") --remove -y # delete all manifests without confirmation
EOF
}

manage_labs() {
  # Allow caller to predefine SCRIPT_DIR/ACTION/ASSUME_YES before calling.
  local SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
  local ACTION="${ACTION:-apply}"
  local ASSUME_YES="${ASSUME_YES:-false}"

  # Parse any arguments passed to the function (optional when calling)
  while [[ ${#} -gt 0 ]]; do
    case "$1" in
      -a|--apply)
        ACTION=apply
        shift
        ;;
      -r|--remove)
        ACTION=delete
        shift
        ;;
      -y|--yes)
        ASSUME_YES=true
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        return 2
        ;;
    esac
  done

  # Ensure oc is available
  if ! command -v oc >/dev/null 2>&1; then
    echo "Error: oc not found in PATH. Please install the OpenShift CLI (oc) and ensure it's available." >&2
    return 3
  fi

  # If deleting, confirm unless ASSUME_YES
  if [[ "$ACTION" == "delete" && "${ASSUME_YES}" != true ]]; then
    echo "You are about to delete resources defined in manifests under subfolders of: $SCRIPT_DIR"
    read -r -p "Are you sure you want to continue? [y/N] " ans
    case "$ans" in
      [yY]|[yY][eE][sS]) ;;
      *) echo "Cancelled."; return 0 ;;
    esac
  fi

  echo "Running 'oc $ACTION' on manifests found in immediate subfolders of: $SCRIPT_DIR"

  local FOUND_ANY=false

  # Iterate immediate subdirectories
  local dir
  for dir in "$SCRIPT_DIR"/*/; do
    [ -d "$dir" ] || continue

    # Collect files one level deep inside this subdir (not recursive)
    local files=()
    local ns_file=""
    local f
    # Look specifically for a namespace file named namespace.yaml or namespace.yml
    for f in "$dir"namespace.yaml "$dir"namespace.yml; do
      if [ -f "$f" ]; then
        ns_file="$f"
        break
      fi
    done

    # If we found a namespace file, try to determine the namespace name (used for waiting/deleting)
    local ns_name=""
    if [ -n "$ns_file" ]; then
      ns_name=$(awk '/^metadata:/{found=1;next} found && /^[[:space:]]*name:/{sub(/^[[:space:]]*name:[[:space:]]*/,"",$0); print $0; exit} END{ if(!found) exit 1 }' "$ns_file" 2>/dev/null || true)
      if [ -z "$ns_name" ]; then
        ns_name=$(awk '/^[[:space:]]*name:/{sub(/^[[:space:]]*name:[[:space:]]*/,"",$0); print $0; exit}' "$ns_file" 2>/dev/null || true)
      fi
      if [ -n "$ns_name" ]; then
        ns_name=$(printf '%s' "$ns_name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')
      fi
    fi

    # Collect remaining manifest files (exclude the namespace file so we can apply it first)
    for f in "$dir"*.yml "$dir"*.yaml "$dir"*.json; do
      # skip non-files and the namespace file we handled specially
      [ -f "$f" ] || continue
      if [ -n "$ns_file" ] && [ "$f" = "$ns_file" ]; then
        continue
      fi
      files+=("$f")
    done

    # Do not append namespace file to the general files list during deletion; we'll handle
    # namespace deletion explicitly after other resources are attempted.
    # (This avoids cases where oc delete -f on the namespace can fail silently and
    # prevents us from performing fallback delete-by-name.)
    # noop here

    # Human-friendly names
    local human_dir
    human_dir=$(basename "$dir")

    # If applying and a namespace file exists, apply it first and wait until namespace is visible
    if [[ "$ACTION" == "apply" && -n "$ns_file" ]]; then
      echo "Found namespace file: $(basename "$ns_file") — applying first in ${human_dir}"
      if ! oc apply -f "$ns_file"; then
        echo "Warning: failed to apply namespace file: $(basename "$ns_file")" >&2
      else
        # Try to extract the namespace name from the YAML. Look for metadata.name; fallback to first 'name:' occurrence.
        ns_name=$(awk '/^metadata:/{found=1;next} found && /^[[:space:]]*name:/{sub(/^[[:space:]]*name:[[:space:]]*/,"",$0); print $0; exit} END{ if(!found) exit 1 }' "$ns_file" 2>/dev/null || true)
        if [ -z "$ns_name" ]; then
          ns_name=$(awk '/^[[:space:]]*name:/{sub(/^[[:space:]]*name:[[:space:]]*/,"",$0); print $0; exit}' "$ns_file" 2>/dev/null || true)
        fi
        if [ -n "$ns_name" ]; then
          # Clean up namespace name: trim whitespace and surrounding quotes
          ns_name=$(printf '%s' "$ns_name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')
          echo "Waiting for namespace '$ns_name' to be created..."
          # Poll for namespace existence (timeout after ~30s)
          for _ in 1 2 3 4 5 6; do
            if oc get namespace "$ns_name" >/dev/null 2>&1; then
              echo "Namespace '$ns_name' exists"
              break
            fi
            sleep 5
          done
          if ! oc get namespace "$ns_name" >/dev/null 2>&1; then
            echo "Warning: namespace '$ns_name' not found after waiting" >&2
          fi
        else
          echo "Applied namespace file but could not determine namespace name to wait for; continuing" >&2
        fi
      fi
    fi

    if (( ${#files[@]} )); then
      FOUND_ANY=true
      echo
      echo "Processing directory: ${human_dir}"
      # Run oc per file so a failure on one doesn't stop the others (namespace deletion will still be attempted)
      local f
      for f in "${files[@]}"; do
        local bname
        bname=$(basename "$f")
        echo "oc $ACTION -f ${bname}"
        if ! oc "$ACTION" -f "$f"; then
          echo "Warning: 'oc $ACTION -f ${bname}' failed; continuing" >&2
        fi
      done
    fi

    # After attempting per-file deletes, if we're deleting and a namespace file exists,
    # try deleting the namespace resource file first, then fall back to delete-by-name.
    if [[ "$ACTION" == "delete" && -n "$ns_file" ]]; then
      bnsfile=$(basename "$ns_file")
      echo "Attempting to delete namespace resource file: ${bnsfile} in ${human_dir}"
      if ! oc delete -f "$ns_file"; then
        echo "Warning: 'oc delete -f ${bnsfile}' failed; will attempt delete-by-name if possible" >&2
        if [ -n "$ns_name" ] && oc get namespace "$ns_name" >/dev/null 2>&1; then
          echo "Attempting to delete namespace by name: ${ns_name}"
          if ! oc delete namespace "$ns_name"; then
            echo "Warning: 'oc delete namespace ${ns_name}' failed; attempting asynchronous delete" >&2
            oc delete namespace "$ns_name" --wait=false || true
          fi
        else
          echo "Could not determine namespace name or namespace not found; manual cleanup may be required" >&2
        fi
      else
        echo "Deleted namespace resource file ${bnsfile}; waiting for namespace to disappear (if named)"
      fi

      # Regardless of whether oc delete -f succeeded, if we know ns_name try to ensure it's gone
      if [ -n "$ns_name" ]; then
        for _ in 1 2 3 4 5 6; do
          if ! oc get namespace "$ns_name" >/dev/null 2>&1; then
            echo "Namespace '${ns_name}' removed"
            break
          fi
          sleep 5
        done
        if oc get namespace "$ns_name" >/dev/null 2>&1; then
          echo "Warning: namespace '${ns_name}' still exists after attempted deletion; you may need cluster privileges to remove it" >&2
        fi
      fi
    fi
  done

  if [[ "$FOUND_ANY" == false ]]; then
    echo "No manifest files found in immediate subfolders of: $SCRIPT_DIR"
  fi

  return 0
}

# If executed (not sourced), run the function with any provided args and exit with its status
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  manage_labs "$@"
  exit $?
fi
