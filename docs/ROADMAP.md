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
- [x] Instrumentação: `/metrics` e logs JSON de requisição
- [ ] OpenTelemetry (evolução futura, fora do escopo atual)

## Fase 3: CI/CD e GitOps
- [x] Chart Helm evoluído (ServiceAccount, Ingress, HPA, PDB, securityContext, ServiceMonitor opcionais)
- [x] CI: pytest, `terraform fmt/validate`, validação Helm/scripts e `trivy config` antes da publicação; imagens com tag por SHA
- [x] CI: PR de release com SHA; deploy permanece manual
- [x] ECR com tags imutáveis por SHA (sem `latest`)
- [ ] ArgoCD com app-of-apps (`gitops/`)

## Fase 4: segurança de runtime
- [ ] External Secrets Operator + AWS Secrets Manager
- [ ] cert-manager + Linkerd (mTLS entre serviços)

## Fase 5: observabilidade
- [x] Prometheus + Grafana (kube-prometheus-stack), dashboards, métricas e alertas versionados
- [ ] Loki + Grafana Alloy (evolução futura; logs atuais via kubectl)
- [ ] OpenTelemetry Collector + Jaeger (evolução futura)

## Fase 6: polimento
- [x] README final com diagrama da arquitetura completa
- [x] `Makefile` com `up`/`down` e referência de custos
- [x] AWS Budgets mensais de US$50 e US$100 com alertas (já configurados)
- [ ] Recriar EKS temporariamente, validar deploy e smoke test; guardar evidências (opcional, gera custos e requer autorização do mantenedor)

## Estado de encerramento (26/11/2026)

- Observabilidade Prometheus/Grafana implementada em Helm, documentada e coberta por validação offline das regras de alerta na CI.
- A instalação no EKS foi tentada, mas a validação ponta a ponta não foi concluída: o Alertmanager apresentou erro de receiver. A configuração customizada foi removida para usar a configuração padrão do chart; o resultado precisa ser confirmado ao recriar o cluster.
- O mantenedor removeu manualmente o EKS e os demais recursos AWS para interromper custos. Não recriar infraestrutura sem combinar previamente.
- As evidências de persistência, isolamento IRSA, Ingress e escala Karpenter de 24/11/2026 foram reportadas pelo mantenedor. Os testes pós-observabilidade ainda precisam rodar em cluster para validar a integração real.
- Para evitar manter recursos faturáveis, o projeto pode ser encerrado com as validações locais e CI atuais; a validação EKS fica documentada como pendente/opcional.
