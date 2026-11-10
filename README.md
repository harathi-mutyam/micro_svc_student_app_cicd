# Complete Student Microservices Deployment on Amazon EKS

> **End-to-end guide:** EC2 preparation → Terraform EKS provisioning → CI/CD and Docker Hub → microservices deployment → Argo CD GitOps → Prometheus/Grafana monitoring → Loki/Alloy logging → Alertmanager → complete cleanup.

<img width="1671" height="941" alt="Student Microservices on Amazon EKS (1)" src="https://github.com/user-attachments/assets/45393ddf-5a6d-4716-a38a-0e78e4172b0d" />


**Repository:** https://github.com/harathi-mutyam/micro_svc_student_app_cicd  
**AWS region used in the EKS setup:** `us-east-1` (US – North Virginia)  
**Kubernetes namespace:** `student-app`

## Table of Contents

1. [Phase 1 – EC2 and Deployment Prerequisites](#phase-1-ec2-and-deployment-prerequisites)
2. [Phase 2 – Docker Engine and GitHub Self-Hosted Runner](#phase-2-install-docker-engine-and-configure-github-self-hosted-runner)
3. [Phase 3 – Repository, CI/CD, EKS and Microservices Deployment](#phase-3-clone-the-repossitory-cicd-pipeline-eks-infrastructure-provisioning-and-student-microservices-deployment)
4. [Phase 4 – Argo CD GitOps Deployment](#phase-4-argo-cd-gitops-deployment)
5. [Phase 5 – Prometheus and Grafana Monitoring](#phase-5-prometheus-and-grafana-monitoring-student-microservices-on-amazon-eks)
6. [Phase 6 – Loki and Grafana Alloy Logging](#phase-6-loki-and-grafana-alloy)
7. [Phase 7 – Verify AWS S3 Log Persistence](#phase-7-verify-aws-s3-log-persistence)
8. [Phase 8 – Alertmanager and Alert Rules](#phase-8-alertmanager-setup--student-app-alerting-rules)
9. [Phase 9 – Complete Cleanup](#phase-9clean-up-procedure)

## Before You Begin

- An AWS account with permissions to create EC2, IAM, VPC, EKS and S3 resources.
- A GitHub account with access to the project repository.
- A Docker Hub account and access token.
- Git Bash on your local Windows machine.
- Keep private keys, GitHub tokens, Docker Hub tokens and application passwords secret. Do not commit them to Git.
- Replace placeholders such as `YOUR_EC2_PUBLIC_IP`, `server_public_ip` and sample CIDR values with your own values.

## Phase 1::EC2 and deployment prerequisites

### Step 1 ---Launch EC2 Management Instance

  1.    Region: us-east-1 (North Virginia)

  2.    Name: student-server

  3.    AMI: Ubuntu Server 24.04 LTS (64-bit x86)

  4.    Instance Type: m7i-flex.large (or t3.large)

  5.    Storage: 40 GiB gp3

  6.    Key Pair: student-key-cicd.pem or your actual filename.pem

  7.    Auto-assign Public IP: Enable

  8.    Security Group: **student-management-sg** with inbound rules:

            .  SSH (22): My IP
                       
            .  Argo CD (8081): My IP
            
            .  Grafana (3000): My IP
            
            .  Prometheus (9090): My IP
            
            .   Alertmanager (9093): My IP

### Step 2 --- Create and Attach IAM Role to EC2

1.    Open **IAM → Roles → Create role**.
    
2.    Select **AWS service → EC2**.
    
3.    Attach policy: **AdministratorAccess** (standard student lab configuration).
    
4.    Name role: student-terraform-management-role.
    
5.    **Attach role to EC2**: **EC2 → Instances → student-server → Actions → Security → Modify IAM role** → select student-terraform-management-role.

### Step 3: Connect & Install CLI Tools

**Connect from Git Bash**

```bash
ssh -i ~/Downloads/student-key.pem \
ubuntu@YOUR_EC2_PUBLIC_IP

sudo hostnamectl set-hostname student-server

exec bash
```

#### Install essential Ubuntu packages

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

#### Install Terraform

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

#### Install AWS CLI v2

```bash
curl -fsSL \
  https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip \
  -o awscliv2.zip
unzip -q awscliv2.zip
sudo ./aws/install
aws --version

```

**Verify your IAM instance role:**

```bash
aws sts get-caller-identity

# AWS cluster Region change region according to your cluster location

aws configure set region us-east-1

```

```bash
aws configure get region
```

#### Install kubectl

```bash
curl -fL \
  https://s3.us-west-2.amazonaws.com/amazon-eks/1.34.9/2026-07-05/bin/linux/amd64/kubectl \
  -o kubectl
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
kubectl version --client

```

#### Install Helm

```bash
curl -fsSLO https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3

chmod 700 get-helm-3

./get-helm-3

helm version
```



## Phase 2 – Install Docker Engine and Configure GitHub Self-Hosted Runner

> **Important:** Docker Engine is required because the GitHub Actions workflow builds Docker images, runs Trivy image scans, and publishes images to Docker Hub.
>
> The GitHub self-hosted runner runs directly on this EC2 instance.

### Step 1 – Install Docker Engine

Install Docker from the official Docker Ubuntu repository.

**1. Install the required packages:**

```
cd ~

sudo apt update

sudo apt install -y ca-certificates curl

sudo install -m 0755 -d /etc/apt/keyrings

sudo curl -fsSL \
  https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc

sudo chmod a+r /etc/apt/keyrings/docker.asc
```

**2. Configure the Docker repository:**

```
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

**3. Install Docker Engine and Buildx:**

```
sudo apt update

sudo apt install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
```

**4. Enable and start Docker:**

```
sudo systemctl enable --now docker
```

**5. Verify the Docker installation:**

```
docker --version

sudo systemctl is-active docker

sudo docker run hello-world
```

**Expected result:** The output should include:

```
Hello from Docker!
```

### Step 2 – Configure Docker Permissions

The GitHub runner service runs under the `ubuntu` account. This account must have permission to access Docker.

**1. Add the Ubuntu user to the Docker group:**

```
sudo usermod -aG docker ubuntu
```

**2. Apply the group change to the current shell:**

```
newgrp docker
```

**3. Test Docker access:**

```
docker ps
```

**4. Verify the Ubuntu user's group membership and Docker access:**

```
id ubuntu

sudo -u ubuntu -H docker ps
```

An empty container list is acceptable. There must be no Docker permission error.

> **Important – Docker permissions**
>
> - `newgrp docker` updates the group context of the current shell.
> - It does not update an already-running systemd runner service.
> - If Docker group membership is changed after installing the runner service, restart that service so it receives the updated group membership.
> - **Never use** `chmod 666 /var/run/docker.sock`. This would expose the Docker socket to all local users.

### Step 3 – Register GitHub Self-Hosted Runner

Open the your project GitHub repository:

Navigate to:

**Repository → Settings → Actions → Runners → New self-hosted runner**

Select:

- **Operating System:** Linux
- **Architecture:** x64

GitHub displays the latest runner download, extraction, and configuration commands.

> **Security warning:** Keep the runner registration token private. It is temporary and must never be committed to Git or shared publicly.

**1. Create the runner directory:**

```
ubuntu@student-server:~$

cd ~

ls

mkdir -p ~/actions-runner

cd ~/actions-runner
```

**2. Download and extract the runner:**

Execute the exact download and extraction commands displayed by GitHub.

They will look similar to: copy those commands from browser paste it in gitbash terminal

```
curl -o actions-runner-linux-x64-VERSION.tar.gz -L GITHUB_DOWNLOAD_URL

tar xzf ./actions-runner-linux-x64-VERSION.tar.gz
```


**3. Configure the runner:**

```
./config.sh \
  --url https://github.com/harathi-mutyam/micro_svc_student_app_cicd \
  --token YOUR_TEMPORARY_TOKEN \
  --labels student-runner
```

Replace `YOUR_TEMPORARY_TOKEN` with the temporary registration token displayed by GitHub.

  -   first press enter    
  -  later add `student-runner`
  -   Use the custom runner label: `student-runner`. 
  -   Accept the default work directory.

### Step 4 – Install Runner as a Linux Service

Install the runner as a systemd service so it starts automatically and remains available after an EC2 reboot.

**1. Install the service:**

```
cd ~/actions-runner

sudo ./svc.sh install ubuntu
```

**2. Start the service:**

```
sudo ./svc.sh start
```

**3. Check the service status:**

```
sudo ./svc.sh status
```

**4. Restart the service to ensure it receives the updated Docker group membership:**

```
sudo systemctl restart \
  actions.runner.harathi-mutyam-micro_svc_student_app_cicd.student-runner.service
```

**5. Verify the runner service and Docker access:**

```
sudo ./svc.sh status

sudo -u ubuntu -H docker ps
```

Open GitHub:

**Repository → Settings → Actions → Runners**

Expected status:

| Setting        | Expected value                |
| -------------- | ----------------------------- |
| Runner name    | `student-runner`              |
| Status         | Online / Idle                 |
| Default labels | `self-hosted`, `Linux`, `X64` |
| Custom label   | `student-runner`              |

### Step 5 – Final Docker and Runner Verification

Run the following commands on the EC2 instance:

```
echo "===== DOCKER VERSION ====="
docker --version

echo "===== DOCKER SERVICE STATUS ====="
sudo systemctl is-active docker

echo "===== UBUNTU USER GROUPS ====="
id ubuntu

echo "===== DOCKER ACCESS AS UBUNTU ====="
sudo -u ubuntu -H docker ps

echo "===== GITHUB RUNNER SERVICE STATUS ====="
cd ~/actions-runner
sudo ./svc.sh status
```

**Expected result:**

- Docker Engine is installed and active.
- The `ubuntu` user belongs to the `docker` group.
- Docker commands work without permission errors.
- The GitHub runner service is active.
- The runner is connected to GitHub and shows `Listening for Jobs`.
- GitHub displays the runner as **Online / Idle** with the `student-runner` label.

> **Final checkpoint:** The EC2 instance is now ready to execute GitHub Actions jobs that require Docker image builds, Trivy scans, and Docker Hub publishing through the self-hosted runner.

Add runner-label workflow verificationAdd runner security and cleanup guidance


## Phase 3– Clone the Repossitory, CI/CD Pipeline, EKS Infrastructure Provisioning and Student Microservices Deployment

#### Clone the repository:

```bash
git clone https://github.com/harathi-mutyam/micro_svc_student_app_cicd.git
cd micro_svc_student_app_cicd

git status --short
git branch --show-current
ls -la
```

**check any syntax errors in shell scripts**

```bash
chmod +x scripts/*.sh

for file in scripts/*.sh database/init.sh; do
  bash -n "$file" || exit 1
done

```

**change admin_cidr with your ec2 instance public ip**

```bash
cd ~/micro_svc_student_app_cicd

vim terraform/terraform.tfvars
```

change **admin_cidr with your # EC2 Public IP** for administrative access

Example: admin_cidr = "16.170.165.24/32"

Save it
```bash
alternative way to change admin_cicr with sed command

sed -i 's|admin_cidr = .*|admin_cidr = "YOUR_EC2_PUBLIC_IP/32"|' terraform/terraform.tfvars
git diff terraform/terraform.tfvars
````

Before push the changes to git hub repository create a classic Token for

you repository

### Create GitHub Personal Access Token (Classic)

Open GitHub click on right side top coner on your profile

picture-->settings--> Devoloper settings--> Personal access tokens

Tokens(classic)-->Click Generate new token.-->Select Generate new token

(classic).--> Enter a Note: Student-App-GitHub-Actions-->Select expiration

(e.g. 90 days)--> Select REPO check box and WorkFlow checkbox -->Click on

Generate Token -->copy the Token value and save it some where.

It will use to push anything into your repository

**open server gitbash terminal**

```bash
git pull origin main

git add  terraform/terraform.tfvars

git commit -m "Update terraform.tfvars file admin cidr with ec2"

git config --global user.email  ehmutyam@example.com

git config --global user.name harathi-mutyam

git push -u origin main

enter

Username for 'https://github.com': harathi-mutyam

Password for 'https://harathi-mutyam@github.com': Paste your saved github token here

git status

```


### Step 4: Configure GitHub Actions to publish Docker images

Code available in ci.yml file

#### create GitHub variables and secrets for Dockerhub user

Before pushing ci.yml, configure the following at Github Actions
Variables and secrets

| GitHub secret | Required value |
|---|---|
| `DOCKERHUB_TOKEN` | Docker Hub access token with push permissions |

Create docker hub username as a variable

| GitHub variable | Value |
|---|---|
| `DOCKERHUB_USERNAME` | `harathi2026` |

#### Steps to create a dockerhub token 

login to docker hub--> click on profile on right side corner-->select account settings--> select personal access

tokens--> name: student-microsvc-token ,Expiration : 30 days , Access Permissions: Repo Read & Write -->generate a token -->save the token and place

it in a github as a secret 

**Open server gitbash terminal**


```bash
cd ~/micro_svc_student_app_cicd

git pull --ff-only origin main

export DOCKERHUB_USERNAME="harathi2026"

go to docker hub copy the latest image tag

export IMAGE_TAG="paste the copied image tag here"

or

export IMAGE_TAG="$(git rev-parse HEAD)"


echo "$IMAGE_TAG"

echo "${#IMAGE_TAG}"

```

### Create A Cluster through Terraform


```bash
cd terraform

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
  --region us-east-1 \
  --name student-cluster

kubectl get nodes -o wide

```

ctrl+c

#### check nodes are ready or not

**Check EBS CSI addon:**

```bash
aws eks describe-addon \
  --cluster-name student-cluster \
  --region us-east-1 \
  --addon-name aws-ebs-csi-driver \
  --query 'addon.status' \
  --output text

```

Output must be ACTIVE

Only after EKS and its EBS CSI driver are ready:
### Create Secrets and ConfigMaps

### Step 5: Deploy Microservices Applications

**Prepare environment variables and secrets:**
```bash

# working directory must be micro_svc_student_app_cicd

cd ~/micro_svc_student_app_cicd   

# Generate environment configuration file (.env.k8s)

bash scripts/01-prepare-env.sh

# Apply namespaces, secrets, and configmaps

bash scripts/02-apply-prerequisites.sh
```

**Verify Verify configuration object and secrets:**

```bash
kubectl get secret student-secrets -n student-app

kubectl get configmaps -n student-app
```

OutPut: You should see student-secrets (with 13 keys) and ConfigMaps mysql-init and nginx-config.

**Export your Docker Hub credentials and deploy all microservices in order:**

```bash
# Export deployment variables

export DOCKERHUB_USERNAME="harathi2026"
```

go to docker hub copy the latest image tag

```bash
export IMAGE_TAG="paste the copied image tag here"

or optional way
export IMAGE_TAG="$(git rev-parse HEAD)"

```

```bash
echo "Username: $DOCKERHUB_USERNAME"
echo "Image Tag: $IMAGE_TAG"
```

**Deploy workloads:**

```bash
# Run deployment script

bash scripts/03-deploy-in-order.sh
```

**Verify Pods and Persistent Storage:**

```bash
kubectl -n student-app get pods -w

```

(Press **Ctrl + C** once database-0, auth, students, attendance, marks, frontend, and gateway are **running**)

```bash
# Check database persistent volume claim

kubectl -n student-app get pvc
```

Verification: data-database-0 status should be **Bound**.

### Step 6: Install Ingress-NGINX Controller & Expose Gateway via Ingress
1. Add the Ingress-NGINX Helm repository
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
```

Update Helm repositories:
```bash
helm repo update

# Verify:

helm repo list
```bash

You should see ingress-nginx in the repository list.

2. Install Ingress-NGINX controller

```bash

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace --set controller.service.type=LoadBalancer
```

Verify installation:

```bash
helm list -n ingress-nginx

```
3. Wait for AWS Load Balancer provisioning
```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller -w
```

Wait until EXTERNAL-IP displays an AWS hostname, for example:

```bash
NAME                       TYPE           CLUSTER-IP     EXTERNAL-IP
ingress-nginx-controller   LoadBalancer   10.x.x.x       xxxx.elb.amazonaws.com
```

Expected
 An AWS Load Balancer hostname appears instead of <pending>.

Press **Ctrl + C** after the hostname appears.

4. Apply your Ingress resource  ~/actions-runner/micro_svc_student_app_cicd

```bash
cd micro_svc_student_app_cicd

kubectl apply -f ~/micro_svc_student_app_cicd/k8s/ingress.yaml

```
Verify:

```bash
kubectl get ingress -n student-app
```
copy external Load Balancer URL.

Also check:

```bash
kubectl describe ingress -n student-app
```

### Access and Test Application in Browser


Retrieve the generated administrator credentials from your first server terminal:

```bash
grep '^DEMO_ADMIN_PASSWORD='  ~/micro_svc_student_app_cicd/.env.k8s
```

**copy the password**

**Open browser and test the application** is running or not

http://DNS ADDRESS

Username: admin

Password: (Value copied from .env.k8s) or paste the password **copied from above**

Click on login


## Phase 4 --- Argo CD GitOps deployment

### Step 1: Install and Configure Argo CD

open first server gitbash terminal:
```bash
# Create namespace and install Argo CD

kubectl create namespace argocd

kubectl get namespace argocd

kubectl apply -n argocd --server-side \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

```

              ```bash
              
              Verify: optional commands
              
              
              kubectl get pods -n argocd
              kubectl get deployments -n argocd
              kubectl get statefulsets -n argocd
              kubectl get services -n argocd
              ```


 **Wait for Argo CD server to be ready**
 
```bash
kubectl rollout status deployment/argocd-server \
  -n argocd --timeout=300s
```
**Retrieve initial admin password**

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Save the password

### Step 2: Access the Argo Cd Dashboard UI

Open one more new Gitbash Terminal

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

**http://server_ec2_publicip:8081**

username : admin

Password: paste argo cd initial admin password copied from above

Observe it argo cd dash board created

### Step 3:Apply Argo CD Application manifest:

cd ~/micro_svc_student_app_cicd

```bash

kubectl apply -f argocd/student-app-argocd.yaml

# Check application sync state

kubectl get applications -n argocd

NAME          SYNC STATUS   HEALTH STATUS

student-app     Synced       Healthy
```
Look for SYNC STATUS: Synced and HEALTH STATUS: Healthy.

Open argo dashboard in browser and check there also.

## Phase 5 --- Prometheus and Grafana Monitoring Student Microservices on Amazon EKS

**Check memore space**

```bash
cd ~/micro_svc_student_app_cicd

kubectl describe nodes | grep -A 8 "Allocated resources:"
```
#### Step 1: Install Kube-Prometheus-Stack

**Create monitoring directory and namespace**

```bash
kubectl create namespace monitoring \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl get namespace monitoring
```

**Add Prometheus Helm repository**

```bash
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
```
```bash
helm repo update
```

verify:

```bash
helm search repo prometheus-community/kube-prometheus-stack \
  --versions | grep 92.17.1

helm list -n monitoring
```

**check monitoring values file**


```bash
cat monitoring/prometheus-values.yaml

helm list -n monitoring

ubuntu@student-server:~/micro_svc_student_app_cicd$ helm list -n monitoring

NAME    NAMESPACE       REVISION        UPDATED STATUS  CHART   APP VERSION
```

**Now render the Helm chart:**

```bash
helm template kube-prometheus-stack \
prometheus-community/kube-prometheus-stack \
--version 92.17.1 \
--namespace monitoring \
-f monitoring/prometheus-values.yaml \
> /tmp/student-monitoring-rendered.yaml
```
Verify:

```bash
test -s /tmp/student-monitoring-rendered.yaml \
&& echo "PASS: Helm template rendering successful"

helm show chart \
prometheus-community/kube-prometheus-stack \
--version 92.17.1
```

### Install Prometheus and Grafana

```bash
helm upgrade --install kube-prometheus-stack \
prometheus-community/kube-prometheus-stack \
--version 92.17.1 \
--namespace monitoring \
-f monitoring/prometheus-values.yaml \
--wait \
--timeout 15m
```

Verify the installation (PVC added in grafana for dashboards persistence
purpose)

```bash
kubectl get pvc -n monitoring
```

Check STATUS:**Bound**

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

**If a monitoring Pod is Pending**

Run:

```bash
kubectl get pods -n monitoring

kubectl get events -n monitoring \
--sort-by=.lastTimestamp
```

If all pods are running continue next step

#### Step 2: Retrieve Grafana Credentials

**Get Grafana administrator password**

```bash
kubectl get secret -n monitoring kube-prometheus-stack-grafana

kubectl get secret kube-prometheus-stack-grafana \
-n monitoring \
-o jsonpath='{.data.admin-password}' | base64 -d
echo
```

Save the password

##### Step 3 : Port-Forward Grafana Dashbord

open one more gitbash terminal for grafana

```bash
ssh -i ~/Downloads/student-key-cicd.pem ubuntu@server_public_ip
sudo hostnamectl set-hostname Grafana
exec bash

```
```bash
kubectl port-forward \
-n monitoring \
svc/kube-prometheus-stack-grafana \
3000:80 --address=0.0.0.0

Forwarding from 127.0.0.1:3000 -> 80
Forwarding from [::1]:3000 -> 80
```
##### **Verify in Browser:**

http://<YOUR_EC2_PUBLIC_IP>:3000 in your browser. 

Log in with user : **admin** and the password:  **retrieved above**)

#### Check your Kubernetes dashboards

Inside Grafana: 

  1.  Select Dashboards from the left navigation.

  2.  Look for the Kubernetes dashboards installed by kube-prometheus-stack.

  3.  **Open Kubernetes / Compute Resources / Cluster**.

  4.  Review CPU utilization, memory utilization, and Pod resource usage.

  5.  select the Namespace dropdown in dashboard and select student-app (where

        the namespace variable is available.)

Click on dash boards--> **Kubernetes / Compute Resources / Namespace (Pods)** --> 

inside select namespace: **student-app (on top)**

<img width="940" height="515" alt="image" src="https://github.com/user-attachments/assets/5a59fbef-0362-49d2-9b72-8cf5191194cc" />


<img width="940" height="628" alt="image" src="https://github.com/user-attachments/assets/81ccef62-e746-42c2-bff0-2c4d17ae0ca5" />

**Dashboards Kubernetes / Compute Resources / Namespace (Workloads)** --> select namespace: student-app


<img width="940" height="624" alt="image" src="https://github.com/user-attachments/assets/5767ddfd-d5a6-4330-8ed7-ff7bc41dfd9b" />


Navigate to Memory Quota-->Click on student or marks or any service


<img width="940" height="632" alt="image" src="https://github.com/user-attachments/assets/5c6213bf-f7ba-4cca-b806-a474f775aebd" />


Dashboards **Kubernetes / Compute Resources / Namespace (Workloads)** select namespace: argocd


<img width="940" height="654" alt="image" src="https://github.com/user-attachments/assets/eba7ab66-3bc6-4884-82b3-42ffec3e3e46" />


Dashboards **Kubernetes / Compute Resources / Namespace (Workloads)** select namespace: monitoring

<img width="940" height="531" alt="image" src="https://github.com/user-attachments/assets/fbcfc1ae-dcbe-44fe-94cf-e4579b11b7b0" />


#### Verify metrics directly in Grafana

Navigate to Explore, select the Prometheus data source -->on right side  

select code --> and run this PromQL expression: up --> click on Run Query

<img width="940" height="520" alt="image" src="https://github.com/user-attachments/assets/44c02f40-ec92-4fe8-b041-9fb9d2cf58d9" />


<img width="940" height="637" alt="image" src="https://github.com/user-attachments/assets/3be63e5e-c346-4635-89a6-6e4bcfb38b74" />


Next, query your **Student application Pods**:

```bash
kube_pod_status_phase{
  namespace="student-app",
  phase="Running"
}
```

<img width="940" height="638" alt="image" src="https://github.com/user-attachments/assets/6b2c2926-35e7-4e5c-b452-3df41ea218fa" />


**For container CPU usage**:
```bash
sum by (pod) (
  rate(
    container_cpu_usage_seconds_total{
      namespace="student-app",
      container!="",
      container!="POD"
    }[5m]
  )
)
```

<img width="940" height="598" alt="image" src="https://github.com/user-attachments/assets/605ebf58-a38b-4d5d-97de-c8689e809497" />


<img width="940" height="512" alt="image" src="https://github.com/user-attachments/assets/3fd711a5-4a6b-4279-8a4e-e8a2b78ae8e0" />


Delete the old Query and enter

**For container memory:**
```bash
sum by (pod) (
  container_memory_working_set_bytes{
    namespace="student-app",
    container!="",
    container!="POD"
  }
)
```
<img width="940" height="646" alt="image" src="https://github.com/user-attachments/assets/0781f9bd-9bb5-4ebd-b62b-92a792caee61" />


<img width="940" height="651" alt="image" src="https://github.com/user-attachments/assets/a834022d-a262-42ff-8b6b-6d88af044205" />


<img width="940" height="421" alt="image" src="https://github.com/user-attachments/assets/5ddb021d-22ff-4ff5-9ee8-4d7b8e94078a" />



Create a Dashboard for application in Grafana in 2 ways **either manualway or through json**

#### Method 1: Build Panels Manually in Grafana UI

Open Grafana at **http://<YOUR_EC2_PUBLIC_IP>:3000**.

##### Step 1: Create a new dashboard
  1.  Open Grafana.
  2.  Click Dashboards in the left sidebar.
  3.  Click New → New Dashboard.
  4.  Click the + (plus icon) in the top-right corner or left menu, and select New Dashboard
  5.  Click + Add visualization.
  6.  Select prometheus (or kube-prometheus-stack-prometheus) as the data source
  

Verification: A new panel configuration screen appears with a query editor at the bottom.


##### Step 2: Panel 1: Running Pods Status (Stat Panel):

   1.  PromQL Query:
      ```bash
      sum(kube_pod_status_phase{namespace="student-app", phase="Running"})
      ```

  2.  On the right-hand panel settings, change the visualization type from Time series to **Stat**.

  3.  Under Panel options, set Title to Healthy Running Pods.
  4.  Click Apply in the top right.

Verification: The panel displays a numeric count of your running pods (e.g., 7).

##### Step 3: Panel 2: CPU Utilization by Microservice (Time Series):

    1.  Click + Add --> Visualization.
    2.  PromQL Query:
    
         ```bash
           sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="student-app", container!="", container!="POD"}[5m]))
         ```
    3.  Under **Legend** , set the label format to {{pod}}.
    4.  Set **Title** to CPU Usage per Pod (Cores).
    5.  Under **Standard options -> Unit**, choose **Data Rate / Throughput** or type **cores**.
    6.  Click Apply.

Verification: A multi-line graph displays CPU usage curves for each service.

##### Step 4 : Panel 3: Memory Usage by Microservice (Time Series):

    1.  Click + Add --> Visualization.
    2.  PromQL Query:
         ```bash
           sum by (pod) (container_memory_working_set_bytes{namespace="student-app", container!="", container!="POD"})
          ```
    3.  Under Legend, enter {{pod}}.
    4.  Set Title to Memory Working Set (RAM).

    5.  Under Standard options --> Unit, select Data (IEC) --> Bytes (IEC) or Megabytes (MiB).

    6.  Click Apply.

  Verification: Graphs show real-time memory usage (e.g.: ~120 MiB fordatabase-0).

##### Step 5 :Panel 4: Network Ingress/Egress Throughput:

1.  Click + Add --> Visualization.
2.  Query A (Received):
  ```bash
    sum by (pod) (rate(container_network_receive_bytes_total{namespace="student-app"}[5m]))

  ```
3.  Legend: {{pod}} - Ingress
4.  Query B (Transmitted):
    ```bash
    sum by (pod) (rate(container_network_transmit_bytes_total{namespace="student-app"}[5m]))

    ```
5.  Legend: {{pod}} - Egress
6.  Under Standard options -> Unit, select Data Rate -> Bytes/sec.
7.  Set Title to Pod Network Traffic (Bytes/sec).
8.  Click Apply.

Verification: Traffic throughput graphs show up when requests are sent through the gateway.
##### Step 6: SAVE Your Dashboard

  1.  Click the Disk icon (Save dashboard) in the top-right toolbar.

  2.  Enter the name Student Microservices Overview and click Save.
     

Verification: The dashboard title updates to "Student Microservices Overview" and persists upon page refresh.

#### Method 2: Import via Ready-to-Use Dashboard JSON ( Import Application Dashboard)

Import a pre-configured dashboard using the JSON model to instantly set up all panels.

1. Retrieve the Dashboard JSON

   option 1: From your server terminal:

    ```bash
       cat monitoring/grafana-dashboard.json

    ```

    Copy the entire terminal output.
    
    option 2 :	Or directly from GitHub: Navigate to https://github.com/harathi-mutyam/micro_svc_student_app_cicd/blob/main/monitoring/grafana-dashboard.json
   
    in your project repository, click Raw, and copy the text.
   

3. Import into Grafana
    1.	In Grafana, click Dashboards in the left sidebar.
    2.	Click New -> Import.
    3.	Under Import via panel json, paste the copied JSON text.

Click Load.  --> Click import

For verification:

go to Dash Boards-->select Student Microservices Application Dashboard--> and confirm all metric panels are streaming data.

### Step :Run Traffic Test to Observe Real-Time Spikes

Open server gitbash terminal run these commands

# Get your Ingress Load Balancer address automatically
```bash
export INGRESS_HOST=$(kubectl get ingress student-app-ingress -n student-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

```
# If running on Minikube/Kind or using IP, use:

```bash

echo "Targeting Ingress: http://$INGRESS_HOST"

BASE_URL="http://${INGRESS_HOST}"

echo "Targeting Ingress: $BASE_URL"

# Generate traffic
for i in {1..200}; do
  curl -fsS "$BASE_URL/api/auth/health" > /dev/null
  curl -fsS "$BASE_URL/api/students/health" > /dev/null
  curl -fsS "$BASE_URL/api/attendance/health" > /dev/null
  curl -fsS "$BASE_URL/api/marks/health" > /dev/null

  if (( i % 50 == 0 )); then
    echo "Completed $((i * 4)) requests..."
  fi
done

echo "Traffic test complete: 800 successful HTTP requests."

```

Open Grafana Dashboard in browser **http://<YOUR_EC2_PUBLIC_IP>:3000**

**In the top-right corner:**

    1.  Change the time range to Last 5 minutes or Last 15 minutes.
    
    2.  Set the auto-refresh interval to 5s (next to the Refresh button).

**Check the panels:**

    1.  Network Ingress (Received): Sharp spikes will appear for gateway, auth,students, attendance, and marks.
      
    2.  CPU Usage per Pod: Microservice CPU utilization lines will spike upwards during the burst.
    

<img width="884" height="444" alt="image" src="https://github.com/user-attachments/assets/bcc03a3f-91da-4301-a202-b128162bf1ef" />


<img width="940" height="579" alt="image" src="https://github.com/user-attachments/assets/b11f410d-1b60-43e9-afac-518dc0828f04" />



## Phase 6: Loki (logging S3 Backend via IRSA) and Grafana Alloy

Open server gitbash terminal

#### Step 1: Check Node Resources & Add Helm Repository
```bash
#Check memory space

kubectl describe nodes | grep -E "DiskPressure|Allocated resources" -A 8

```

```bash
helm repo add grafana https://grafana.github.io/helm-charts

helm repo update

```
### Step 2: Export Environment Variables & Create S3 Buckets

```bash
cd ~/micro_svc_student_app_cicd

export AWS_REGION="us-east-1"
export CLUSTER_NAME="student-cluster"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export LOKI_CHUNKS_BUCKET="student-loki-chunks-${ACCOUNT_ID}-${AWS_REGION}"
export LOKI_RULER_BUCKET="student-loki-ruler-${ACCOUNT_ID}-${AWS_REGION}"
echo "Account: $ACCOUNT_ID | Cluster: $CLUSTER_NAME | Region: $AWS_REGION"
echo "Chunks Bucket: $LOKI_CHUNKS_BUCKET"
echo "Ruler Bucket: $LOKI_RULER_BUCKET"

```

##### Step 3: Create the S3 buckets

```bash
aws s3api create-bucket --bucket "$LOKI_CHUNKS_BUCKET" --region "$AWS_REGION"
aws s3api create-bucket --bucket "$LOKI_RULER_BUCKET" --region "$AWS_REGION"

for BUCKET in "$LOKI_CHUNKS_BUCKET" "$LOKI_RULER_BUCKET"; do
  aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

  aws s3api put-bucket-encryption \
    --bucket "$BUCKET" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
Done


```
```bash
aws s3 ls | grep student-loki
```

#### step 4: Install eksctl & Configure IAM Roles for Service Accounts (IRSA)

**Install eksctl**

```bash
if ! command -v eksctl &> /dev/null; then
  curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz"
  tar -xzf eksctl_Linux_amd64.tar.gz
  sudo install -m 0755 eksctl /usr/local/bin/eksctl
  rm -f eksctl eksctl_Linux_amd64.tar.gz
fi

eksctl version

```
```bash
eksctl version
```

**Associate OIDC Provider with your EKS cluster:**
```bash
eksctl utils associate-iam-oidc-provider --cluster "$CLUSTER_NAME" \
--region "$AWS_REGION" --approve
```

#### Step 5: Create the IAM Policy for S3 access

  **Using this file to create a policy or run manual way**
      
##### Using Script file 
```bash
chmod +x ./scripts/create-loki-s3-policy.sh

./scripts/create-loki-s3-policy.sh \
  "$LOKI_CHUNKS_BUCKET" \
  "$LOKI_RULER_BUCKET"

```
#### optional way using manual way create a IAM Policy follow above or this way
```bash
Or this way 

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

aws iam create-policy \
  --policy-name StudentLokiS3Policy \
  --policy-document file:///tmp/student-loki-s3-policy.json 2>/dev/null || true

```

#### Step 6: Create the logging namespace & ServiceAccount

**Check IAM created Policy**

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

### Step 7: Configure and Deploy Loki with S3 Backend

**Add the Grafana Community Helm repository**

```bash
helm repo add grafana-community \
 https://grafana-community.github.io/helm-charts

```

```bash
helm repo update
```

**Check logging/loki-values.yaml**
```bash
  cat logging/loki-values.yaml

```
### Step 8: Deploy Loki

```bash
helm upgrade --install loki grafana-community/loki \
  --version 19.0.3 \
  --namespace logging \
  -f logging/loki-values.yaml \
  --wait \
  --timeout 10m

```

```bash
kubectl get pods -n logging

NAME                           READY   STATUS    RESTARTS   AGE
loki-0                         2/2     Running   0          90s
loki-canary-hhh9q              1/1     Running   0          90s
loki-canary-qlhpv              1/1     Running   0          90s
loki-gateway-9847cdff6-dsgv9   2/2     Running   0          90s

```

### Step 9: Install Grafana Alloy to Ship Pod Logs

**Add the official Grafana Helm repository:**

```bash
helm repo add grafana https://grafana.github.io/helm-charts

helm repo update
```

**Create or Verify logging/alloy-values.yaml**
```bash
  cat logging/alloy-values.yaml
```
### Step 10 :Deploy Alloy as a DaemonSet

```bash
helm upgrade --install alloy grafana/alloy \
  --version 1.14.1 \
  --namespace logging \
  -f logging/alloy-values.yaml \
  --wait \
  --timeout 10m

kubectl get ds -n logging

NAME          DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
alloy         2         2         2       2            2           <none>          86s
loki-canary   2         2         2       2            2           <none>          7m3s

```
### Step 11 : Connect Loki in Grafana & Query Logs

1.  Open Grafana in your web browser http://<YOUR_EC2_PUBLIC_IP>:3000

2.  Go to **Connections** --> **Data sources** --> click **Add data source**.

3.  Select Loki.

4.  In the Connection URL field, enter: **http://loki-gateway.logging.svc.cluster.local/**

5.  Scroll down and click Save & test. (You should see a green notification.Then Data source successfully connected)

### Step 12: Query Application Logs in Grafana Explore

Navigate to Explore -->select **Loki** -->select **Code mode**(switch to code mode) --> paste the **{namespace="student-app"}** --> click on Run query

```bash
          With Explanation:
          
          Click Explore (compass icon) in Grafana's left navigation sidebar.
          
          Select Loki from the top data source dropdown.
          
          Switch to Code mode and test your Student Microservices queries
````

**All Student Microservices Logs:**

```bash
{namespace="student-app"}
```

**Specific Service Logs (e.g., Auth or Students):**

```bash
{namespace="student-app", app="auth"}
{namespace="student-app", app="students"}
```

**MySQL Database Logs:**

```bash
{namespace="student-app", app="database"}
```

**Search for errors:**

```bash
{namespace="student-app"} |= "error"
```

### Step 13 : Add a Live Logs Panel to Your Existing Dashboard

1. Open your **Student Microservices Application Dashboard** in Grafana.

2. Click Edit--> **Add --> Visualization** (top toolbar).

3. Select data source **Loki**.

4. Enter the query: **{namespace="student-app"}**

5. On the right-hand settings panel, change visualization type to **Logs**.

6. Set the Panel Title to Student Microservices - Live Logs

7. Click **Apply** in the top right, then click the **Save** disk icon.

Same way check for marks also and add visulisation

```bash
{namespace="student-app", app="students"}
```

Verification: The panel displays auto-refreshing log streams directly 

beneath your existing CPU, RAM, and Network metrics panels.


<img width="940" height="436" alt="image" src="https://github.com/user-attachments/assets/fba890e6-137e-4154-8e2d-7e9940697bd8" />


## Phase 7: Verify AWS S3 Log Persistence

Open aws console --> open s3--> open chunks bucket-->check logs are present or not

### Step 1: Generate application traffic to trigger write logs

Open server gitbash terminal

# Export the Ingress host URL if not already exported
```bash
export INGRESS_HOST=$(kubectl get ingress student-app-ingress -n student-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

# Generate application traffic through the Ingress controller
```bash
for i in {1..30}; do
  curl -s "http://${INGRESS_HOST}/api/auth/health" > /dev/null
  curl -s "http://${INGRESS_HOST}/api/students/health" > /dev/null
done

echo "Traffic generated successfully through Ingress."

```


```bash
for i in {1..30}; do
  curl -s http://127.0.0.1:8080/api/auth/health > /dev/null
  curl -s http://127.0.0.1:8080/api/students/health > /dev/null
done

```





open Grafana dash board in browser-->change Refresh time to 5 seconds

observe the logs are refreshing now


### Step 2: Inspect Chunks Stored in S3 

**Open server gitbash Terminal**

```bash
aws s3 ls "s3://${LOKI_CHUNKS_BUCKET}/" --recursive --summarize
```

## Phase 8: Alertmanager Setup & Student App Alerting Rules

### Step 1: Verify Alertmanager Is Running

```bash
kubectl get pods -n monitoring \
 -l "app.kubernetes.io/name=alertmanager"

kubectl get svc -n monitoring \
 -l "app.kubernetes.io/name=alertmanager"


NAME                                                READY   STATUS    RESTARTS   AGE
alertmanager-kube-prometheus-stack-alertmanager-0   2/2     Running   0          

```

### Step 2: Create Custom Prometheus Alert Rules for student-app

Created a Kubernetes PrometheusRule Custom Resource Definition (CRD)

that tells Prometheus when to trigger alerts for pod down events, high

CPU usage, crash loops, and database connectivity failures.

```bash
cat monitoring/student-app-alerts.yaml


kubectl apply -f monitoring/student-app-alerts.yaml

```

### Step 3 : Verify the Alert Rules in Prometheus UI

**Port-forward the Prometheus server:**

Open one new git bash terminal

```bash
ssh -i ~/Downloads/student-key-cicd.pem ubuntu@3.80.204.112

sudo hostnamectl set-hostname Prometheus-alertmanager

exec bash
```
```bash
kubectl port-forward -n monitoring \
 svc/kube-prometheus-stack-prometheus 9090:9090 --address=0.0.0.0

```

### Step 4: Access Alerts in Browser

Open your browser **http://<YOUR_EC2_PUBLIC_IP>:9090/alerts**

Verification: Scroll down to find the group student-app.rules. You will

see your 4 rules: **or search student**

          1.  StudentMicroserviceDown
          
          2.  StudentPodFrequentRestart
          
          3.  MySQLDatabaseDown
          
          4.  StudentPodHighMemory

Note: All rules should initially display with a **green**

If You see one firing Some alert is there.



```bash
optional procedure

Open Server gitbash Terminal

  vim monitoring/student-app-alerts.yaml

Firing related one **time to 3 to 1**

Observe apply it again


kubectl apply -f monitoring/student-app-alerts.yaml


Within 1--2 minutes, all 4 rules in the Prometheus /alerts tab will transition to green INACTIVE (4).
```
### Step 5: Access the Alertmanager Web UI

Open one more gitbash

```bash
ssh -i ~/Downloads/student-key-cicd.pem ubuntu@server_public_ip

sudo hostnamectl set-hostname alertmanager

exec bash

```


```bash
kubectl port-forward -n monitoring \
 svc/kube-prometheus-stack-alertmanager 9093:9093 \
 --address=0.0.0.0

```

### Step 6:Access Alert manager in browser

Open Alertmanager in Your Browser

**http://<YOUR_EC2_PUBLIC_IP>:9093**

Verification: Active alerts routed from Prometheus appear under the **Alerts** tab with their associated labels and annotations.

## Phase 9::Clean UP Procedure

cd micro_svc_student_app_cicd

### Step 1: Delete Prometheus, Alertmanager, and Grafana (including Grafana PVC):

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

### Step 2: Delete Loki and Alloy Logging Components:

```bash
helm uninstall alloy -n logging
helm uninstall loki -n logging
kubectl delete pvc --all -n logging
kubectl delete namespace logging
```

### Step 3: Delete Argo CD & Application Resources:

```bash
# Remove Argo CD application

kubectl delete -f argocd/student-app-argocd.yaml --ignore-not-found
```
**Delete student application workloads and database PVC (releases the AWS EBS volume)**
```bash

kubectl delete namespace student-app
kubectl delete pvc data-database-0 -n student-app --ignore-not-found

```
**Uninstall Argo CD**
```bash
kubectl delete -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
  --ignore-not-found


kubectl delete namespace argocd
```


### Step 4: Delete Loki IAM Service Account and Policy

**1.  Set variables**

```bash
export AWS_REGION="us-east-1"
export CLUSTER_NAME="student-cluster"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/StudentLokiS3Policy"

```

**2.  Delete IAM Service Account**

```bash
eksctl delete iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --namespace logging \
  --name loki

```

**3.  Check policy attachments**

```bash
aws iam list-entities-for-policy \
  --policy-arn "$POLICY_ARN" \
  --output table

```

**4.  Check attachment count**

```bash
aws iam get-policy \
  --policy-arn "$POLICY_ARN" \
  --query 'Policy.AttachmentCount'

```

**5.  Delete IAM policy**

Only when attachment count is 0:

```bash
aws iam delete-policy \
  --policy-arn "$POLICY_ARN"

```

**6.  Verify deletion**

```bash
aws iam get-policy \
  --policy-arn "$POLICY_ARN"

```

### Step 5: Empty and Delete the Loki S3 Buckets

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
#### Step 6: Uninstall Ingress-NGINX Controller

1.  **Uninstall Ingress-NGINX Helm release**
```bash

helm uninstall ingress-nginx -n ingress-nginx
```
2.  **Delete Ingress-NGINX namespace**
```bash

kubectl delete namespace ingress-nginx

helm list -n ingress-nginx

kubectl get namespace ingress-nginx

```
### Step 7: Destroy EKS Cluster through Terraform

```bash
cd ~/micro_svc_student_app_cicd/terraform


terraform destroy -auto-approve

```
### Step 8: Stop the Runner
```bash

cd ~/actions-runner

sudo ./svc.sh stop

exit

````
### Step 9: Terminate ec2 instance in aws console

Open Ec2 instance in aws console select ec2 instance terminate it
