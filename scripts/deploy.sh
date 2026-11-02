#!/usr/bin/env bash
set -euo pipefail
: "${DOCKERHUB_USERNAME:?Set DOCKERHUB_USERNAME}"
: "${IMAGE_TAG:?Set IMAGE_TAG to successful CI commit SHA}"
: "${ENV_FILE:=.env}"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE"; exit 1; }
[[ -f database/init.sh && -f gateway/nginx.conf ]] || { echo "Run at project root"; exit 1; }
kubectl apply -f k8s/namespace.yaml 2>/dev/null || kubectl create namespace student-app --dry-run=client -o yaml | kubectl apply -f -
# These are demo local secrets; production use Secrets Manager + external-secrets.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
for key in MYSQL_ROOT_PASSWORD AUTH_DB_PASSWORD STUDENT_DB_PASSWORD ATTENDANCE_DB_PASSWORD MARKS_DB_PASSWORD JWT_SECRET DEMO_ADMIN_PASSWORD DEMO_STUDENT_PASSWORD PASSWORD_ENCRYPTION_KEY; do
  [[ -n "${!key:-}" ]] || { echo "Missing $key"; exit 1; }
done
kubectl -n student-app create secret generic student-secrets \
  --from-literal=MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
  --from-literal=AUTH_DB_PASSWORD="$AUTH_DB_PASSWORD" \
  --from-literal=STUDENT_DB_PASSWORD="$STUDENT_DB_PASSWORD" \
  --from-literal=ATTENDANCE_DB_PASSWORD="$ATTENDANCE_DB_PASSWORD" \
  --from-literal=MARKS_DB_PASSWORD="$MARKS_DB_PASSWORD" \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=DEMO_ADMIN_PASSWORD="$DEMO_ADMIN_PASSWORD" \
  --from-literal=DEMO_STUDENT_PASSWORD="$DEMO_STUDENT_PASSWORD" \
  --from-literal=PASSWORD_ENCRYPTION_KEY="$PASSWORD_ENCRYPTION_KEY" \
  --from-literal=AUTH_DATABASE_URL="mysql+pymysql://auth_user:${AUTH_DB_PASSWORD}@database:3306/auth_db" \
  --from-literal=STUDENTS_DATABASE_URL="mysql+pymysql://student_user:${STUDENT_DB_PASSWORD}@database:3306/student_db" \
  --from-literal=ATTENDANCE_DATABASE_URL="mysql+pymysql://attendance_user:${ATTENDANCE_DB_PASSWORD}@database:3306/attendance_db" \
  --from-literal=MARKS_DATABASE_URL="mysql+pymysql://marks_user:${MARKS_DB_PASSWORD}@database:3306/marks_db" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n student-app create configmap mysql-init --from-file=init.sh=database/init.sh --dry-run=client -o yaml | kubectl apply -f -
kubectl -n student-app create configmap nginx-config --from-file=nginx.conf=gateway/nginx.conf --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/platform.yaml
kubectl -n student-app rollout status statefulset/database --timeout=10m
for s in auth students attendance marks frontend gateway; do
  sed -e "s/REPLACE_DOCKERHUB_USER/${DOCKERHUB_USERNAME}/g" -e "s/REPLACE_IMAGE_TAG/${IMAGE_TAG}/g" "k8s/$s.yaml" | kubectl apply -f -
done
for s in auth students attendance marks frontend gateway; do kubectl -n student-app rollout status "deployment/$s" --timeout=5m; done
kubectl -n student-app get pods,svc,pvc
