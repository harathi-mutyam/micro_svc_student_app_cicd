#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# Student Microservices - EKS Deployment
# Full 40-character GitHub Commit SHA
# ==========================================

cd "$(dirname "$0")/.."

: "${DOCKERHUB_USERNAME:?Export DOCKERHUB_USERNAME first}"
: "${IMAGE_TAG:?Export full 40-character IMAGE_TAG first}"

# Validate input
[[ "$DOCKERHUB_USERNAME" =~ ^[a-z0-9_-]+$ ]] || {
  echo "ERROR: Invalid Docker Hub username"
  exit 1
}

[[ "$IMAGE_TAG" =~ ^[0-9a-f]{40}$ ]] || {
  echo "ERROR: IMAGE_TAG must be a 40-character lowercase Git SHA"
  exit 1
}

echo "========================================"
echo "Student Microservices EKS Deployment"
echo "========================================"
echo "Docker Hub User: $DOCKERHUB_USERNAME"
echo "Full Image SHA: $IMAGE_TAG"

# Verify manifest files
for svc in auth students attendance marks frontend gateway; do
  [[ -f "k8s/$svc.yaml" ]] || {
    echo "ERROR: Missing k8s/$svc.yaml"
    exit 1
  }
done

[[ -f k8s/gp3-storageclass.yaml ]] || {
  echo "ERROR: Missing gp3 StorageClass manifest"
  exit 1
}

[[ -f k8s/platform.yaml ]] || {
  echo "ERROR: Missing MySQL platform manifest"
  exit 1
}

# Verify Kubernetes connection
echo ""
echo "Checking Kubernetes context..."
kubectl config current-context
kubectl cluster-info

# Verify namespace
kubectl get namespace student-app >/dev/null

# Verify Kubernetes Secret (13 keys)
echo ""
echo "Checking Kubernetes Secret..."

SECRET_COUNT=$(
  kubectl -n student-app get secret student-secrets \
    -o go-template='{{len .data}}'
)

[[ "$SECRET_COUNT" == "13" ]] || {
  echo "ERROR: Expected 13 Secret keys, found $SECRET_COUNT"
  exit 1
}

echo "PASS: student-secrets contains 13 keys"

# Verify ConfigMaps
kubectl -n student-app get configmap mysql-init nginx-config

echo "PASS: Required ConfigMaps exist"

# ==========================================
# Prepare temporary Kubernetes manifests
# ==========================================

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo ""
echo "Preparing Kubernetes manifests with full SHA..."

for svc in auth students attendance marks frontend; do

  sed -E \
    -e "s|REPLACE_DOCKERHUB_USER/student-${svc}:REPLACE_IMAGE_TAG|${DOCKERHUB_USERNAME}/student-${svc}:${IMAGE_TAG}|g" \
    -e "s|[[:alnum:]_.-]+/student-${svc}:[[:alnum:]_.-]+|${DOCKERHUB_USERNAME}/student-${svc}:${IMAGE_TAG}|g" \
    "k8s/${svc}.yaml" > "$work/${svc}.yaml"

  IMAGE="${DOCKERHUB_USERNAME}/student-${svc}:${IMAGE_TAG}"

  grep -Fq "image: $IMAGE" "$work/${svc}.yaml" || {
    echo "ERROR: Image reference not found for $svc"
    exit 1
  }

  echo "Prepared: $IMAGE"

done

# ==========================================
# Configure gp3 EBS storage
# ==========================================

echo ""
echo "Checking EBS CSI driver..."

kubectl get csidriver ebs.csi.aws.com >/dev/null || {
  echo "ERROR: AWS EBS CSI driver not found"
  exit 1
}

echo "Applying gp3 StorageClass..."

kubectl apply -f k8s/gp3-storageclass.yaml

# ==========================================
# Deploy MySQL
# ==========================================

echo ""
echo "Deploying MySQL StatefulSet..."

kubectl apply -f k8s/platform.yaml

kubectl -n student-app rollout status \
  statefulset/database \
  --timeout=600s

echo "PASS: MySQL StatefulSet ready"

kubectl get pvc -n student-app

# ==========================================
# Deploy FastAPI microservices
# ==========================================

for svc in auth students attendance marks; do

  echo ""
  echo "Deploying $svc..."

  kubectl apply --dry-run=server \
    -f "$work/${svc}.yaml" >/dev/null

  kubectl apply -f "$work/${svc}.yaml"

  kubectl -n student-app rollout status \
    "deployment/$svc" \
    --timeout=300s

  echo "PASS: $svc deployment ready"

done

# ==========================================
# Deploy PHP frontend
# ==========================================

echo ""
echo "Deploying frontend..."

kubectl apply --dry-run=server \
  -f "$work/frontend.yaml" >/dev/null

kubectl apply -f "$work/frontend.yaml"

kubectl -n student-app rollout status \
  deployment/frontend \
  --timeout=300s

echo "PASS: Frontend ready"

# ==========================================
# Deploy NGINX gateway
# ==========================================

echo ""
echo "Deploying NGINX gateway..."

kubectl apply -f k8s/gateway.yaml

kubectl -n student-app rollout status \
  deployment/gateway \
  --timeout=300s

echo "PASS: Gateway ready"

# ==========================================
# Final verification
# ==========================================

echo ""
echo "========================================"
echo "Final Kubernetes Status"
echo "========================================"

kubectl -n student-app get pods
kubectl -n student-app get deployments
kubectl -n student-app get services
kubectl -n student-app get pvc

echo ""
echo "SUCCESS: All Student Microservices deployed"
echo "Docker Hub: $DOCKERHUB_USERNAME"
echo "Image SHA: $IMAGE_TAG"
