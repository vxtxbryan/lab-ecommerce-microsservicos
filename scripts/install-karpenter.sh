#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=1.15.3
settings=$(terraform -chdir=infra/terraform output -json karpenter_settings)
field() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1" <<< "$settings"; }
cluster=$(field cluster)
endpoint=$(terraform -chdir=infra/terraform output -raw cluster_endpoint)
if [[ "$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')" != "$endpoint" ]]; then
  echo "Aponte o kubeconfig para o cluster Terraform antes de instalar." >&2
  exit 1
fi
registry=oci://public.ecr.aws/karpenter
helm upgrade --install karpenter-crd "$registry/karpenter-crd" --version "$version" -n kube-system --wait
kubectl wait --for=condition=Established --timeout=2m \
  crd/nodepools.karpenter.sh crd/nodeclaims.karpenter.sh crd/ec2nodeclasses.karpenter.k8s.aws
kubectl api-resources --cached=false >/dev/null
helm upgrade --install karpenter "$registry/karpenter" --version "$version" -n kube-system --skip-crds \
  --set-string settings.clusterName="$cluster" \
  --set-string 'serviceAccount.annotations.eks\.amazonaws\.com/role-arn'="$(field controller_role)" \
  --set-string nodeSelector.workload=system --wait
helm upgrade --install karpenter-capacity helm/karpenter-capacity -n kube-system \
  --set-string cluster="$cluster" --set-string instanceProfile="$(field profile)"
kubectl wait --for=condition=Ready ec2nodeclass/workloads nodepool/workloads --timeout=5m
