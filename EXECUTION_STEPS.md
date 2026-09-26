# Kubernetes Tetris — End-to-End DevSecOps Project  
**Execution Steps for AWS Deployment**  

This guide provides **clear, sequential steps** to deploy the Tetris game to AWS EKS using the full DevSecOps pipeline (Jenkins CI → Trivy scans → ECR → GitOps → ArgoCD → EKS → Monitoring).  
**Prerequisites**: AWS account, AWS CLI, Terraform, kubectl, Helm, Docker, GitHub account, Docker Hub account.  
*All commands assume you're in the project root directory (`tetris-devsecops`).*

---

## 🔧 Phase 1: Provision AWS Infrastructure
### 1. Initialize & Apply Terraform
```bash
cd terraform
terraform init
terraform plan  # Review the plan (resources to be created)
terraform apply  # Type 'yes' when prompted
```
- **What this creates**: VPC, EKS cluster (`tetris-devsecops`), ECR repository, IAM roles.
- **After completion**, update your kubeconfig to connect to the EKS cluster:
  ```bash
  aws eks update-kubeconfig --region ap-south-1 --name tetris-devsecops
  ```
- **Verify connection**:
  ```bash
  kubectl get nodes
  # Should show EKS worker nodes
  ```

### 2. Install Cluster Add-ons
```bash
# AWS Load Balancer Controller (for ALB Ingress)
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=tetris-devsecops

# Prometheus + Grafana (monitoring stack)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prom-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f monitoring/prometheus-values.yaml

# ArgoCD (GitOps continuous delivery)
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 3. Bootstrap ArgoCD
```bash
# Apply ArgoCD Application manifest (watches k8s/base/ for manifests)
kubectl apply -f k8s/argocd/application.yaml

# Get initial ArgoCD admin password (needed for UI login)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

# Port-forward to access ArgoCD UI (leave this running in a separate terminal)
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
- **Access ArgoCD UI**: Open `https://localhost:8080` in your browser
- **Login**: Username `admin`, Password = output from the `get secret` command above
- **ArgoCD will automatically**: 
  1. Create the `tetris` namespace
  2. Sync all manifests from `k8s/base/` (Deployment, Service, HPA, NetworkPolicy, etc.)
  3. Deploy the Tetris application (initially waiting for Jenkins to push the first image)

---

## ⚙️ Phase 2: Configure Jenkins (CI Server)
> **Note**: Jenkins is *not* provisioned by Terraform in this repo. You must set up a Jenkins server separately (e.g., on an EC2 instance, Docker, or Jenkins.io).  
> *If you don't have Jenkins ready, use [Jenkins Docker](https://www.jenkins.io/doc/book/installing/docker/) for quick setup.*

### 4. Install Required Jenkins Plugins
In Jenkins UI → **Manage Jenkins** → **Manage Plugins** → **Available**, install:
- Docker Pipeline
- AWS Credentials
- SSH Agent
- (Optional) Trivy (if not installing Trivy CLI on Jenkins agent)

### 5. Configure Jenkins Credentials
In Jenkins UI → **Manage Jenkins** → **Manage Credentials** → **System** → **Global credentials (unrestricted)** → **Add Credentials**:
| Credential Type | Scope | ID | Description | Details |
|----------------|-------|----|-------------|---------|
| **Username with password** | Global | `dockerhub-creds` | Docker Hub credentials | Username = your Docker Hub ID, Password = your Docker Hub access token |
| **SSH Username with private key** | Global | `github-deploy-key` | GitHub deploy key | Username = `git`, Private key = SSH key with **write access** to this GitHub repo (generate via `ssh-keygen` and add to repo Settings → Deploy keys) |

### 6. Create the Jenkins Pipeline Job
1. In Jenkins UI → **New Item** → Enter item name (e.g., `tetris-devsecops-pipeline`)
2. Select **Pipeline** → Click **OK**
3. Under **Pipeline**:
   - **Definition**: `Pipeline script from SCM`
   - **SCM**: `Git`
   - **Repository URL**: `https://github.com/ADITYASURVE123/tetris-devsecops.git` (or your fork URL)
   - **Credentials**: *(If using private repo, add GitHub credentials here)*
   - **Script Path**: `Jenkinsfile`
4. Click **Save**

### 7. Trigger the First Build
- Click **Build Now** on the pipeline job, **OR**
- Push an initial commit to start the pipeline automatically:
  ```bash
  git add .
  git commit -m "Initial commit to trigger DevSecOps pipeline"
  git push origin main
  ```

---

## 🚀 Phase 3: Verify the Deployment
### 8. Monitor the Pipeline in Jenkins
- Watch the pipeline progress through stages:
  1. Checkout → SCA (Trivy fs scan) → SAST → Build Image → Trivy Image Scan → Push to Docker Hub → GitOps: Bump Image Tag
- **Key security gates**: 
  - Trivy fs/image scans **fail the build** on HIGH/CRITICAL vulnerabilities
  - Only images passing scans get pushed to Docker Hub and deployed via ArgoCD

### 9. Confirm ArgoCD Sync & Application Status
- In ArgoCD UI (https://localhost:8080):
  - The `tetris-devsecops` application should show **Synced** and **Healthy**
  - Under **Resources**, verify:
    - Deployment `tetris-app` is running
    - Service `tetris-app` exposes port 8080
    - Ingress `tetris-ingress` is created (by AWS Load Balancer Controller)
- **Get the ALB URL to access the game**:
  ```bash
  kubectl get ingress -n tetris
  # Output will show ADDRESS like: a1b2c3d4e5f6g7h8i9j0k.lmno.ap-south-1.elb.amazonaws.com
  ```
- **Open in browser**: `http://<ADDRESS_FROM_ABOVE>`  
  (Replace `<ADDRESS_FROM_ABOVE>` with the actual ADDRESS from the command above)

### 10. Access Monitoring (Optional)
```bash
# Port-forward Grafana (leave running)
kubectl port-forward svc/kube-prom-stack-grafana -n monitoring 3000:80
```
- **Access Grafana**: Open `http://localhost:3000`
- **Login**: 
  - Username: `admin`
  - Password: Find in `monitoring/prometheus-values.yaml` under `grafana.adminPassword` (default is `prom-operator`)
- **Import Tetris dashboard**: 
  - Click **+** → **Import** → Paste JSON from `monitoring/tetris-dashboard.json` → Load

---

## 📝 Important Notes & Troubleshooting
| Scenario | Solution |
|----------|----------|
| **"Image not found" in Trivy scan** | Ensure Docker daemon is running on Jenkins agent. Install Docker on the Jenkins node if using self-hosted agents. |
| **ArgoCD shows "OutOfSync"** | Check if Jenkins successfully pushed the image tag bump to GitHub. Verify `github-deploy-key` has write permissions. |
| **Game not loading at ALB URL** | <ul><li>Check ALB provisioning: `kubectl get ingress -n tetris -w` (wait for ADDRESS to appear)</li><li>Verify Ingress resources: `kubectl describe ingress tetris-ingress -n tetris`</li><li>Check pod logs: `kubectl logs -n tetris -l app=tetris-app`</li></ul> |
| **Jenkins fails at Docker push** | Validate `dockerhub-creds` credentials in Jenkins. Test Docker Hub login manually on Jenkins agent: `docker login` |
| **Want to use ECR instead of Docker Hub?** | <ol><li>Update `DOCKER_REPO` in Jenkinsfile to your ECR repo URI (from Terraform output)</li><li>Add AWS ECR credentials to Jenkins (IAM role or access keys)</li><li>Replace `docker push` with AWS ECR login steps in Jenkinsfile</li></ol> |
| **Clean up resources** | ```bash\ncd terraform\nterraform destroy\n# Then manually delete: ECR images, Docker Hub images, EKS-related AWS resources (if any remain)\n``` |

---

## ✅ You're Done!
The Tetris game is now running on AWS EKS with full DevSecOps automation:
- **CI**: Jenkins builds, scans (Trivy fs/image), and pushes secure images to Docker Hub
- **GitOps**: ArgoCD watches the repo and auto-deploys image tag updates
- **Security**: Non-root pods, read-only filesystem, NetworkPolicy (default-deny), Trivy gates
- **Observability**: Prometheus scrapes metrics, Grafana dashboard shows requests/sec, CPU, memory, pod count
- **Access**: Play the game at the ALB URL obtained in Step 9

> 💡 **Tip**: To see the pipeline in action, make a code change (e.g., update `app/style.css`), commit, and push. Watch Jenkins rebuild, rescan, and ArgoCD auto-sync the new version—all without manual `kubectl apply`!  
> **Co-Authored-By**: Claude Code <noreply@anthropic.com>