#!/usr/bin/env bash
# Execute antes de remover o release orders, o controller ou a VPC.
set -euo pipefail
cd "$(dirname "$0")/.."
tf=(terraform -chdir=infra/terraform)
endpoint=$("${tf[@]}" output -raw cluster_endpoint)
if [[ "$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')" != "$endpoint" ]]; then
  echo "Selecione o cluster deste state no kubeconfig." >&2
  exit 1
fi
settings=$("${tf[@]}" output -json load_balancer_settings)
region=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["region"])' <<< "$settings")
vpc=$("${tf[@]}" output -raw vpc_id)
dns=$(kubectl get ingress orders -n default --ignore-not-found -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
arn=""
if [[ -n "$dns" ]]; then
  lbs=$(aws elbv2 describe-load-balancers --region "$region" --output json)
  arn=$(python3 -c 'import json,sys; print(next((lb["LoadBalancerArn"] for lb in json.load(sys.stdin)["LoadBalancers"] if lb["DNSName"] == sys.argv[1] and lb["VpcId"] == sys.argv[2]), ""))' "$dns" "$vpc" <<< "$lbs")
fi
kubectl delete ingress orders -n default --ignore-not-found --wait --timeout=10m
if [[ -n "$arn" ]]; then
  aws elbv2 wait load-balancers-deleted --region "$region" --load-balancer-arns "$arn"
fi
remaining=$(kubectl get ingress -A -o json | python3 -c 'import json,sys; print("alb" if any(i["spec"].get("ingressClassName")=="alb" for i in json.load(sys.stdin)["items"]) else "")')
if [[ -n "$remaining" ]]; then
  echo "Ainda existem Ingresses alb; mantendo o controller." >&2
  exit 1
fi
helm uninstall aws-load-balancer-controller -n kube-system --ignore-not-found --wait
