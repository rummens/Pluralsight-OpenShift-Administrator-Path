#!/usr/bin/env bash
# evict-pod.sh — trigger a pod eviction via the Kubernetes Eviction API
#
# Usage: ./evict-pod.sh <pod-name> [namespace]
#
# Background: Eviction is a pod subresource (POST .../pods/{name}/eviction),
# not a top-level resource. oc/kubectl create -f can't reach it via the REST
# mapper, so we POST directly. This is the same call oc adm drain uses
# internally for each pod.

set -euo pipefail

POD=${1:?Usage: evict-pod.sh <pod-name> [namespace]}
NS=${2:-globomantics}

TOKEN=$(oc whoami -t)
APISERVER=$(oc whoami --show-server)

curl -sk -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "$APISERVER/api/v1/namespaces/$NS/pods/$POD/eviction" \
  -d "{\"apiVersion\":\"policy/v1\",\"kind\":\"Eviction\",\"metadata\":{\"name\":\"$POD\",\"namespace\":\"$NS\"}}"

echo
