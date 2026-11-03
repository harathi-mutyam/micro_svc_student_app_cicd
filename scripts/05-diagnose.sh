#!/usr/bin/env bash
set -euo pipefail
kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -n student-app -o wide
kubectl get deployments,statefulsets,pvc -n student-app
kubectl get events -n student-app --sort-by=.lastTimestamp | tail -40
for svc in database auth students attendance marks frontend gateway; do
 echo "======== $svc logs ========"
 if [[ "$svc" == database ]]; then kubectl logs -n student-app database-0 --tail=30 || true
 else kubectl logs -n student-app deployment/$svc --tail=30 || true; fi
done
