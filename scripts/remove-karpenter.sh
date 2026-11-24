#!/usr/bin/env bash
# Remova primeiro os workloads que usam este pool.
set -euo pipefail
cd "$(dirname "$0")/.."
endpoint=$(terraform -chdir=infra/terraform output -raw cluster_endpoint)
if [[ "$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')" != "$endpoint" ]]; then
  echo "Aponte o kubeconfig para o cluster Terraform antes de remover." >&2
  exit 1
fi
helm uninstall karpenter-capacity -n kube-system --ignore-not-found --wait --timeout 10m
for kind in nodepools.karpenter.sh nodeclaims.karpenter.sh ec2nodeclasses.karpenter.k8s.aws; do
  crd=$(kubectl get crd "$kind" --ignore-not-found -o name)
  if [[ -n "$crd" ]]; then
    remaining=$(kubectl get "$kind" -o name)
    if [[ -n "$remaining" ]]; then
      echo "Ainda existem recursos $kind; o controller e os CRDs continuam instalados." >&2
      exit 1
    fi
  fi
done
helm uninstall karpenter -n kube-system --ignore-not-found --wait
helm uninstall karpenter-crd -n kube-system --ignore-not-found --wait
