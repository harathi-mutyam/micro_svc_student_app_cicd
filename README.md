# Complete Student Microservices Deployment on Amazon EKS

> **End-to-end guide:** EC2 preparation → Terraform EKS provisioning → CI/CD and Docker Hub → microservices deployment → Argo CD GitOps → Prometheus/Grafana monitoring → Loki/Alloy logging → Alertmanager → complete cleanup.

**Repository:** https://github.com/harathi-mutyam/micro_svc_student_app_cicd  
**AWS region used in the EKS setup:** `eu-north-1` (Europe – Stockholm)  
**Kubernetes namespace:** `student-app`

## Table of Contents

1. [Phase 1 – EC2 and deployment prerequisites](#phase-1--ec2-and-deployment-prerequisites)
2. [Phase 2 – Argo CD GitOps deployment](#phase-2--argo-cd-gitops-deployment)
3. [Phase 3 – Prometheus and Grafana monitoring](#phase-3--monitoring-student-microservices-on-amazon-eks)
4. [Phase 4 – Loki and Grafana Alloy logging](#phase-4-loki-and-grafana-alloy)
5. [Phase 5 – Verify S3 log persistence](#phase-5-verify-aws-s3-log-persistence)
6. [Phase 6 – Alertmanager and alert rules](#phase-6-alertmanager-setup--student-app-alerting-rules)
7. [Phase 7 – Complete cleanup and destroy](#phase-7clean-up-procedure)

## Before You Begin

- An AWS account with permissions to create EC2, IAM, VPC, EKS and S3 resources.
- A GitHub account with access to the project repository.
- A Docker Hub account and access token.
- Git Bash on your local Windows machine.
- Keep private keys, GitHub tokens, Docker Hub tokens and application passwords secret. Do not commit them to Git.
- Replace placeholders such as `YOUR_EC2_PUBLIC_IP`, `server_public_ip` and sample CIDR values with your own values.

## Command and Output Conventions

- Run commands in the **EC2 Ubuntu terminal over SSH**, unless a step explicitly says Git Bash or browser.
- Each command block is labelled with its language, such as `bash` or `json`.
- Lines beginning with `#` are comments and explain the command below them.
- Keep long-running commands such as `kubectl port-forward` running in their own terminal.
- Use a second SSH terminal for other commands while port-forwarding is active.

> **Important:** The source procedure uses `eu-north-1` for the EKS cluster setup but later sets `AWS_REGION=us-east-1` for Loki/S3. These are different regions. Keep the S3 bucket, IAM/IRSA configuration and Loki Helm values consistent with the region you actually choose. This document preserves the source procedure's values; verify them before running those commands.

### Step 1 --- Create the EC2 instance

Choose the AWS region Europe (Stockholm) --- eu-north-1, then select
Launch instance.

| Setting | Enter / select |
|---|---|
| Name | `student-server` |
| Operating system | Ubuntu Server 24.04 LTS |
| Architecture | 64-bit x86 |
| Instance type | `m7i-flex.large` |
| Key pair | `student-key-cicd.pem` (or your existing key) |
| Root storage | 40 GiB gp3 |
| Network | VPC with internet access |
| Auto-assign public IP | Enable |
| Security group | Create new: `student-management-sg` |
| Inbound rule | SSH TCP 22, source: My IP |

### Step 2 --- Create and attach the EC2 IAM role

Open IAM → Roles → Create role.

Choose AWS service → EC2.

Attach permissions required for your Terraform EKS configuration :
select administrator role for simple way (optional way including IAM,
EC2/VPC, EKS, and any S3 state backend resources.)

Name the role student-terraform-management-role.

Go to EC2 → Instances → student-server → Actions → Security → Modify IAM
role, and select the new role.

Add In bound Rules in student-management-sg Security Group:

| Purpose | Protocol / port | Source |
|---|---:|---|
| Application | Custom TCP `8080` | My IP |
| Argo CD | Custom TCP `8081` | My IP |
| Grafana | Custom TCP `3000` | My IP |
| Prometheus | Custom TCP `9090` | My IP |
| Alertmanager | Custom TCP `9093` | My IP |

> **Security:** Restrict these inbound rules to your trusted IP address. Avoid exposing administration and monitoring dashboards to `0.0.0.0/0`.

### Connect from Git Bash

```bash
ssh -i ~/Downloads/student-key.pem \
ubuntu@YOUR_EC2_PUBLIC_IP
sudo hostnamectl set-hostname student-server
exec bash
```

### Install essential Ubuntu packages

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y \
  git curl wget unzip jq \
  python3 python3-pip \
  gnupg ca-certificates lsb-release
```

```bash
git --version
python3 --version
```

### Install Terraform

```bash
wget -O- https://apt.releases.hashicorp.com/gpg \
| sudo gpg --dearmor \
-o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
| sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install -y terraform
```

```bash
terraform version
```

### Install AWS CLI v2

```bash
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
  -o awscliv2.zip
unzip -q awscliv2.zip
sudo ./aws/install
aws --version
```

Verify your IAM instance role:

```bash
aws sts get-caller-identity
# AWS cluster Region change region according to your cluster location
aws configure set region eu-north-1
```

```bash
aws configure get region
```

### Install kubectl

```bash
curl -fL "https://s3.us-west-2.amazonaws.com/amazon-eks/1.34.9/2026-07-05/bin/linux/amd64/kubectl" \
  -o kubectl
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
kubectl version --client
```

### Install Helm

```bash
curl -fsSLO https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get-helm-3
./get-helm-3
helm version
```

### Clone the repository:

```bash
git clone https://github.com/harathi-mutyam/micro_svc_student_app_cicd.git
cd micro_svc_student_app_cicd

git status --short
git branch --show-current
ls -la
```

check any syntax errors in shell scripts

```bash
chmod +x scripts/*.sh
for file in scripts/*.sh database/init.sh; do
bash -n "$file" || exit 1
done
```

change admin_cidr with your ec2 instance public ip

cd \~/micro_svc_student_app_cicd

vim terraform/terraform.tfvars

change admin_cidr with your \# EC2 Public IP for administrative access

Example: admin_cidr = "16.170.165.24/32"

Save it

Before push the changes to git hub repository create a classic Token for
you repository

### Create GitHub Personal Access Token (Classic)

Open GitHub click on right side top coner on your profile
picturesettings Devoloper settings Personal access tokens
Tokens(classic)Click Generate new token.--\>Select Generate new token
(classic). Enter a Note: Student-App-GitHub-ActionsSelect expiration
(e.g. 90 days) Select REPO check box and WorkFlow checkbox Click on
Generate Token copy the Token value and save it some where.It will use
to push anything into your repository

```bash
git pull origin main
git status
git add  terraform/terraform.tfvars
git commit -m "Update terraform.tfvars file admin cicr with ec2"
git config --global user.email  ehmutyam@example.com
git config --global user.name harathi-mutyam
git push origin main
```

enter

Username for 'https://github.com': harathi-mutyam

Password for 'https://harathi-mutyam@github.com':

```bash
git status
```

### Step 3: Configure GitHub Actions to publish Docker images

Code available in ci.yml file

create GitHub variables and secrets for Dockerhub user

Before pushing ci.yml, configure the following at Github Actions
Variables and secrets

| GitHub secret | Required value |
|---|---|
| `DOCKERHUB_TOKEN` | Docker Hub access token with push permissions |

Create docker hub username as a variable

| GitHub variable | Value |
|---|---|
| `DOCKERHUB_USERNAME` | `harathi2026` |

Steps to create a dockerhub token login to docker hub click on profile
on right side cornerselect account settings select personal access
tokens name: student-microsvc-token ,Expiration : 30 days , Access
Permissions: Repo Read & Write generate a token save the token and place
it in a github as a secret

Check it in browser: open project github repositoryactionsrunner Build
successful

Open server gitbash terminal

cd \~/micro_svc_student_app_cicd

```bash
git pull --ff-only origin main
export DOCKERHUB_USERNAME="harathi2026"
export IMAGE_TAG="$(git rev-parse HEAD)"
echo "$IMAGE_TAG"
echo "${#IMAGE_TAG}"
```

### Create A Cluster through Terraform

cd terraform

```bash
terraform init
terraform validate
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
```

### Connect to EKS

```bash
#region must match claster provided region
aws eks update-kubeconfig \
--region eu-north-1 \
--name student-cluster
kubectl get nodes -o wide
```

ctrl+c

check nodes are ready or not

Check EBS CSI addon:

```bash
aws eks describe-addon \
--cluster-name student-cluster \
--region eu-north-1 \
--addon-name aws-ebs-csi-driver \
--query 'addon.status' \
--output text
```

Output must be ACTIVE

### Create Secrets and ConfigMaps

Only after EKS and its EBS CSI driver are ready:

cd \~/micro_svc_student_app_cicd

```bash
# Generate environment configuration file (.env.k8s)
bash scripts/01-prepare-env.sh
# Apply namespaces, secrets, and configmaps
bash scripts/02-apply-prerequisites.sh
```

Verify resources:

```bash
kubectl get secret student-secrets -n student-app
kubectl get configmaps -n student-app
```

OutPut: You should see student-secrets (with 13 keys) and ConfigMaps
mysql-init and nginx-config.

### Deploy Microservices Applications

Export your Docker Hub credentials and deploy all microservices in
order:

Bash

```bash
# Export deployment variables
export DOCKERHUB_USERNAME="harathi2026"
```

go to docker hub copy the latest image tag

```bash
export IMAGE_TAG="paste the copied image tag here"
```

or optional way

```bash
export IMAGE_TAG="$(git rev-parse HEAD)"
```

```bash
echo "Username: $DOCKERHUB_USERNAME"
echo "Image Tag: $IMAGE_TAG"
```

```bash
# Run deployment script
bash scripts/03-deploy-in-order.sh
```

Verify Pods and Persistent Storage:

```bash
kubectl -n student-app get pods -w
```

(Press Ctrl + C once database-0, auth, students, attendance, marks,
frontend, and gateway are running)

```bash
# Check database persistent volume claim
kubectl -n student-app get pvc
```

Verification: data-database-0 status should be Bound.

### Step : Access and Test Application in Browser

Start port-forwarding for the API gateway:

open one more new git bash terminal

```bash
ssh -i ~/Downloads/student-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
sudo hostnamectl set-hostname student-application-test
exec bash
```

```bash
kubectl port-forward -n student-app svc/gateway 8080:80 \
--address=0.0.0.0
```

(Keep this terminal open and running)

Retrieve admin password (in a old server Git Bash terminal):

```bash
grep '^DEMO_ADMIN_PASSWORD='  ~/micro_svc_student_app_cicd/.env.k8s
```

copy the password

Open browser and test the application is running or not

http://`<YOUR_EC2_PUBLIC_IP>`{=html}:8080

Username: admin

Password: (Value copied from .env.k8s)

Click on login

## Phase 2 --- Argo CD GitOps deployment

### Step : Install and Configure Argo CD

```bash
# Create namespace and install Argo CD
kubectl create namespace argocd
kubectl get namespace argocd
kubectl apply -n argocd --server-side \
```

-f
https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

Verify: optional commands

```bash
kubectl get pods -n argocd
kubectl get deployments -n argocd
kubectl get statefulsets -n argocd
kubectl get services -n argocd
```

```bash
# Wait for Argo CD server to be ready
kubectl rollout status deployment/argocd-server \
-n argocd --timeout=300s
# Retrieve initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
-o jsonpath='{.data.password}' | base64 -d; echo
```

Save the password

### Step : Access the Argo Cd Dashboard

Open another Gitbash Terminal

Login through ssh

```bash
ssh -i ~/Downloads/student-key-cicd.pem ubuntu@server_public_ip
```

```bash
sudo hostnamectl set-hostname argocd
exec bash
```

```bash
kubectl port-forward -n argocd   svc/argocd-server \
--address=0.0.0.0 8081:443
```

Open Windows Browser :

http://server_ec2_publicip:8081

username : admin

Password: paste argo cd initial admin password

Observe it argo cd dash board created

### Step :Apply Argo CD Application manifest:

cd \~/micro_svc_student_app_cicd

```bash
kubectl apply -f argocd/student-app-argocd.yaml
# Check application sync state
kubectl get applications -n argocd
NAME          SYNC STATUS   HEALTH STATUS
```

student-app Synced Healthy

Look for SYNC STATUS: Synced and HEALTH STATUS: Healthy.

Open argo dashboard in browser and check there also.

## Phase 3 --- Monitoring Student Microservices on Amazon EKS

Check memore space

cd \~/micro_svc_student_app_cicd

```bash
kubectl describe nodes | grep -A 8 "Allocated resources:"
```

Create monitoring directory and namespace

```bash
kubectl create namespace monitoring \
--dry-run=client -o yaml | kubectl apply -f -
kubectl get namespace monitoring
```

Add Prometheus Helm repository

```bash
helm repo add prometheus-community \
```

https://prometheus-community.github.io/helm-charts

```bash
helm repo update
```

verify:

```bash
helm search repo prometheus-community/kube-prometheus-stack
helm list -n monitoring
```

check monitoring values file

cat monitoring/prometheus-values.yaml

```bash
helm list -n monitoring
ubuntu@student-server:~/micro_svc_student_app_cicd$ helm list -n monitoring
NAME    NAMESPACE       REVISION        UPDATED STATUS  CHART   APP VERSION
```

Now render the Helm chart:

```bash
helm template kube-prometheus-stack \
```

prometheus-community/kube-prometheus-stack\

```bash
--version 92.17.1 \
--namespace monitoring \
```

-f monitoring/prometheus-values.yaml\

> /tmp/student-monitoring-rendered.yaml

Verify:

```bash
test -s /tmp/student-monitoring-rendered.yaml \
```

&& echo "PASS: Helm template rendering successful"

```bash
helm show chart \
```

prometheus-community/kube-prometheus-stack\

```bash
--version 92.17.1
```

### Install Prometheus and Grafana

```bash
helm upgrade --install kube-prometheus-stack \
```

prometheus-community/kube-prometheus-stack\

```bash
--version 92.17.1 \
--namespace monitoring \
```

-f monitoring/prometheus-values.yaml\

```bash
--wait \
--timeout 15m
```

Verify the installation (PVC added in grafana for dashboards persistence
purpose)

```bash
kubectl get pvc -n monitoring
```

Check STATUS: Bound

```bash
kubectl get pods -n monitoring -l "app.kubernetes.io/name=grafana"
helm list -n monitoring
kubectl get pods -n monitoring
kubectl get deployments -n monitoring
kubectl get statefulsets -n monitoring
kubectl get daemonsets -n monitoring
kubectl get svc -n monitoring
```

Verify Prometheus:

```bash
kubectl get prometheus -n monitoring
```

If a monitoring Pod is Pending

Run:

```bash
kubectl get pods -n monitoring
kubectl get events -n monitoring \
--sort-by=.lastTimestamp
```

If all pods are running continue this step

Get Grafana administrator password

```bash
kubectl get secret -n monitoring \
```

kube-prometheus-stack-grafana

```bash
kubectl get secret kube-prometheus-stack-grafana \
```

-n monitoring\

```bash
-o jsonpath='{.data.admin-password}' | base64 -d
```

Echo

Save the password

### Step : Access Grafana Dashbord through Browser

open one more gitbash terminal for grafana

```bash
ssh -i ~/Downloads/student-key-cicd.pem ubuntu@server_public_ip
sudo hostnamectl set-hostname Grafana
exec bash
kubectl port-forward \
```

-n monitoring\

svc/kube-prometheus-stack-grafana\

```bash
3000:80 --address=0.0.0.0
Forwarding from 127.0.0.1:3000 -> 80
Forwarding from [::1]:3000 -> 80
```

Open Grafana in Broser http://`<Server-ec2-public-ip>`{=html}:3000

username:admin

password:paste saved one here login

Check your Kubernetes dashboards

Inside Grafana:

Select Dashboards from the left navigation.

Look for the Kubernetes dashboards installed by kube-prometheus-stack.

Open Kubernetes / Compute Resources / Cluster.

Review CPU utilization, memory utilization, and Pod resource usage.

select the Namespace dropdown in dashboard and select student-app (where
the namespace variable is available.)

Click on dash boards Kubernetes / Compute Resources / Namespace (Pods)
inside select namespace: student-app (on top)

Dashboards Kubernetes / Compute Resources / Namespace (Workloads)select
namespace: student-app

Navigate to Memory QuotaClick on student or marks or any service

Dashboards Kubernetes / Compute Resources / Namespace (Workloads)select
namespace: argocd

Dashboards Kubernetes / Compute Resources / Namespace (Workloads)select
namespace: monitoring

Verify metrics directly in Grafana

Navigate to Explore, select the Prometheus data source on right side
select code and run this PromQL expression: up click on Run Query

Next, query your Student application Pods:

kube_pod_status_phase{

namespace="student-app",

phase="Running"

```bash
}
```

For container CPU usage:

sum by (pod) (

```bash
rate(
```

container_cpu_usage_seconds_total{

namespace="student-app",

container!="",

container!="POD"

```bash
}[5m]
```

)

)

Delete the old Query and enter

For container memory:

sum by (pod) (

container_memory_working_set_bytes{

namespace="student-app",

container!="",

container!="POD"

```bash
}
```

)

Create a Dashboard for application in Grafana in 2 ways either manual
way or through json

Method 1: Build Panels Manually in Grafana UI

Create a New Dashboard:

Open Grafana at http://`<YOUR_EC2_PUBLIC_IP>`{=html}:3000.

Click the + (plus icon) in the top-right corner or left menu, and select
New Dashboard.

Click + Add visualization.

Select prometheus (or kube-prometheus-stack-prometheus) as the data
source.

Verification: A new panel configuration screen appears with a query
editor at the bottom.

Panel 1: Running Pods Status (Stat Panel):

PromQL Query:

Code-Snippet

```bash
sum(kube_pod_status_phase{namespace="student-app", phase="Running"})
```

On the right-hand panel settings, change the visualization type from
Time series to Stat.

Under Panel options, set Title to Healthy Running Pods.

Click Apply in the top right.

Verification: The panel displays a numeric count of your running pods
(e.g., 7).

Panel 2: CPU Utilization by Microservice (Time Series):

Click + Add -\> Visualization.

PromQL Query:

Code-Snippet

sum by (pod)
(rate(container_cpu_usage_seconds_total{namespace="student-app",
container!="", container!="POD"}\[5m\]))

Under Legend, set the label format to {{pod}}.

Set Title to CPU Usage per Pod (Cores).

Under Standard options -\> Unit, choose Data Rate / Throughput or type
cores.

Click Apply.

Verification: A multi-line graph displays CPU usage curves for each
service.

Panel 3: Memory Usage by Microservice (Time Series):

Click + Add -\> Visualization.

PromQL Query:

Code-Snippet

sum by (pod)
(container_memory_working_set_bytes{namespace="student-app",
container!="", container!="POD"})

Under Legend, enter {{pod}}.

Set Title to Memory Working Set (RAM).

Under Standard options -\> Unit, select Data (IEC) -\> Bytes (IEC) or
Megabytes (MiB).

Click Apply.

Verification: Graphs show real-time memory usage (e.g., \~120 MiB for
database-0).

Panel 4: Network Ingress/Egress Throughput:

Click + Add -\> Visualization.

Query A (Received):

Code-Snippet

sum by (pod)
(rate(container_network_receive_bytes_total{namespace="student-app"}\[5m\]))

Legend: {{pod}} - Ingress

Query B (Transmitted):

Code-Snippet

sum by (pod)
(rate(container_network_transmit_bytes_total{namespace="student-app"}\[5m\]))

Legend: {{pod}} - Egress

Under Standard options -\> Unit, select Data Rate -\> Bytes/sec.

Set Title to Pod Network Traffic (Bytes/sec).

Click Apply.

Verification: Traffic throughput graphs show up when requests are sent
through the gateway.

Save Your Dashboard:

Click the Disk icon (Save dashboard) in the top-right toolbar.

Enter the name Student Microservices Overview and click Save.

Verification: The dashboard title updates to "Student Microservices
Overview" and persists upon page refresh.

Method 2: Import via Ready-to-Use Dashboard JSON

If you want an instant dashboard with all these panels pre-arranged:

In Grafana, click Dashboards in the left sidebar.

Click New -\> Import.

Under Import via panel json, paste the JSON block below:

JSON

```bash
{
"annotations": { "list": [] },
"editable": true,
"fiscalYearStartMonth": 0,
"graphTooltip": 1,
"id": null,
"links": [],
"liveNow": false,
"panels": [
{
"collapsed": false,
"gridPos": { "h": 1, "w": 24, "x": 0, "y": 0 },
"id": 1,
"title": "Application Health & Resources",
"type": "row"
},
{
"datasource": { "type": "prometheus" },
"fieldConfig": {
"defaults": {
"color": { "mode": "thresholds" },
"thresholds": {
"mode": "absolute",
"steps": [
{ "color": "red", "value": null },
{ "color": "green", "value": 7 }
]
}
}
},
"gridPos": { "h": 4, "w": 6, "x": 0, "y": 1 },
"id": 2,
"options": {
"colorMode": "value",
"graphMode": "none",
"justifyMode": "auto",
"reduceOptions": { "calcs": ["lastNotNull"], "values": false }
},
"pluginVersion": "10.0.0",
"targets": [
{
"expr": "sum(kube_pod_status_phase{namespace=\"student-app\", phase=\"Running\"})",
"refId": "A"
}
],
"title": "Healthy Running Pods",
"type": "stat"
},
{
"datasource": { "type": "prometheus" },
"fieldConfig": {
"defaults": {
"unit": "short"
}
},
"gridPos": { "h": 4, "w": 6, "x": 6, "y": 1 },
"id": 3,
"options": {
"colorMode": "value",
"graphMode": "none",
"justifyMode": "auto",
"reduceOptions": { "calcs": ["lastNotNull"], "values": false }
},
"targets": [
{
"expr": "sum(kube_pod_container_status_restarts_total{namespace=\"student-app\"})",
"refId": "A"
}
],
"title": "Total Pod Restarts",
"type": "stat"
},
{
"datasource": { "type": "prometheus" },
"fieldConfig": {
"defaults": {
"custom": { "drawStyle": "line", "lineInterpolation": "smooth" },
"unit": "cores"
}
},
"gridPos": { "h": 8, "w": 12, "x": 12, "y": 1 },
"id": 4,
"options": { "legend": { "displayMode": "table", "placement": "bottom" } },
"targets": [
{
"expr": "sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=\"student-app\", container!=\"\", container!=\"POD\"}[5m]))",
"legendFormat": "{{pod}}",
"refId": "A"
}
],
"title": "CPU Usage per Pod",
"type": "timeseries"
},
{
"datasource": { "type": "prometheus" },
"fieldConfig": {
"defaults": {
"custom": { "drawStyle": "line", "lineInterpolation": "smooth" },
"unit": "bytes"
}
},
"gridPos": { "h": 8, "w": 12, "x": 0, "y": 9 },
"id": 5,
"options": { "legend": { "displayMode": "table", "placement": "bottom" } },
"targets": [
{
"expr": "sum by (pod) (container_memory_working_set_bytes{namespace=\"student-app\", container!=\"\", container!=\"POD\"})",
"legendFormat": "{{pod}}",
"refId": "A"
}
],
"title": "Memory Usage (Working Set)",
"type": "timeseries"
},
{
"datasource": { "type": "prometheus" },
"fieldConfig": {
"defaults": {
"custom": { "drawStyle": "line", "lineInterpolation": "smooth" },
"unit": "binBps"
}
},
"gridPos": { "h": 8, "w": 12, "x": 12, "y": 9 },
"id": 6,
"options": { "legend": { "displayMode": "table", "placement": "bottom" } },
"targets": [
{
"expr": "sum by (pod) (rate(container_network_receive_bytes_total{namespace=\"student-app\"}[5m]))",
"legendFormat": "{{pod}} Rx",
"refId": "A"
}
],
"title": "Network Ingress (Received)",
"type": "timeseries"
}
],
"schemaVersion": 38,
"title": "Student Microservices Application Dashboard",
"timezone": "browser",
"weekStart": ""
}
```

Click Load. Click import

And observe it go to Dash Boardsselect Student Microservices Application
Dashboard

### Step :To observe live Spikes in Grafana

Open server gitbash terminal run these commands

```bash
for i in {1..200}; do
curl -s http://127.0.0.1:8080/api/auth/health > /dev/null
curl -s http://127.0.0.1:8080/api/students/health > /dev/null
curl -s http://127.0.0.1:8080/api/attendance/health > /dev/null
curl -s http://127.0.0.1:8080/api/marks/health > /dev/null
done
echo "Traffic test complete: 800 total HTTP requests sent."
```

Open Grafana Dashboard in browser
http://`<YOUR_EC2_PUBLIC_IP>`{=html}:3000

In the top-right corner:

Change the time range to Last 5 minutes or Last 15 minutes.

Set the auto-refresh interval to 5s (next to the Refresh button).

Check the panels:

Network Ingress (Received): Sharp spikes will appear for gateway, auth,
students, attendance, and marks.

CPU Usage per Pod: Microservice CPU utilization lines will spike upwards
during the burst.

## Phase 4: Loki and Grafana Alloy

Open server gitbash terminal

```bash
#Check memory space
kubectl describe nodes | grep -E "DiskPressure|Allocated resources" -A 8
```

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

cd \~/micro_svc_student_app_cicd

```bash
export AWS_REGION="us-east-1"
export CLUSTER_NAME="student-cluster"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export LOKI_CHUNKS_BUCKET="student-loki-chunks-${ACCOUNT_ID}-${AWS_REGION}"
export LOKI_RULER_BUCKET="student-loki-ruler-${ACCOUNT_ID}-${AWS_REGION}"
echo "Account: $ACCOUNT_ID | Cluster: $CLUSTER_NAME | Region: $AWS_REGION"
echo "Chunks Bucket: $LOKI_CHUNKS_BUCKET"
echo "Ruler Bucket: $LOKI_RULER_BUCKET"
```

Create the S3 buckets

```bash
aws s3api create-bucket --bucket "$LOKI_CHUNKS_BUCKET" --region "$AWS_REGION"
aws s3api create-bucket --bucket "$LOKI_RULER_BUCKET" --region "$AWS_REGION"
```

```bash
for BUCKET in "$LOKI_CHUNKS_BUCKET" "$LOKI_RULER_BUCKET"; do
aws s3api put-public-access-block \
--bucket "$BUCKET" \
--public-access-block-configuration \
```

BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

```bash
aws s3api put-bucket-encryption \
--bucket "$BUCKET" \
--server-side-encryption-configuration \
'{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

Done

```bash
aws s3 ls | grep student-loki
```

Install eksctl & Configure IAM Roles for Service Accounts (IRSA)

Install eksctl

```bash
if ! command -v eksctl &> /dev/null; then
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz"
```

tar -xzf eksctl_Linux_amd64.tar.gz

```bash
sudo install -m 0755 eksctl /usr/local/bin/eksctl
rm -f eksctl eksctl_Linux_amd64.tar.gz
fi
```

```bash
eksctl version
```

Associate OIDC Provider with your EKS cluster:

```bash
eksctl utils associate-iam-oidc-provider --cluster "$CLUSTER_NAME" \
--region "$AWS_REGION" --approve
```

Create the IAM Policy for S3 access

Using this file to create a policy or run manual way

```bash
chmod +x ./scripts/create-loki-s3-policy.sh
```

```bash
./scripts/create-loki-s3-policy.sh \
"$LOKI_CHUNKS_BUCKET" \
"$LOKI_RULER_BUCKET"
```

Or this way

```bash
cat <<EOF > /tmp/student-loki-s3-policy.json
{
"Version": "2012-10-17",
"Statement": [
{
"Effect": "Allow",
"Action": ["s3:ListBucket", "s3:GetBucketLocation"],
"Resource": [
"arn:aws:s3:::${LOKI_CHUNKS_BUCKET}",
"arn:aws:s3:::${LOKI_RULER_BUCKET}"
]
},
{
"Effect": "Allow",
"Action": [
"s3:GetObject",
"s3:PutObject",
"s3:DeleteObject"
],
"Resource": [
"arn:aws:s3:::${LOKI_CHUNKS_BUCKET}/*",
"arn:aws:s3:::${LOKI_RULER_BUCKET}/*"
]
}
]
}
EOF
```

```bash
aws iam create-policy \
--policy-name StudentLokiS3Policy \
--policy-document file:///tmp/student-loki-s3-policy.json 2>/dev/null || true
```

Create the logging namespace & ServiceAccount

Check IAM created Policy

```bash
aws iam list-policies \
--scope Local \
--query "Policies[?PolicyName=='StudentLokiS3Policy'].[PolicyName,Arn]" \
--output table
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -
```

```bash
eksctl create iamserviceaccount \
--cluster "$CLUSTER_NAME" \
--region "$AWS_REGION" \
--namespace logging \
--name loki \
--role-name StudentLokiS3Role \
--attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/StudentLokiS3Policy" \
--override-existing-serviceaccounts \
--approve
```

Verify:

```bash
kubectl get sa loki -n logging -o yaml
```

### Configure and Deploy Loki with S3 Backend

Add the Grafana Community Helm repository

```bash
helm repo add grafana-community \
```

https://grafana-community.github.io/helm-charts

```bash
helm repo update
```

Generate logging/loki-values.yaml

cat logging/loki-values.yaml

Deploy Loki

```bash
helm upgrade --install loki grafana-community/loki \
--version 19.0.3 \
--namespace logging \
```

-f logging/loki-values.yaml\

```bash
--wait \
--timeout 10m
```

```bash
kubectl get pods -n logging
NAME                           READY   STATUS    RESTARTS   AGE
```

loki-0 2/2 Running 0 90s

loki-canary-hhh9q 1/1 Running 0 90s

loki-canary-qlhpv 1/1 Running 0 90s

loki-gateway-9847cdff6-dsgv9 2/2 Running 0 90s

### Install Grafana Alloy to Ship Pod Logs

Add the official Grafana Helm repository:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

Create or Verify logging/alloy-values.yaml

cat logging/alloy-values.yaml

Deploy Alloy as a DaemonSet

```bash
helm upgrade --install alloy grafana/alloy \
--version 1.14.1 \
--namespace logging \
```

-f logging/alloy-values.yaml\

```bash
--wait \
--timeout 10m
kubectl get ds -n logging
NAME          DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
```

alloy 2 2 2 2 2 `<none>`{=html} 86s

loki-canary 2 2 2 2 2 `<none>`{=html} 7m3s

### Step : Connect Loki to Grafana

Open Grafana in your web browser
http://`<YOUR_EC2_PUBLIC_IP>`{=html}:3000

Go to Connections -\> Data sources -\> click Add data source.

Select Loki.

In the Connection URL field, enter:

http://loki-gateway.logging.svc.cluster.local/

Scroll down and click Save & test.

Query Application Logs in Grafana Explore

Navigate to Explore select Loki select Code mode paste the
{namespace="student-app"} click on Run query

With Explanation:

Click Explore (compass icon) in Grafana's left navigation sidebar.

Select Loki from the top data source dropdown.

Switch to Code mode and test your Student Microservices queries

All Student Microservices Logs:

```bash
{namespace="student-app"}
```

Specific Service Logs (e.g., Auth or Students):

```bash
{namespace="student-app", app="auth"}
{namespace="student-app", app="students"}
```

MySQL Database Logs:

```bash
{namespace="student-app", app="database"}
```

Search for errors:

```bash
{namespace="student-app"} |= "error"
```

### Step : Add a Live Logs Panel to Your Existing Dashboard

Open your Student Microservices Application Dashboard in Grafana.

Click Add -\> Visualization (top toolbar).

Select data source Loki.

Enter the query: {namespace="student-app"}

On the right-hand settings panel, change visualization type to Logs.

Set the Panel Title to Student Microservices - Live Logs

Click Apply in the top right, then click the Save disk icon.

Same way check for marks also and add visulisation

```bash
{namespace="student-app", app="students"}
```

Verification: The panel displays auto-refreshing log streams directly
beneath your existing CPU, RAM, and Network metrics panels.

## Phase 5: Verify AWS S3 Log Persistence

Open aws console open s3 open chunks bucketcheck logs are present or not

Generate traffic to trigger write logs

Open server gitbash terminal

```bash
for i in {1..30}; do
curl -s http://127.0.0.1:8080/api/auth/health > /dev/null
curl -s http://127.0.0.1:8080/api/students/health > /dev/null
done
```

open Grafana dash board in browserchange Refresh time to 5 seconds

observe the logs are refreshing now

```bash
# Inspect chunks stored in S3 through gitbahs terminal
```

Open server gitbash Terminal

```bash
aws s3 ls "s3://${LOKI_CHUNKS_BUCKET}/" --recursive --summarize
```

## Phase 6: Alertmanager Setup & Student App Alerting Rules

Verify Alertmanager Is Running

```bash
kubectl get pods -n monitoring \
```

-l "app.kubernetes.io/name=alertmanager"

```bash
kubectl get svc -n monitoring \
```

-l "app.kubernetes.io/name=alertmanager"

```bash
NAME                                                READY   STATUS    RESTARTS   AGE
```

alertmanager-kube-prometheus-stack-alertmanager-0 2/2 Running 0

Create Custom Prometheus Alert Rules for student-app

Created a Kubernetes PrometheusRule Custom Resource Definition (CRD)
that tells Prometheus when to trigger alerts for pod down events, high
CPU usage, crash loops, and database connectivity failures.

cat monitoring/student-app-alerts.yaml

```bash
kubectl apply -f monitoring/student-app-alerts.yaml
```

### Step : Verify the Alert Rules in Prometheus UI

Port-forward the Prometheus server:

Open one more git bash terminal login through ssh

```bash
ssh -i ~/Downloads/student-key-cicd.pem ubuntu@3.80.204.112
sudo hostnamectl set-hostname Prometheus-alertmanager
exec bash
kubectl port-forward -n monitoring \
svc/kube-prometheus-stack-prometheus 9090:9090 --address=0.0.0.0
```

Access Alerts in Browser

Open your browser http://`<YOUR_EC2_PUBLIC_IP>`{=html}:9090/alerts

Verification: Scroll down to find the group student-app.rules. You will
see your 4 rules: or search student

StudentMicroserviceDown

StudentPodFrequentRestart

MySQLDatabaseDown

StudentPodHighMemory

Note: All rules should initially display with a green

If You you see one firing .Open Server gitbash Terminal

vim monitoring/student-app-alerts.yaml

Firing related one time to 3 to 1

Observe apply it again

```bash
kubectl apply -f monitoring/student-app-alerts.yaml
```

Within 1--2 minutes, all 4 rules in the Prometheus /alerts tab will
transition to green INACTIVE (4).

### Step : Access the Alertmanager Web UI

Add 9093 port in security group of ec2 instance

Open one more gitbash

```bash
ssh -i ~/Downloads/student-key-cicd.pem ubuntu@server_public_ip
sudo hostnamectl set-hostname alertmanager
exec bash
kubectl port-forward -n monitoring \
```

svc/kube-prometheus-stack-alertmanager 9093:9093\

```bash
--address=0.0.0.0
```

### Step :Access Alert manager in browser

Open Alertmanager in Your Browser

http://`<YOUR_EC2_PUBLIC_IP>`{=html}:9093

Verification: Active alerts routed from Prometheus appear under the
Alerts tab with their associated labels and annotations.

## Phase 7::Clean UP Procedure

cd micro_svc_student_app_cicd

### Step : Delete Prometheus, Alertmanager, and Grafana (including Grafana PVC):

```bash
# Uninstall Helm release
helm uninstall kube-prometheus-stack -n monitoring
# Explicitly delete the Grafana PVC and any monitoring PVCs
kubectl delete pvc -l "app.kubernetes.io/name=grafana" -n monitoring
kubectl delete pvc --all -n monitoring
# Remove custom Prometheus rules and monitoring namespace
kubectl delete -f monitoring/student-app-alerts.yaml --ignore-not-found
kubectl delete namespace monitoring
```

### Step : Delete Loki and Alloy Logging Components:

```bash
helm uninstall alloy -n logging
helm uninstall loki -n logging
kubectl delete pvc --all -n logging
kubectl delete namespace logging
```

### Step : Delete Argo CD & Application Resources:

```bash
# Remove Argo CD application
kubectl delete -f argocd/student-app-argocd.yaml --ignore-not-found
```

```bash
# Delete student application workloads and database PVC (releases the AWS EBS volume)
kubectl delete namespace student-app
kubectl delete pvc data-database-0 -n student-app --ignore-not-found
# Uninstall Argo CD
kubectl delete -n argocd \
```

-f
https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml\

```bash
--ignore-not-found
kubectl delete namespace argocd
```

Delete IAM Service Accounts & Custom Policies created via eksctl:

```bash
export AWS_REGION="us-east-1"
export CLUSTER_NAME="student-cluster"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
# Delete IAM Service Account
eksctl delete iamserviceaccount \
--cluster "$CLUSTER_NAME" \
--region "$AWS_REGION" \
--namespace logging \
--name loki
```

```bash
# Delete IAM Policy
aws iam delete-policy \
--policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/StudentLokiS3Policy"
```

### Step : Delete Loki IAM Service Account and Policy

1.  Set variables

```bash
export AWS_REGION="us-east-1"
export CLUSTER_NAME="student-cluster"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/StudentLokiS3Policy"
```

2.  Delete IAM Service Account

```bash
eksctl delete iamserviceaccount \
--cluster "$CLUSTER_NAME" \
--region "$AWS_REGION" \
--namespace logging \
--name loki
```

3.  Check policy attachments

```bash
aws iam list-entities-for-policy \
--policy-arn "$POLICY_ARN" \
--output table
```

4.  Check attachment count

```bash
aws iam get-policy \
--policy-arn "$POLICY_ARN" \
--query 'Policy.AttachmentCount'
```

5.  Delete IAM policy

Only when attachment count is 0:

```bash
aws iam delete-policy \
--policy-arn "$POLICY_ARN"
```

6.  Verify deletion

```bash
aws iam get-policy \
--policy-arn "$POLICY_ARN"
```

### Step : Empty and Delete the Loki S3 Buckets

AWS S3 requires all objects and versions to be removed before a bucket
can be deleted:

```bash
export AWS_REGION="us-east-1"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export LOKI_CHUNKS_BUCKET="student-loki-chunks-${ACCOUNT_ID}-${AWS_REGION}"
export LOKI_RULER_BUCKET="student-loki-ruler-${ACCOUNT_ID}-${AWS_REGION}"
# Empty and delete the chunks bucket
aws s3 rm "s3://${LOKI_CHUNKS_BUCKET}" --recursive
aws s3api delete-bucket \
--bucket "$LOKI_CHUNKS_BUCKET" \
--region "$AWS_REGION"
# Empty and delete the ruler bucket
aws s3 rm "s3://${LOKI_RULER_BUCKET}" --recursive
aws s3api delete-bucket --bucket "$LOKI_RULER_BUCKET" --region "$AWS_REGION"
```

### Step: Destroy EKS Cluster through Terraform

cd \~/micro_svc_student_app_cicd/terraform

```bash
terraform destroy -auto-approve
```

exit

### Step: Terminate ec2 instance in aws console

Open Ec2 instance in aws console select ec2 instance terminate it
