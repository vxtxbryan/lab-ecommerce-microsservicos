# Roadmap

Plataforma de microsserviços em EKS com GitOps e observabilidade. Marque as caixas conforme cada fase for concluída.

## Fase 0: correções de base
- [x] Kubernetes 1.35 (suporte padrão) e addons gerenciados (`vpc-cni`, `kube-proxy`, `coredns`, `aws-ebs-csi-driver`)
- [x] Nodes em subnets privadas /20 + 1 NAT Gateway
- [x] Node group de sistema `t3.large`
- [x] Módulo local de IRSA (`infra/terraform/modules/irsa`) e IRSA do EBS CSI
- [x] Bucket do state, repositório/IDs do GitHub e conta AWS parametrizados
- [x] Tags de descoberta do Karpenter (subnets e security group)

## Fase 1: plataforma de infraestrutura
- [x] Karpenter (NodePool + EC2NodeClass) com IRSA, taint no grupo de sistema e teste real de provisionamento e consolidação de um node On-Demand
- [x] AWS Load Balancer Controller com IRSA
- [x] Ingress interno para a API (`orders`), testado pelo DNS do ALB

## Fase 2: serviços
- [x] DynamoDB, uma tabela por serviço (database per service), com IRSA de menor privilégio por serviço
- [x] Correções no `orders` (status HTTP dos outros serviços, estoque)
- [x] Testes automatizados (pytest)
- [x] Dockerfiles não-root + `.dockerignore`
- [ ] Instrumentação: `/metrics`, logs JSON e OpenTelemetry

## Fase 3: CI/CD e GitOps
- [ ] Chart Helm evoluído (ServiceAccount, Ingress, HPA, PDB, securityContext, ServiceMonitor)
- [x] CI: pytest, `terraform fmt/validate`, validação Helm/scripts e `trivy config` antes da publicação; imagens com tag por SHA
- [ ] CI: atualização da tag de deploy no Git
- [x] ECR com tags imutáveis por SHA (sem `latest`)
- [ ] ArgoCD com app-of-apps (`gitops/`)

## Fase 4: segurança de runtime
- [ ] External Secrets Operator + AWS Secrets Manager
- [ ] cert-manager + Linkerd (mTLS entre serviços)

## Fase 5: observabilidade
- [ ] Prometheus + Grafana (kube-prometheus-stack) e dashboards
- [ ] Loki + Grafana Alloy (logs)
- [ ] OpenTelemetry Collector + Jaeger (tracing distribuído)

## Fase 6: polimento
- [ ] README final com diagrama da arquitetura completa
- [ ] `Makefile` com `up`/`down` e custos atualizados
- [ ] AWS Budgets e prints das evidências
