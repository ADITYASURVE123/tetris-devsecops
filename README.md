# Kubernetes Tetris — End-to-End DevSecOps Project

A playable Tetris game deployed to AWS EKS through a full DevSecOps pipeline:
**Jenkins (CI) → Trivy (Security Gate) → ECR → Git (GitOps) → ArgoCD (CD) → EKS → Prometheus/Grafana (Observability)**

## Architecture

```
Developer
   │ git push
   ▼
GitHub (app repo)
   │ webhook
   ▼
Jenkins CI
   ├─ Trivy fs scan (deps, secrets, IaC misconfig)
   ├─ SAST (SonarQube/Semgrep slot)
   ├─ docker build
   ├─ Trivy image scan  ──► FAILS BUILD on HIGH/CRITICAL
   ├─ push image → ECR (scan-on-push as 2nd layer)
   └─ bump image tag in tetris-k8s-manifests repo (GitOps commit)
                │
                ▼
        GitHub (manifests repo)
                │ watched by
                ▼
           ArgoCD (auto-sync + self-heal)
                │
                ▼
         EKS Cluster (namespace: tetris)
                ├─ Deployment (non-root, read-only rootfs, no capabilities)
                ├─ HPA (3-10 pods)
                ├─ NetworkPolicy (default-deny + explicit allow)
                ├─ Ingress (ALB)
                └─ nginx-exporter sidecar ──► Prometheus ──► Grafana dashboard
```

## Repo Layout

```
tetris-devsecops/
├── app/                    # Tetris game (HTML5 canvas, no framework deps)
├── Dockerfile              # Multi-stage, non-root, nginx-unprivileged base
├── Jenkinsfile              # CI pipeline
├── k8s/
│   ├── base/               # Deployment, Service, Ingress, HPA, NetworkPolicy
│   └── argocd/              # ArgoCD Application (points at manifests repo)
├── terraform/               # VPC + EKS + ECR via IaC
├── monitoring/               # Prometheus/Grafana Helm values + dashboard
└── security/                 # Trivy script + Gatekeeper policy
```

> In real GitOps you'd split this into two repos: an **app repo** (this one)
> and a **manifests repo** that ArgoCD watches. Jenkins commits to the manifests
> repo; it never runs `kubectl apply` itself. That separation is what makes it GitOps.

## Setup — Step by Step

### 1. Provision EKS
```bash
cd terraform
terraform init
terraform plan
terraform apply
aws eks update-kubeconfig --region ap-south-1 --name tetris-devsecops
```

### 2. Install cluster add-ons
```bash
# AWS Load Balancer Controller (for the Ingress)
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=tetris-devsecops

# Prometheus + Grafana
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prom-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f monitoring/prometheus-values.yaml

# ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 3. Bootstrap ArgoCD
```bash
kubectl apply -f k8s/argocd/application.yaml
# ArgoCD will create the `tetris` namespace and sync everything in k8s/base/
```

### 4. Point Jenkins at this repo
- Install plugins: Docker Pipeline, AWS Credentials, SSH Agent, Trivy (or just call the CLI).
- Add credentials: `github-deploy-key` (SSH key with push to manifests repo),
  AWS credentials with ECR push permission.
- Create a Multibranch/Pipeline job pointing at this repo's `Jenkinsfile`.

### 5. Push a change and watch it flow
```
git push  →  Jenkins builds + scans  →  ECR  →  manifests repo bump  →  ArgoCD syncs  →  live on EKS
```

## Security Controls (the "Sec" in DevSecOps)

| Layer | Tool | What it catches |
|---|---|---|
| Dependencies/secrets | Trivy `fs` scan | Leaked secrets, vulnerable packages, IaC misconfig |
| Container image | Trivy `image` scan | CVEs in base image + layers, **fails the build** on HIGH/CRITICAL |
| Registry | ECR scan-on-push | Second independent scan pass |
| Runtime pod | securityContext | Non-root, read-only rootfs, no Linux capabilities, no priv-escalation |
| Network | NetworkPolicy | Default-deny; only explicit allowed traffic |
| Cluster-wide | Gatekeeper (optional) | Blocks privileged/root pods even if someone bypasses CI |

Run the same scans locally before pushing:
```bash
chmod +x security/trivy-scan.sh
./security/trivy-scan.sh tetris-app:local
```

## Observability

- `nginx-prometheus-exporter` sidecar exposes `:9113/metrics` on every pod.
- `ServiceMonitor` (monitoring/servicemonitor.yaml) tells Prometheus Operator to scrape it.
- Import `monitoring/tetris-dashboard.json` into Grafana for requests/sec, CPU, memory, pod count.
- Access Grafana: `kubectl port-forward svc/kube-prom-stack-grafana -n monitoring 3000:80`

## Before you go to production

- Move Terraform state to S3 + DynamoDB lock (commented block in `terraform/main.tf`).
- Replace the placeholder ECR repo URL / account ID in the Dockerfile references and manifests.
- Point the Ingress host at a real domain + ACM cert.
- Split app repo and manifests repo (this project keeps them together for simplicity).
- Wire Alertmanager to Slack/PagerDuty for the alerts kube-prometheus-stack ships with.
