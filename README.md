# Wiz Technical Exercise — AWS Infrastructure

**Candidate:** Silvia Rodriguez Garcia

## Architecture Overview

```
Internet
   │
   ▼
[AWS ALB]  ←── internet-facing, managed by AWS LB Controller
   │
   ▼
[EKS Cluster — Private Subnets]
   │  tasky pod (containerised Go app)
   │  ClusterRoleBinding → cluster-admin  ⚠️ intentional weakness
   │
   ├──→ [MongoDB EC2 — Public Subnet]   port 27017 (EKS nodes only)
   │      Ubuntu 18.04 + MongoDB 4.4    ⚠️ intentionally outdated
   │      SSH open to 0.0.0.0/0         ⚠️ intentional weakness
   │      IAM: AmazonEC2FullAccess      ⚠️ intentional weakness
   │
   └──→ [S3 Bucket — public read/list]  ⚠️ intentional weakness
          Daily mongodump backups via cron
```

## Intentional Weaknesses (for Wiz exercise)

| Resource | Weakness | Why |
|---|---|---|
| MongoDB EC2 | Ubuntu 18.04 (EOL Apr 2023) | 1+ year outdated OS |
| MongoDB | Version 4.4 | 1+ year outdated DB |
| EC2 Security Group | SSH `0.0.0.0/0` | Exposed to internet |
| EC2 IAM Role | `AmazonEC2FullAccess` | Can create VMs |
| S3 Bucket | Public read + list ACL | Backup data exposed |
| EKS Pod | `cluster-admin` ClusterRoleBinding | Over-privileged workload |
| EBS Volume | Not encrypted | Data-at-rest exposure |

---

## Prerequisites

- AWS CLI configured with admin permissions
- Terraform >= 1.5.0
- kubectl
- Helm >= 3.14
- Docker
- An existing EC2 key pair in your target region

---

## Step 1 — Deploy Infrastructure with Terraform

```bash
cd terraform/

# 1. Export AWS access keys as environment variables
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""

# 2. Initialise
terraform init

# 3. Preview
terraform plan

# 4. Apply (~15-20 mins due to EKS)
terraform apply
```

Note the outputs — you'll need:
- `mongodb_private_ip` for the connection string
- `ecr_repository_url` for pushing the image
- `eks_cluster_name` for kubeconfig
- `aws_lbc_role_arn` for the LB controller

---

## Step 2 — Configure kubectl

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name wiz-exercise-eks
kubectl get nodes
```

---

## Step 3 — Install the AWS Load Balancer Controller

```bash
# Add the Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install the controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=wiz-exercise-eks \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<aws_lbc_role_arn from terraform output>

# Verify
kubectl get deployment -n kube-system aws-load-balancer-controller
```

---

## Step 4 — Build & Push the Container Image

```bash
cd app/

# Authenticate to ECR
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin <ECR_REGISTRY>

# Build (wizexercise.txt is already in the app/ directory)
docker build -t <ECR_REGISTRY>/wiz-exercise/tasky:latest .

# Verify wizexercise.txt is in the image
docker run --rm <ECR_REGISTRY>/wiz-exercise/tasky:latest cat /app/wizexercise.txt
# Expected output: Silvia Rodriguez Garcia

# Push
docker push <ECR_REGISTRY>/wiz-exercise/tasky:latest
```

---

## Step 5 — Deploy the App with Helm

```bash
# Construct the MongoDB URI (use private IP from terraform output)
MONGODB_URI="mongodb://tasky:<app_password>@<mongodb_private_ip>:27017/go-mongodb?authSource=go-mongodb"

# Deploy
helm upgrade --install tasky ./helm/tasky \
  --namespace default \
  --set image.repository="<ECR_REGISTRY>/wiz-exercise/tasky" \
  --set image.tag="latest" \
  --set mongodb.uri="$MONGODB_URI" \
  --wait --timeout 5m

# Check rollout
kubectl rollout status deployment/tasky-tasky
kubectl get pods
kubectl get ingress   # get ALB DNS name
```

---

## Step 6 — Validate the Deployment

```bash
# 1. Check wizexercise.txt inside the running container
POD=$(kubectl get pods -l app.kubernetes.io/name=tasky -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- cat /app/wizexercise.txt
# Expected: Silvia Rodriguez Garcia

# 2. Check the ClusterRoleBinding (intentional weakness)
kubectl get clusterrolebinding tasky-tasky-cluster-admin -o yaml

# 3. Access the app
ALB_URL=$(kubectl get ingress tasky-tasky -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "App URL: http://$ALB_URL"
curl -s http://$ALB_URL | grep -i tasky

# 4. Verify MongoDB backup in S3
aws s3 ls s3://wiz-exercise-mongo-backups/backups/
```

---

## CI/CD Pipelines (GitHub Actions)

### Required GitHub Secrets

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_REGION` | e.g. `us-east-1` |
| `MONGODB_PASSWORD` | MongoDB admin password |
| `MONGODB_APP_PASSWORD` | MongoDB app user password |
| `MONGODB_URI` | Full connection string for the app |
| `ECR_REGISTRY` | ECR registry hostname |
| `ECR_REPOSITORY` | e.g. `wiz-exercise/tasky` |
| `EKS_CLUSTER_NAME` | e.g. `wiz-exercise-eks` |

### Pipeline 1 — `terraform-deploy.yml`

Triggered on push/PR to `terraform/**`:
1. **IaC Security Scan** — Checkov + tfsec, results uploaded to GitHub Security tab
2. **Terraform Plan** — validates and plans, posts plan to PR as comment
3. **Terraform Apply** — applies on merge to `main` (requires `production` environment approval)

### Pipeline 2 — `app-build-deploy.yml`

Triggered on push/PR to `app/**` or `helm/**`:
1. **Build** — builds Docker image, pushes to ECR
2. **Image Security Scan** — Trivy + Grype CVE scan, SARIF to GitHub Security
3. **Deploy** — Helm upgrade to EKS, validates `wizexercise.txt` in running pod

---

## Teardown

```bash
# Remove Kubernetes resources
helm uninstall tasky

# Destroy infrastructure
cd terraform/
terraform destroy
```
