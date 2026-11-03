#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.." 2>/dev/null || true
[[ -f .env.k8s && -f database/init.sh && -f gateway/nginx.conf ]] || { echo 'Missing .env.k8s, database/init.sh or gateway/nginx.conf' >&2; exit 1; }
kubectl config current-context
# Existing resources are updated in place; no delete/recreate commands.
kubectl apply -f k8s/namespace.yaml
kubectl -n student-app create secret generic student-secrets --from-env-file=.env.k8s --dry-run=client -o yaml | kubectl apply -f -
kubectl -n student-app create configmap mysql-init --from-file=init.sh=database/init.sh --dry-run=client -o yaml | kubectl apply -f -
kubectl -n student-app create configmap nginx-config --from-file=nginx.conf=gateway/nginx.conf --dry-run=client -o yaml | kubectl apply -f -
kubectl -n student-app get secret student-secrets -o go-template='Secret: {{len .data}} keys{{"\n"}}'
kubectl -n student-app get configmap mysql-init nginx-config
printf '\nIMPORTANT: Updating a Secret does not change MySQL users/passwords already stored in a populated PVC.\n'
