#!/usr/bin/env bash
set -euo pipefail
# Ubuntu 24.04, x86_64 management EC2 only; does not configure AWS credentials.
[[ "$(uname -m)" == "x86_64" ]] || { echo 'This installer supports x86_64 only'; exit 1; }
sudo apt-get update
sudo apt-get install -y git curl wget unzip jq python3 ca-certificates gnupg lsb-release
# Terraform via official HashiCorp apt repository.
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com %s main\n' "$(dpkg --print-architecture)" "$(. /etc/os-release && echo "$VERSION_CODENAME")" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
sudo apt-get update
sudo apt-get install -y terraform
# AWS CLI v2 official installer.
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o "$work/awscliv2.zip"
(cd "$work" && unzip -q awscliv2.zip)
sudo "$work/aws/install" --update
# EKS Kubernetes 1.34-compatible kubectl, pinned official binary and checksum.
curl -fsSL https://s3.us-west-2.amazonaws.com/amazon-eks/1.34.9/2026-07-05/bin/linux/amd64/kubectl -o "$work/kubectl"
curl -fsSL https://s3.us-west-2.amazonaws.com/amazon-eks/1.34.9/2026-07-05/bin/linux/amd64/kubectl.sha256 -o "$work/kubectl.sha256"
(cd "$work" && sha256sum -c kubectl.sha256)
sudo install -m 0755 "$work/kubectl" /usr/local/bin/kubectl
# Helm official Helm 3 installer.
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o "$work/get-helm-3"
chmod 700 "$work/get-helm-3"
"$work/get-helm-3"
terraform version | head -1
aws --version
kubectl version --client
helm version --short
