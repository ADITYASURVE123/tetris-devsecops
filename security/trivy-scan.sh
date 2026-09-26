#!/usr/bin/env bash
# Run the same three Trivy scans locally that Jenkins runs in CI.
set -euo pipefail

IMAGE="${1:-tetris-app:local}"

echo "== 1/3 Filesystem scan (deps + secrets + misconfig) =="
trivy fs --scanners vuln,secret,misconfig --severity HIGH,CRITICAL .

echo "== 2/3 IaC scan (Terraform + Kubernetes manifests) =="
trivy config --severity HIGH,CRITICAL terraform/ k8s/

echo "== 3/3 Image scan =="
if docker image inspect "$IMAGE" > /dev/null 2>&1; then
  trivy image --severity HIGH,CRITICAL "$IMAGE"
else
  echo "Image $IMAGE not found locally - build it first: docker build -t $IMAGE ."
fi
