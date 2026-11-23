# Laboratório de e-commerce em EKS

## Arquitetura implementada

- Cada pasta em `services/` contém uma API FastAPI, suas dependências e seu Dockerfile. No Compose, `products` atende na porta 8000, `orders` na 8001, `users` na 8002 e `payments` na 8003. Todas expõem `/health`.
- Ao criar um pedido, `orders` consulta usuário e produto por HTTP, reserva estoque e solicita um pagamento simulado. A aprovação consome a reserva e a recusa devolve a quantidade. No Compose, os quatro serviços usam tabelas separadas no DynamoDB Local com um volume nomeado. Repetir POST /orders com o mesmo corpo e Idempotency-Key retoma a compra. O chart ainda usa o modo em memória. Mantenha uma réplica por serviço até implementar persistência compartilhada entre réplicas.
- `infra/terraform/` define VPC em duas AZs, subnets privadas /20, um NAT Gateway, EKS 1.35 e node group `system` com dois t3.large AL2023 por padrão. Os addons são VPC CNI, kube-proxy, CoreDNS e EBS CSI. O último usa o módulo local `modules/irsa`. As tags de descoberta já existem para a futura instalação do Karpenter.
- Cada serviço tem um repositório ECR. A CI em `.github/workflows/ci.yml` constrói as quatro imagens, executa Trivy e publica SHA completo e `latest` via OIDC nos eventos de publicação. A role AWS aceita a branch main do repositório configurado. A variável do GitHub Actions é `AWS_ROLE_ARN`.
- `helm/microservice/` contém o chart compartilhado. Cada release usa seu arquivo em `helm/values/` e cria Deployment e Service ClusterIP na porta 80. Os nomes das releases são os nomes DNS usados por orders. Há probes HTTP e requests/limits.

## Comandos a partir da raiz

### Desenvolvimento local

```bash
docker compose up --build -d
# Assim que os serviços responderem em /health
bash scripts/test-order.sh
docker compose down
```

O script usa curl e Python 3 para criar usuário, produto e pedido. Tanto aprovação quanto recusa simulada são resultados válidos.

### Terraform e publicação na AWS

Use Terraform 1.10 ou superior, AWS CLI autenticada e o bucket S3 do ambiente já criado. Na primeira configuração, copie `infra/terraform/backend.hcl.example` para `infra/terraform/backend.hcl` e preencha o bucket. O backend usa criptografia e lockfile. Confira os IDs do GitHub, a opção de reutilizar o provedor OIDC e os CIDRs permitidos para a API do EKS nas variáveis.

```bash
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform init -backend-config=backend.hcl
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform plan
terraform -chdir=infra/terraform apply
terraform -chdir=infra/terraform output -raw configure_kubectl
```

Execute o comando AWS CLI mostrado pelo último output para configurar kubectl. O apply cria recursos faturáveis. Para publicar manualmente, use `bash scripts/build-and-push.sh` com os repositórios ECR já criados. O script descobre a conta via STS e publica SHA curto e latest. Ajuste AWS_REGION e PROJECT_NAME se alterou os padrões.

### Helm e smoke test no cluster

Com o kubeconfig apontando para o laboratório e as imagens publicadas, use as URLs do output Terraform para instalar na conta em uso.

```bash
for s in products users payments orders; do
  repo=$(terraform -chdir=infra/terraform output -json ecr_repository_urls | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$s")
  helm upgrade --install "$s" ./helm/microservice -f "helm/values/$s.yaml" --set-string "image.repository=$repo" --wait || break
done
kubectl get nodes
kubectl get pods,svc
```

Abra um terminal por encaminhamento e rode o script em outro terminal.

```bash
kubectl port-forward svc/products 8000:80
kubectl port-forward svc/orders 8001:80
kubectl port-forward svc/users 8002:80
```

Use `bash scripts/test-order.sh`. Para encerrar, consulte as opções de desmontagem no README. O fluxo completo inclui `helm uninstall products users payments orders`, esvaziamento dos ECRs que serão excluídos e `terraform -chdir=infra/terraform destroy`. O bucket de state tem ciclo de vida separado.

## Continuidade

A Fase 0 teve apply, validação e destroy relatados pelo mantenedor. Consulte `docs/ROADMAP.md` para o trabalho pendente. A próxima fase instala Karpenter e AWS Load Balancer Controller com IRSA, adiciona Ingress para orders e contempla limpeza dos recursos dos controllers antes do destroy. A decisão de persistência é DynamoDB com uma tabela e uma role IRSA de menor privilégio por serviço. GitOps, segurança de runtime, observabilidade e Makefile são entregas futuras.
