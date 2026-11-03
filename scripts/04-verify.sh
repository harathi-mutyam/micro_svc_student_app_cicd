#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo '=== Cluster / resources ==='
kubectl config current-context
kubectl get nodes
kubectl get storageclass gp3
kubectl -n student-app get pods,deploy,svc,pvc,configmap
[[ "$(kubectl -n student-app get secret student-secrets -o go-template='{{len .data}}')" == '13' ]] || { echo 'ERROR: Secret does not contain 13 values'; exit 1; }
for svc in auth students attendance marks frontend gateway; do
  kubectl -n student-app rollout status deployment/$svc --timeout=60s
done
kubectl -n student-app rollout status statefulset/database --timeout=60s
kubectl -n student-app get pvc data-database-0 -o jsonpath='{.status.phase}' | grep -qx Bound
# Verify MySQL schemas using the already-configured root password from pod env.
kubectl exec -n student-app database-0 -- sh -c 'mysql --protocol=socket -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "SHOW DATABASES;"' | grep -E '^(auth_db|student_db|attendance_db|marks_db)$'
# Local port forwarding stays bound to localhost, not public EC2 interfaces.
log=$(mktemp); kubectl port-forward -n student-app svc/gateway 18080:80 >"$log" 2>&1 & pf=$!
cleanup(){ kill "$pf" 2>/dev/null || true; wait "$pf" 2>/dev/null || true; rm -f "$log"; }
trap cleanup EXIT
ready=0
for attempt in $(seq 1 25); do
  if curl -fsS --max-time 2 http://127.0.0.1:18080/ >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[[ "$ready" == 1 ]] || { cat "$log"; echo 'Gateway port-forward failed'; exit 1; }
for svc in auth students attendance marks; do
  echo "=== $svc /health ==="
  response=$(curl -fsS --max-time 8 "http://127.0.0.1:18080/api/$svc/health")
  SERVICE="$svc" RESPONSE="$response" python3 -c 'import json,os; d=json.loads(os.environ["RESPONSE"]); assert d.get("status")=="ok" and d.get("service")==os.environ["SERVICE"], d; print("PASS:",os.environ["SERVICE"])'
done
echo 'PASS: Kubernetes workloads, database schemas and API health endpoints.'
echo 'NEXT: Test admin/student UI login and create attendance/marks manually via SSH tunnel.'
