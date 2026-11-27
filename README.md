# Laboratório de E-commerce com Microsserviços no Amazon EKS

[![CI](https://github.com/vxtxbryan/lab-ecommerce-microsservicos/actions/workflows/ci.yml/badge.svg)](https://github.com/vxtxbryan/lab-ecommerce-microsservicos/actions/workflows/ci.yml)

Laboratório prático de **cloud e DevOps**: quatro microsserviços de e-commerce (Python/FastAPI) em um cluster **Amazon EKS**, com infraestrutura criada por **Terraform**, entrega GitOps com **Argo CD e Helm** e uma pipeline de **CI no GitHub Actions** que compila as imagens, verifica vulnerabilidades com **Trivy** e, quando habilitada, publica no **Amazon ECR** usando **OIDC** (sem chaves de acesso armazenadas no GitHub).

O objetivo é servir como material de estudo e como referência de um fluxo completo, do código até o cluster. Se você quer aprender como as peças se encaixam, ou precisa de um ponto de partida para um projeto parecido, pode clonar, rodar e adaptar.

> **Aviso de custo:** subir o cluster na AWS **gera cobrança** (a infraestrutura base custa cerca de **US$ 0,33 por hora**, além de ALB, tráfego e capacidade do Karpenter). O passo a passo abaixo mostra como rodar tudo localmente sem custos AWS e como destruir a infraestrutura na nuvem ao terminar. Veja a seção [Custos](#custos).

---

## Sumário

- [O que este projeto demonstra](#o-que-este-projeto-demonstra)
- [Tecnologias](#tecnologias)
- [Arquitetura](#arquitetura)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Os serviços](#os-serviços)
- [Pré-requisitos](#pré-requisitos)
- [Passo a passo](#passo-a-passo)
  - [1. Rodar localmente com Docker Compose (sem custo)](#1-rodar-localmente-com-docker-compose-sem-custo)
  - [2. Preparar a conta AWS](#2-preparar-a-conta-aws)
  - [3. Criar a infraestrutura com Terraform](#3-criar-a-infraestrutura-com-terraform)
  - [4. Enviar as imagens para o ECR](#4-enviar-as-imagens-para-o-ecr)
  - [5. Conectar o kubectl ao cluster](#5-conectar-o-kubectl-ao-cluster)
  - [6. Instalar os serviços com Argo CD](#6-instalar-os-serviços-com-argo-cd)
  - [7. Testar o fluxo de um pedido](#7-testar-o-fluxo-de-um-pedido)
  - [8. Desligar tudo para parar a cobrança](#8-desligar-tudo-para-parar-a-cobrança)
- [Pipeline de CI](#pipeline-de-ci)
- [Evidências do deploy](#evidências-do-deploy)
- [Decisões de projeto e limitações](#decisões-de-projeto-e-limitações)
- [Custos](#custos)
- [Problemas comuns](#problemas-comuns)
- [Próximos passos](#próximos-passos)
- [Licença](#licença)

---

## O que este projeto demonstra

- **Infraestrutura como código** com Terraform: VPC, subnets, cluster EKS, node group, repositórios ECR e a role de acesso do GitHub Actions, com o state guardado em um bucket S3.
- **Kubernetes na prática**: Deployments, Services, probes de liveness e readiness, limites de recursos e comunicação entre serviços por DNS interno.
- **Helm**: um chart genérico (`helm/microservice`) compartilhado pelos quatro serviços, com um arquivo de valores para cada um.
- **CI com segurança embutida**: build, varredura Trivy que reprova a pipeline em vulnerabilidades `HIGH` e `CRITICAL`, e push para o ECR.
- **Autenticação sem segredos**: o GitHub Actions assume uma role da AWS por OIDC, restrita à branch `main` deste repositório.
- **Microsserviços**: quatro APIs independentes, onde o serviço `orders` orquestra chamadas HTTP aos outros três.

## Tecnologias

| Área | Ferramenta | Observação |
|---|---|---|
| Nuvem | AWS | Região `us-east-1` |
| Orquestração | Amazon EKS (Kubernetes 1.35) | Node group de sistema: 2 nodes `t3.large` em subnets privadas |
| IaC | Terraform ≥ 1.10 | Provider AWS `~> 5.0`; módulos `terraform-aws-modules/vpc` e `eks`, mais um módulo local de IRSA (`modules/irsa`) |
| Deploy | Argo CD + Helm 3 | GitOps app-of-apps; chart compartilhado e values por serviço |
| Registro de imagens | Amazon ECR | 1 repositório por serviço, scan no push |
| CI | GitHub Actions | Build, Trivy, push, OIDC |
| Segurança | Trivy | Reprova em `HIGH` e `CRITICAL` com correção disponível |
| Aplicação | Python 3.12, FastAPI, Uvicorn, Pydantic | Imagem base `python:3.12-slim` |
| Local | Docker e Docker Compose | Para rodar sem custo |

## Arquitetura

A CI valida o código, publica imagens com SHA imutável e propõe a promoção dos quatro SHAs em um PR que altera `helm/values/*.yaml`. Após o merge, o Argo CD sincroniza os releases Helm automaticamente.

### Visão da infraestrutura

```mermaid
flowchart LR
    dev["Desenvolvedor<br/>git push"] --> gha["GitHub Actions<br/>build, Trivy, push"]
    dev --> repo["GitHub<br/>main e PR de promoção"]
    gha -->|"abre PR com os SHAs"| repo

    subgraph AWS["AWS - us-east-1"]
        ecr["Amazon ECR<br/>4 repositórios"]
        s3["Bucket S3<br/>state do Terraform"]
        cp["EKS control plane<br/>Kubernetes 1.35"]
        argocd["Argo CD<br/>app-of-apps + Helm"]
        subgraph VPC["VPC 10.0.0.0/16 - 2 zonas de disponibilidade"]
            subgraph PUB["Subnets públicas"]
                nat["NAT Gateway<br/>único, compartilhado"]
            end
            subgraph PRIV["Subnets privadas /20"]
                n1["Node t3.large<br/>zona A"]
                n2["Node t3.large<br/>zona B"]
            end
        end
    end

    gha -->|"OIDC: assume a role e envia as imagens"| ecr
    repo -.->|"reconcilia main"| argocd
    argocd -->|"reconcilia recursos pela API"| cp
    ecr -.->|"pull das imagens"| n1
    ecr -.->|"pull das imagens"| n2
    cp --- n1
    cp --- n2
    n1 -.->|"saída para a internet"| nat
    n2 -.->|"saída para a internet"| nat
```

### Como os serviços conversam

Os quatro serviços rodam no namespace `default` e se encontram pelo **DNS interno do Kubernetes**: o Service `users` responde em `http://users`, e assim por diante. O serviço `orders` é o único que chama os outros.

```mermaid
flowchart LR
    client["Cliente<br/>curl via port-forward"] -->|"POST /orders"| orders

    subgraph K8S["Cluster EKS - namespace default"]
        orders["orders<br/>Service :80 para Pod :8001"]
        users["users<br/>Service :80 para Pod :8002"]
        products["products<br/>Service :80 para Pod :8000"]
        payments["payments<br/>Service :80 para Pod :8003"]
        orders -->|"1. valida o usuário"| users
        orders -->|"2. reserva estoque"| products
        orders -->|"3. processa o pagamento"| payments
    end
```

### Fluxo de um pedido

```mermaid
sequenceDiagram
    participant C as Cliente
    participant O as orders
    participant U as users
    participant P as products
    participant PG as payments

    C->>O: POST /orders
    O->>U: GET /users/:id
    U-->>O: 200 ou 404
    O->>P: PUT /products/:id/reservations/:order_id
    P-->>O: Reserva criada ou recuperada
    Note over O: Calcula o total
    O->>PG: POST /payments
    PG-->>O: approved ou declined
    O->>P: DELETE /products/:id/reservations/:order_id
    Note over P: Devolve estoque em caso de recusa
    O-->>C: 201 com status confirmed ou payment_declined
```

Se algum serviço estiver fora do ar, o `orders` responde `503`. Usuário ou produto inexistente retorna `404`, e estoque insuficiente retorna `400`.

## Estrutura do repositório

```text
.
├── .github/workflows/ci.yml     # Pipeline: build, Trivy e push para o ECR
├── gitops/                      # Argo CD: bootstrap, projeto e Applications
├── docker-compose.yml           # Sobe os 4 serviços localmente
├── helm/
│   ├── microservice/            # Chart genérico (Deployment + Service)
│   │   ├── Chart.yaml
│   │   ├── values.yaml          # Valores padrão (réplicas, probes, recursos)
│   │   └── templates/
│   └── values/                  # Um arquivo de valores por serviço
│       ├── products.yaml
│       ├── users.yaml
│       ├── payments.yaml
│       └── orders.yaml
├── infra/terraform/
│   ├── backend.tf               # State remoto no S3 (bucket informado no init)
│   ├── backend.hcl.example      # Modelo do arquivo com o nome do seu bucket
│   ├── provider.tf              # Versões, provider AWS e default_tags
│   ├── variables.tf             # Região, versão do K8s, nodes, GitHub
│   ├── vpc.tf                   # VPC, subnets públicas/privadas e NAT
│   ├── eks.tf                   # Cluster EKS, addons e node group de sistema
│   ├── addons.tf                # Addon EBS CSI (com IRSA)
│   ├── modules/irsa/            # Módulo reutilizável: role IAM por service account
│   ├── ecr.tf                   # Repositórios ECR e política de retenção
│   ├── oidc.tf                  # Role que o GitHub Actions assume (OIDC)
│   └── outputs.tf
├── scripts/
│   ├── install-argocd.sh        # Instala Argo CD e inicia o app-of-apps
│   ├── deploy-services.sh       # Deploy Helm manual (alternativa ao GitOps)
│   ├── build-and-push.sh        # Build e publicação manual no ECR
│   ├── test-order.sh            # Teste ponta a ponta de um pedido
│   └── validate-gitops.sh       # Valida a configuração declarativa do Argo CD
├── services/
│   ├── products/                # API de produtos  (porta 8000)
│   ├── orders/                  # API de pedidos   (porta 8001)
│   ├── users/                   # API de usuários  (porta 8002)
│   └── payments/                # API de pagamentos (porta 8003)
└── docs/img/                    # Prints usados neste README
```

## Os serviços

Cada serviço usa sua própria tabela no DynamoDB Local via Compose. No EKS, o deploy do passo 6 configura uma tabela DynamoDB e uma role IRSA por serviço. Todos expõem `GET /health`, usado nas probes do Kubernetes, e a documentação interativa do FastAPI fica em `/docs`.

| Serviço | Porta | Rotas | Observações |
|---|---|---|---|
| `products` | 8000 | `GET /products`, `GET /products/{id}`, `POST /products`, `DELETE /products/{id}` | Corpo do `POST`: `name`, `price`, `stock` |
| `orders` | 8001 | `GET /orders`, `POST /orders` | Orquestra `users`, `products` e `payments` |
| `users` | 8002 | `GET /users`, `GET /users/{id}`, `POST /users`, `POST /users/login` | Senha armazenada como hash bcrypt; e-mail único |
| `payments` | 8003 | `GET /payments/{id}`, `POST /payments` | Simulação: **aprova 90%** e **recusa 10%** dos pagamentos |

Exemplo de corpo do `POST /orders`:

```json
{
  "user_id": "<id do usuário>",
  "product_id": "<id do produto>",
  "quantity": 2,
  "payment_method": "pix"
}
```

Formas de pagamento aceitas: `credit_card`, `pix` e `boleto`.

## Pré-requisitos

| Ferramenta | Para quê | Versão |
|---|---|---|
| Git | Clonar o repositório | qualquer recente |
| Docker (e Docker Compose) | Rodar localmente e buildar imagens | recente |
| Python | Testes, scripts auxiliares e validação local | 3.12 |
| PyYAML | Scripts de deploy e validação do GitOps | 6.0.3 |
| Conta AWS | Criar a infraestrutura | com permissão administrativa para o laboratório |
| AWS CLI v2 | Falar com a AWS | 2.x |
| Terraform | Criar a infraestrutura | **1.10 ou superior** (o backend usa `use_lockfile`) |
| kubectl | Operar o cluster | compatível com o Kubernetes 1.35 |
| Helm | Instalar os serviços | 3.x |

> **No Windows:** use o **WSL 2** (Ubuntu) e rode todos os comandos de dentro dele. No Docker Desktop, ative a integração com a distribuição WSL em *Settings → Resources → WSL integration*. Este projeto foi desenvolvido assim.

Para a parte local (passo 1) você só precisa de Git e Docker.

## Passo a passo

Atalhos: `make up` inicia o Compose; `make down` encerra sem apagar dados; `make test` executa pytest; `make validate` verifica Helm, Terraform, scripts e Compose; `make clean` remove também o volume local do DynamoDB; `make deploy` faz o deploy Helm manual e requer kubeconfig. Para GitOps, use `make gitops`.

```bash
git clone https://github.com/vxtxbryan/lab-ecommerce-microsservicos.git
cd lab-ecommerce-microsservicos
```

### 1. Rodar localmente com Docker Compose (sem custo)

O Compose inicializa as tabelas de usuários, produtos, pedidos e pagamentos no DynamoDB Local. O volume nomeado preserva os cadastros, o catálogo, o estoque, os pedidos e os pagamentos após `docker compose down`.

```bash
docker compose up --build
```

Os serviços sobem em `localhost`: products `8000`, orders `8001`, users `8002` e payments `8003`. Em **outro terminal**, rode o teste de ponta a ponta:

```bash
./scripts/test-order.sh
```

Ele cria um usuário e um produto, faz um pedido e mostra a resposta. Se aparecer `"status": "confirmed"`, o fluxo completo funcionou. Um `"status": "payment_declined"` também é um resultado válido: é a recusa simulada de 10% do serviço `payments`. Se o script não tiver permissão de execução, rode `chmod +x scripts/*.sh`.

Para verificar o cadastro concorrente, a disputa pela última unidade e a recuperação de um pagamento, com o Compose em execução e em um ambiente Python com as dependências de `services/orders/requirements.txt`, `common/requirements.txt` e pytest, execute:

```bash
ORDERS_TEST_URL=http://localhost:8001 USERS_TEST_URL=http://localhost:8002 STOCK_TEST_URL=http://localhost:8000 PAYMENT_TEST_URL=http://localhost:8003 python -m pytest -q tests
```

A suíte cobre cadastro concorrente, estoque e recuperação de pagamento. O teste de disputa de estoque simula usuário e pagamento para controlar a aprovação e a recusa.

Se o pagamento ficar sem resposta conclusiva, a reserva permanece pendente. Para retomar o pedido, repita o mesmo corpo em `POST /orders` com o mesmo cabeçalho `Idempotency-Key` enviado na primeira tentativa. Use uma chave diferente por compra. Reutilizar a chave com outro corpo retorna HTTP 409. Clientes que omitem o cabeçalho criam um novo pedido a cada envio. A retomada depende da repetição pelo cliente.

Para encerrar, use `Ctrl+C` e depois `docker compose down`.

### 2. Preparar a conta AWS

**2.1 Configure as credenciais e confirme a conta:**

```bash
aws configure
aws sts get-caller-identity
```

**2.2 Crie o bucket S3 do state do Terraform.** Nomes de bucket são únicos no mundo todo, então o bucket do autor não serve para você. Crie o seu:

```bash
export TF_BUCKET="meu-tfstate-lab-ecommerce-$RANDOM$RANDOM"

aws s3api create-bucket --bucket "$TF_BUCKET" --region us-east-1
aws s3api put-bucket-versioning --bucket "$TF_BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$TF_BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$TF_BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

E informe o bucket ao Terraform. O nome **não fica no código**: ele vai em um arquivo local, ignorado pelo Git:

```bash
echo "bucket = \"$TF_BUCKET\"" > infra/terraform/backend.hcl
```

> Se preferir só experimentar sem bucket, apague o arquivo `infra/terraform/backend.tf` (e pule o `-backend-config` do passo 3). O state passará a ficar em um arquivo local (`terraform.tfstate`). Isso serve para estudo, mas não para trabalho em equipe. **Nunca faça commit de arquivos de state**: o `.gitignore` já os ignora.

**2.3 Troque o ID de conta AWS do autor pelo seu nos values do Helm.** O script de push já descobre a conta sozinho (`aws sts get-caller-identity`); o ID `271251458777` só permanece em `helm/values/*.yaml`:

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/271251458777/$AWS_ACCOUNT_ID/g" helm/values/*.yaml
```

**2.4 Restrinja o endpoint público do EKS ao seu IP.** O valor padrão do laboratório permite qualquer origem; limite-o antes de aplicar:

```bash
MY_IP=$(curl -s https://checkip.amazonaws.com)
echo "cluster_endpoint_public_access_cidrs = [\"${MY_IP}/32\"]" >> infra/terraform/terraform.tfvars
```

**2.5 Decida se vai usar a CI do GitHub Actions.** O arquivo `infra/terraform/oidc.tf` cria a role usada pela pipeline e vem configurado para o repositório do autor.

- **Não vai usar a CI:** remova o arquivo antes do `terraform apply`:

  ```bash
  rm infra/terraform/oidc.tf
  ```

- **Vai usar a CI (no seu fork):** veja a seção [Pipeline de CI](#pipeline-de-ci), que explica o que ajustar. Se a sua conta **já tiver** um provedor OIDC do GitHub (`aws iam list-open-id-connect-providers`), use `-var create_github_oidc_provider=false` no `plan`/`apply` para reaproveitá-lo.

### 3. Criar a infraestrutura com Terraform

> **Daqui em diante há cobrança.** Reserve cerca de 1h30 para executar até o passo 8 de uma vez.

Os arquivos `.tf` ficam em `infra/terraform`. Rodar o `terraform` na raiz do repositório causa o erro `No configuration files`.

```bash
cd infra/terraform
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Leia o plano e confirme com `yes`. A criação leva de **15 a 20 minutos**, e a maior parte é a espera do cluster EKS e do node group. Se a conexão cair, rode `terraform apply` de novo, que ele continua de onde parou. Ao final, volte para a raiz com `cd ../..`.

O que é criado: uma VPC com quatro subnets e um NAT Gateway, o cluster EKS com os addons (`vpc-cni`, `kube-proxy`, `coredns` e `aws-ebs-csi-driver`), o node group de sistema, quatro tabelas DynamoDB com roles IRSA por serviço, quatro repositórios ECR e, se mantido `oidc.tf`, a role OIDC do GitHub Actions.

### 4. Enviar as imagens para o ECR

O Docker precisa estar rodando. Na raiz do repositório:

```bash
./scripts/build-and-push.sh
```

O script autentica no ECR, builda as quatro imagens e publica cada uma com a tag SHA completo do commit. Confira:

```bash
aws ecr describe-images --repository-name ecommerce-microsservicos-orders \
  --region us-east-1 --query 'imageDetails[].imageTags'
```

> Para o bootstrap GitOps, as quatro imagens precisam estar no ECR e cada `image.tag` em `helm/values/*.yaml` precisa conter um SHA completo. No envio manual, depois do script, promova a revisão que acabou de publicar:

```bash
IMAGE_TAG=$(git rev-parse HEAD)
for service in products orders users payments; do
  sed -i -E "s/^(  tag: ).*$/\\1\"${IMAGE_TAG}\"/" "helm/values/${service}.yaml"
done
```

Faça commit e push dessa promoção para `main`. Com publicação habilitada na [CI](#pipeline-de-ci), o workflow publica as imagens e abre um PR com os SHAs automaticamente. O bootstrap do Argo CD verifica as quatro tags antes de instalar para evitar releases sem imagem.

### 5. Conectar o kubectl ao cluster

```bash
aws eks update-kubeconfig --region us-east-1 --name ecommerce-microsservicos
kubectl get nodes
kubectl get pods -A
```

Esperado: **2 nodes `Ready`** e os pods de sistema (`aws-node`, `coredns`, `kube-proxy`) em `Running`.

### Autoscaling de nós

O grupo gerenciado `system` usa o taint `CriticalAddonsOnly=true:NoSchedule`. O controller Karpenter roda nesses nós, com IRSA. O pool `workloads` provisiona instâncias Linux amd64 On-Demand em subnets privadas, usando o perfil IAM criado pelo Terraform e as tags de descoberta da VPC. O chart fixa a versão da AMI AL2023. O limite configurado é de 8 vCPUs; a consolidação de nodes vazios começa após 30 segundos.

Para observar o ciclo em um cluster sem aplicações, instale o controller e a capacidade e crie o pod de teste:

```bash
bash scripts/install-karpenter.sh
kubectl apply -f tests/kubernetes/karpenter-scale.yaml
kubectl wait --for=condition=Ready pod/karpenter-scale-test --timeout=10m
kubectl get nodes -L workload,node.kubernetes.io/instance-type
kubectl get nodeclaims
kubectl delete pod karpenter-scale-test
kubectl get nodeclaims --watch
```

O pod exige o pool `workloads`. Quando ele é a única carga de aplicação, sua remoção deixa o node elegível para consolidação. Saia do watch com Ctrl+C após a exclusão do NodeClaim. O custo de EC2 e EBS do node dinâmico é adicional ao do node group de sistema.

**Validação na AWS em 24/11/2026.** Com dois nodes de sistema de Kubernetes 1.35.9, o pod de teste ficou `Unschedulable`. O Karpenter 1.15.3 criou um NodeClaim e um `t3.medium` em subnet privada, sem IP público. O pod ficou `Ready`. Após excluir o pod, o Karpenter consolidou o node vazio. Confirmamos a exclusão do NodeClaim, a instância EC2 em `terminated` e o retorno aos dois `t3.large` de sistema.

### 6. Instalar os serviços com Argo CD

Prepare a capacidade de aplicação e o Ingress antes de instalar os serviços. O bootstrap do Argo CD confere o endpoint do kubeconfig com o endpoint do Terraform, instala o chart oficial e cria a aplicação raiz, que acompanha a branch `main`:

```bash
bash scripts/install-karpenter.sh
bash scripts/install-alb-controller.sh
make gitops
kubectl get applications -n argocd
kubectl get pods -w
```

O app-of-apps cria um projeto restrito ao repositório e quatro Applications, uma por serviço. Cada aplicação usa o chart compartilhado em `helm/microservice`, mantém o nome do release igual ao nome do Service e carrega os valores correspondentes em `helm/values/*.yaml`. As aplicações sincronizam automaticamente no namespace `default`; alterações manuais nos recursos são corrigidas pelo Argo CD. A CI abre um PR com os SHAs completos das imagens publicadas. Revise e faça merge para aplicar a versão aprovada. Se a política do GitHub bloquear PRs automáticos, a execução informa o link para abri-lo.

Para acessar a interface, use um port-forward. A senha inicial é gerada pelo Argo CD; troque-a depois do primeiro login:

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

O script aguarda as quatro aplicações ficarem sincronizadas e saudáveis. Cada pod recebe o nome da própria tabela, a região e uma ServiceAccount associada à role correspondente. As tabelas usam cobrança por requisição. Um `terraform destroy` completo exclui as tabelas e os dados do laboratório.

Confira os recursos com `kubectl get pods,svc` e os releases com `helm list -n default`.

**Validação no EKS em 24/11/2026.** Com dois nodes Kubernetes 1.35.9 e os quatro serviços na revisão `6afd133`, um pedido de duas unidades foi aprovado e o estoque caiu de quatro para duas. Após `kubectl rollout restart` dos quatro Deployments, todos os pods tinham novos UIDs. Repetir o mesmo corpo e a mesma `Idempotency-Key` retornou os mesmos IDs de pedido e pagamento, e o saldo continuou em duas unidades. Dentro do pod de payments, o SDK usou credenciais de identidade web: `GetItem` encontrou o pagamento na tabela própria e recebeu `AccessDeniedException` na tabela de usuários.

Para implantar uma revisão específica manualmente em um ambiente sem Argo CD, o script Helm legado continua disponível; não o use ao mesmo tempo que o Argo CD gerencia os mesmos releases:

```bash
IMAGE_TAG=<SHA-publicado-no-ECR> make deploy
```

### 7. Testar o fluxo de um pedido

O Ingress de `orders` publica a rota exata `/orders` em um ALB **interno**, com targets IP e checagem de saúde em `/health`. O security group do listener permite HTTP a partir do CIDR do laboratório. Quem estiver na rede permitida pode chamar a API; o serviço ainda não autentica o cliente. O ALB gera cobrança enquanto existir.

Para testar a partir da VPC com os quatro serviços instalados, execute:

```bash
bash scripts/test-orders-ingress.sh
```

O teste cria usuário e produto pelos Services, envia o pedido ao DNS do ALB, repete a mesma chave de idempotência e verifica que o listener devolve 404 para `/users`.

**Validação em 24/11/2026.** No EKS 1.35, o controller 3.6.3 registrou o IP do pod de orders e o target ficou `healthy`. Pelo DNS interno, `POST /orders` retornou HTTP 201 com `payment_declined`, resultado previsto pelo simulador. O replay retornou o mesmo pedido e `/users` retornou HTTP 404.

Os Services são `ClusterIP` (internos). Para testar do seu computador, faça um port-forward com as mesmas portas do Docker Compose:

```bash
kubectl port-forward svc/products 8000:80 >/dev/null 2>&1 &
kubectl port-forward svc/orders   8001:80 >/dev/null 2>&1 &
kubectl port-forward svc/users    8002:80 >/dev/null 2>&1 &
sleep 3

./scripts/test-order.sh
```

Exemplo de resposta com pagamento aprovado:

```json
{
    "id": "7cbd9b85-2f3f-47a9-8cc8-2868e0e4094d",
    "user_id": "18014654-13b6-451a-b873-5a7489086043",
    "product_id": "df717e5c-14f9-4347-aebe-dc4ecf2a6993",
    "product_name": "Teclado",
    "quantity": 2,
    "total_price": 300.0,
    "status": "confirmed",
    "payment_id": "3280ac4c-80d4-4b83-bfa8-1d00be12e90b"
}
```

O campo `payment_id` preenchido comprova que o `orders` falou com os outros três serviços **por dentro do cluster**. Para encerrar os port-forwards: `kill $(jobs -p)`.

> O `payments` não precisa de port-forward porque só o `orders` o chama.

### 8. Desligar tudo para parar a cobrança

Remova os serviços GitOps enquanto os controllers ainda estão disponíveis. `remove-gitops.sh` desativa a reconciliação automática de `orders`, remove o Ingress e aguarda a exclusão do ALB antes de remover as aplicações e o Argo CD. Na validação de 24/11/2026, consultar os ARNs de teste retornou `LoadBalancerNotFound` e `TargetGroupNotFound` enquanto o EKS ainda estava `ACTIVE`. Depois, remova o monitoramento e o Karpenter:

```bash
bash scripts/remove-gitops.sh
bash scripts/remove-monitoring.sh
bash scripts/remove-karpenter.sh
```

**Opção A: desligar cluster e rede entre sessões.** As tabelas DynamoDB, seus dados e os repositórios ECR permanecem na conta e podem gerar custos de armazenamento.

```bash
cd infra/terraform
terraform destroy -target=module.load_balancer_irsa -target=module.karpenter -target=module.eks -target=module.vpc
```

O Terraform avisa que o uso de `-target` pode deixar mudanças incompletas. É esperado. Para subir de novo, basta um `terraform apply`. Confira que não sobrou cluster:

```bash
aws eks list-clusters --region us-east-1
```

**Opção B: apagar absolutamente tudo.** O ECR não é removido enquanto houver imagens, então esvazie os repositórios antes:

```bash
for s in products users payments orders; do
  REPO=ecommerce-microsservicos-$s
  IDS=$(aws ecr list-images --repository-name $REPO --region us-east-1 --query 'imageIds[*]' --output json)
  [ "$IDS" != "[]" ] && aws ecr batch-delete-image --repository-name $REPO --region us-east-1 --image-ids "$IDS" >/dev/null
done

cd infra/terraform
terraform destroy
```

O bucket S3 do state **não** é apagado pelo `destroy`. Para removê-lo: `aws s3 rb s3://$TF_BUCKET --force`.

## Pipeline de CI

O teste de checkout usa as quatro APIs por HTTP e confere pagamento, estoque e idempotência, aceitando aprovação ou recusa simulada. Execute a suíte somente em ambiente de testes: ela cria registros de usuários, produtos, pedidos e pagamentos. A publicação no ECR depende da aprovação dos testes e da validação de configuração. A CI executa pytest com as APIs e DynamoDB Local, rejeita testes ignorados, verifica Terraform com backend desativado, faz lint e renderiza os dois charts, verifica a sintaxe dos scripts e executa Trivy nos arquivos de configuração e nos manifests renderizados. Alterações em testes, infraestrutura, charts e scripts também disparam esses jobs.

O scan de configuração bloqueia achados HIGH e CRITICAL. As exceções atuais estão em `.trivyignore.yaml`, com justificativas para ECR mutável, endpoint administrativo público e saída dos nodes via NAT. Essas exceções devem ser revisadas na migração para GitOps e no endurecimento da rede.



O workflow `.github/workflows/ci.yml` roda em cada `push` ou `pull request` que altere serviços, código compartilhado, infraestrutura, charts, scripts, testes, `Makefile`, configuração do Trivy, Compose ou o próprio workflow. Build e scan de imagem ocorrem somente quando há alteração na aplicação (`services/**`, `common/**` ou `.dockerignore`), com um job por serviço em paralelo:

```mermaid
flowchart LR
    a["push ou pull request"] --> b["Build da imagem Docker"]
    b --> c["Scan Trivy<br/>HIGH e CRITICAL"]
    c -->|"achou vulnerabilidade com correção"| x["Pipeline reprovada"]
    c -->|"limpo, somente em push na main"| d["Login na AWS via OIDC"]
    d --> e["Push para o ECR<br/>tag imutável: SHA do commit"]
```

- **Em pull requests**, a pipeline só faz build e scan, e **não toca na AWS**.
- **No push para a `main`**, depois dos testes e scans, ela só publica no ECR quando `AWS_PUBLISH_ENABLED=true` e `AWS_ROLE_ARN` estão configuradas. As imagens recebem o SHA completo do commit.
- **Com publicação habilitada**, a pipeline abre um PR que atualiza a tag nos quatro arquivos `helm/values/*.yaml`; ao fazer merge, o Argo CD sincroniza a revisão aprovada. Sem essa habilitação, os jobs executam validações e nenhum acesso AWS acontece.
- **Trivy:** reprova em vulnerabilidades `HIGH` e `CRITICAL` que já tenham correção disponível (`ignore-unfixed`). A action do Trivy está fixada pelo **hash do commit** e não por tag, como proteção contra ataques à cadeia de suprimentos.

### Por que OIDC?

Em vez de guardar uma chave de acesso da AWS nos *secrets* do GitHub (que pode vazar e nunca expira), o GitHub emite um token temporário a cada execução, e a AWS troca esse token por credenciais de curta duração. A role criada no `oidc.tf` só pode ser assumida por pushes na `main` **deste repositório** e só tem permissão de enviar imagens para os 4 repositórios ECR.

### Usando a CI no seu fork

1. Informe seu repositório ao Terraform (em um `terraform.tfvars`, ignorado pelo Git, ou com `-var`). São três variáveis: `github_repo` (`seu-usuario/seu-repositorio`), `github_owner_id` e `github_repo_id`. O GitHub inclui os **IDs numéricos** do dono e do repositório no token; descubra-os (repositório público):

     ```bash
     curl -s https://api.github.com/users/SEU_USUARIO | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])'
     curl -s https://api.github.com/repos/SEU_USUARIO/SEU_REPOSITORIO | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])'
     ```

2. Rode `terraform apply` e anote o output `github_actions_role_arn`.
3. No GitHub, em *Settings → Secrets and variables → Actions → aba **Variables***, crie `AWS_ROLE_ARN` com esse ARN e `AWS_PUBLISH_ENABLED` com valor `true`. São *variables*, não *secrets*, porque nenhum dos valores é sensível.
4. Faça um push na `main` e acompanhe na aba *Actions*.

## Evidências do deploy

Resultados reais de uma execução do laboratório.

**Nodes do cluster EKS** (2 nodes `Ready`):

![kubectl get nodes](docs/img/kubectl-get-nodes.png)

**Pods e Services** (4 pods `1/1 Running`, todos `ClusterIP`):

![kubectl get pods e svc](docs/img/kubectl-get-pods-svc.png)

**Releases Helm** (um por serviço, mesmo chart):

![helm list](docs/img/helm-list.png)

**Pedido ponta a ponta**, aqui com o pagamento recusado pela simulação de 10% do serviço `payments` (o `payment_id` preenchido mostra que a cobrança foi processada, e o `status` reflete a recusa):

![pedido via curl](docs/img/pedido-recusado.png)

## Decisões de projeto e limitações

Este é um laboratório de estudo, e algumas escolhas priorizam **custo e simplicidade** em vez de produção. Conhecê-las é parte do aprendizado:

| Decisão | Motivo | Em produção |
|---|---|---|
| **1 único NAT Gateway** para as 2 zonas | Nodes ficam em subnets privadas (boa prática), e o NAT custa cerca de US$ 0,045/hora mais tráfego. Um só divide o custo | 1 NAT por zona, para não ter ponto único de falha, ou VPC endpoints |
| **Endpoint público da API do EKS** | Facilita o acesso do `kubectl` de qualquer lugar (a autenticação continua exigida). Dá para restringir pela variável `cluster_endpoint_public_access_cidrs` | Restringir por CIDR ou deixar privado |
| **1 réplica por serviço** | Reduz o consumo de recursos do laboratório | Validar múltiplas réplicas e HPA no EKS |
| **ALB interno** | Apenas a rota de pedidos está publicada para a rede do laboratório | Autenticação e TLS antes de abrir acesso externo |
| **Tags imutáveis no ECR** | Rastreabilidade por commit e prevenção de sobrescrita acidental | Deploy requer `IMAGE_TAG` com um SHA publicado |
| **Containers sem privilégios** | UID 10001, filesystem somente leitura no Helm e capabilities removidas | Adicionar NetworkPolicy |

Se a resposta de pagamento se perder, a reserva fica pendente até o cliente repetir o pedido com a mesma chave de idempotência.

## Custos

Valores aproximados na região `us-east-1` (confira a [calculadora de preços da AWS](https://calculator.aws/), que muda com o tempo):

| Recurso | Custo aproximado |
|---|---|
| Control plane do EKS | US$ 0,10 por hora em versão com suporte padrão; US$ 0,60 em suporte estendido |
| 2 nodes `t3.large` (sob demanda) | 2 × US$ 0,0835 por hora |
| NAT Gateway | US$ 0,045 por hora + tráfego, e ~US$ 0,005 por hora do IPv4 público |
| Volumes gp3 dos nodes | 2 × 50 GB; cerca de US$ 8 por mês (US$ 0,011 por hora) |
| **Subtotal de EKS, nodes, NAT, IPv4 e volumes** | **cerca de US$ 0,33 por hora** |
| ALB interno | Cobrança por hora e por capacidade utilizada (LCU), adicional ao subtotal |
| ECR (armazenamento das imagens) | centavos por mês; a política de retenção mantém só as 5 últimas imagens por repositório |
| Bucket S3 do state | centavos por mês |

Somente essa infraestrutura base, durante 2h, custa em torno de **US$ 0,66**. Mantida por um mês, fica perto de **US$ 240**, antes de tráfego, ALB, nós do Karpenter e armazenamento adicional. Os preços variam por região e podem mudar; consulte a [página de preços do EKS](https://aws.amazon.com/eks/pricing/), [EC2 T3](https://aws.amazon.com/ec2/instance-types/t3/), [VPC](https://aws.amazon.com/vpc/pricing/) e [EBS gp3](https://aws.amazon.com/ebs/pricing/). Na conta deste laboratório existem budgets mensais de US$20, US$50 e US$100, com alertas em 85%, 100% e previsão acima de 100%. Consulte a [página AWS Budgets](https://console.aws.amazon.com/billing/home#/budgets) antes de iniciar recursos.

## Problemas comuns

| Sintoma | Causa provável e solução |
|---|---|
| `Error: No configuration files` no `terraform apply` | Você está fora de `infra/terraform`. Entre na pasta e rode de novo |
| `terraform init` pede o bucket ou falha no backend S3 | Faltou `-backend-config=backend.hcl`, ou o bucket do arquivo não existe na sua conta. Veja o passo 2.2 |
| `EntityAlreadyExists` no provedor OIDC do GitHub | A conta já tem o provedor. Rode com `-var create_github_oidc_provider=false` |
| Node group passa de 12 minutos em *Still creating* | Verifique os eventos do Auto Scaling Group no console da AWS, que costumam apontar cota de vCPU ou erro de capacidade |
| Pods em `ImagePullBackOff` | As imagens não estão no ECR ou o ID de conta nos values está errado. Rode o passo 4 e confira o passo 2.3 |
| Pod reiniciando com `OOMKilled` | O limite de memória (128Mi) ficou pequeno. Aumente `resources.limits.memory` em `helm/microservice/values.yaml` |
| `error: unable to forward port` / porta em uso | Há um `port-forward` antigo rodando. Rode `kill $(jobs -p)` ou use outras portas |
| `test-order.sh` diz que não conseguiu conectar | Os serviços não estão no ar: confira `docker compose up` ou os `port-forward` |
| CI: `Not authorized to perform sts:AssumeRoleWithWebIdentity` | A trust policy da role não bate com o token. Confira o `sub` em [Usando a CI no seu fork](#usando-a-ci-no-seu-fork) (formato com IDs) e a variável `AWS_ROLE_ARN` |
| CI: Trivy reprova a pipeline | Há uma vulnerabilidade `HIGH` ou `CRITICAL` com correção. O log mostra o pacote e a versão corrigida: atualize o `requirements.txt` ou a imagem base |
| `terraform destroy` falha com `RepositoryNotEmpty` | O ECR ainda tem imagens. Use a Opção B do [passo 8](#8-desligar-tudo-para-parar-a-cobrança) |

## Monitoramento

As quatro APIs expõem `/metrics` para o Prometheus e registram logs JSON de requisição, consultáveis com `kubectl logs`. Rotas são registradas como templates, sem corpos, senhas ou cabeçalhos; a instrumentação não exige coletor para iniciar. Prometheus e Grafana cobrem métricas, dashboards e alertas. Instalação, consultas, limites e roteiro de apresentação estão em [docs/OBSERVABILITY.md](docs/OBSERVABILITY.md). Logs centralizados e tracing ficam fora desta versão. O código compartilhado fica em `common/`; construa cada imagem a partir da raiz, por exemplo: `docker build -f services/orders/Dockerfile .`.

## Próximos passos

Ideias para evoluir o projeto:

- [x] **GitOps com Argo CD**: app-of-apps, projeto restrito, sincronização automática dos quatro serviços e promoção de imagens por PR; instalação em cluster pendente.
- [x] **Observabilidade** com Prometheus e Grafana: métricas das APIs e Kubernetes, dashboard e alertas; validada em EKS temporário em 27/11/2026.
- [x] **Persistência e IRSA no EKS** validados com recriação dos pods e teste de acesso entre tabelas.
- [x] **Ingress interno para orders** com AWS Load Balancer Controller e IRSA, validado pelo DNS do ALB dentro da VPC.
- [x] **Endurecimento de segurança**: usuário não-root nos containers e `securityContext`; NetworkPolicy fica para expansão futura.
- [x] **Executar pytest e validar Terraform e Helm na CI**, com scan de configuração.
- [ ] **Gerenciamento de segredos** com External Secrets e AWS Secrets Manager.

Em 27/11/2026, recriamos o EKS temporariamente e validamos checkout, persistência DynamoDB/IRSA, Karpenter, ALB interno e Prometheus/Grafana; depois removemos os recursos de execução para evitar custos. A configuração GitOps está versionada, mas a instalação do Argo CD e a sincronização dos serviços ainda precisam de um cluster ativo. Permanecem os budgets e o bucket S3 do state, que têm ciclo de vida separado. Consulte [docs/ROADMAP.md](docs/ROADMAP.md) para resultados e limites, e [docs/OBSERVABILITY.md](docs/OBSERVABILITY.md) para instalação e demonstração.

## Licença

Este projeto é distribuído sob a licença **MIT**: você pode usar, copiar e adaptar livremente, em estudos ou em trabalho. Veja o arquivo [LICENSE](LICENSE).
