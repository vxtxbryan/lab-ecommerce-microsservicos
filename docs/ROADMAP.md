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
- [x] AWS Budgets mensais de US$20, US$50 e US$100 com alertas (já configurados)
- [x] Recriar EKS temporariamente, validar deploy e smoke tests, registrar resultados e destruir a infraestrutura (27/11/2026)

## Estado de encerramento (27/11/2026)

- EKS 1.35.9 recriado com dois nodes `t3.large`, um NAT, ECR, quatro tabelas DynamoDB, Karpenter e AWS Load Balancer Controller; a API do cluster foi restrita ao IP do operador durante a validação.
- Checkout real aprovado; após reiniciar os quatro Deployments, usuário, estoque, pedido e pagamento persistiram. Replay idempotente repetiu o mesmo resultado, a mesma chave com outro corpo retornou HTTP 409, e IRSA de `payments` leu sua tabela e recebeu `AccessDeniedException` na tabela `users`.
- Karpenter provisionou um `t3.medium` para os serviços e um `t3.large` para o pod de teste; após excluir o pod temporário, consolidou o node vazio. O pod de teste foi removido.
- Ingress interno do ALB validou pedido, replay idempotente e HTTP 404 para `/users`.
- Prometheus: quatro targets `UP`, métricas das quatro APIs e quatro alertas carregados. Grafana respondeu saudável e o dashboard tinha dez painéis. O alerta de Deployment indisponível disparou quando `payments` foi escalado a zero e resolveu após a recuperação.
- O primeiro install de `kube-prometheus-stack` precisou das CRDs aplicadas e estabelecidas antes do release. `scripts/install-monitoring.sh` agora automatiza essa ordem. A configuração padrão do Alertmanager ficou saudável, sem erro de receiver.
- Regras de alerta também passaram em `promtool` na CI. A CI validou Terraform, Helm, scripts, Trivy, build de imagens e testes do checkout sem publicar para AWS por padrão.
- Após os testes, o EKS, VPC/NAT, ALB, nodes, tabelas e ECRs temporários foram removidos. A verificação final encontrou zero state Terraform e zero recursos temporários; permanecem os três budgets e o bucket S3 usado pelo backend remoto.
- Os três budgets têm notificações ACTUAL em 85% e 100%, além de FORECASTED em 100%. Os limites são US$20, US$50 e US$100.
- GitOps/ArgoCD, External Secrets, mTLS, logs centralizados e tracing continuam sendo evoluções opcionais, não bloqueios para a entrega atual.
