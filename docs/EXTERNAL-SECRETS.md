# Segredos com External Secrets e AWS Secrets Manager

## Como funciona

O External Secrets Operator (ESO) lê valores do AWS Secrets Manager usando uma role IAM associada à sua ServiceAccount por IRSA. Ele cria um Secret Kubernetes no namespace de destino; o valor nunca precisa ser armazenado no Git.

```text
AWS Secrets Manager
        │ IRSA: GetSecretValue + DescribeSecret
        ▼
External Secrets Operator ──► Secret Kubernetes ──► variável de ambiente do pod
```

O Terraform configura a role `ecommerce-microsservicos-external-secrets`, confiável apenas para a ServiceAccount `external-secrets` no namespace `external-secrets`. A policy limita a leitura a nomes iniciados por `ecommerce-microsservicos/`. Não há acesso de escrita, listagem ou leitura de segredos de outros prefixos.

## Instalação

O chart External Secrets Operator 2.15.0 está fixado para Kubernetes 1.37, versão compatível indicada pela matriz de suporte atual. Essa é a versão padrão em `infra/terraform/variables.tf`. O operador fica nos nodes de sistema e usa o namespace `external-secrets`. Ao atualizar a versão do chart ou Kubernetes, atualize ambos juntos após conferir a matriz oficial.

Depois de aplicar Terraform, configurar o kubeconfig e instalar o controller Karpenter, execute:

```bash
bash scripts/install-external-secrets.sh
```

O script confere se o kubeconfig aponta para o cluster do state e se o servidor Kubernetes é 1.37 ou superior. Ele aplica as CRDs grandes com server-side apply antes de instalar o chart, conforme a orientação do projeto External Secrets. Ele não cria segredos no Secrets Manager. Após instalar o operador, Argo CD sincroniza `gitops/apps/secrets.yaml`, que declara o `SecretStore` namespaced `aws-secrets-manager` no namespace `default`.

## Criar e consumir um segredo

Crie um segredo no AWS Secrets Manager com nome dentro do prefixo autorizado, por exemplo `ecommerce-microsservicos/payments/provider-api`. Para segredo JSON, guarde uma propriedade `api_key`. Use o console ou a AWS CLI sem colocar o valor em argumentos visíveis no histórico do shell; mantenha o arquivo JSON fora do repositório e remova-o com segurança após o envio.

Copie `examples/external-secrets/payments-api.yaml.example` para `gitops/apps/payments-api-secret.yaml`, confirme o `remoteRef.key` e a propriedade JSON e envie a alteração. Argo CD cria o ExternalSecret e ESO cria `payments-api-credentials` no namespace `default`.

No arquivo `helm/values/payments.yaml`, declare a referência sem o valor secreto:

```yaml
secretEnv:
  - name: API_KEY
    secretName: payments-api-credentials
    secretKey: API_KEY
```

Faça commit da referência e deixe o Argo CD sincronizar. A aplicação precisa ler `API_KEY`; o serviço de pagamentos simulado atual não usa uma chave externa.

## Rotação e remoção

ESO reconcilia o Secret Kubernetes a cada hora. A atualização de uma variável de ambiente em um Secret não reinicia automaticamente os pods existentes; após a rotação, faça rollout do Deployment consumidor ou adicione um controller de restart automático em uma evolução futura.

`deletionPolicy: Retain` preserva o Secret Kubernetes quando o objeto remoto some, até uma ação operacional explícita. Revise o RBAC do Kubernetes: usuários capazes de ler Secrets no namespace conseguem acessar esses valores. Para segredos criptografados com uma chave KMS gerenciada pelo cliente, conceda `kms:Decrypt` somente para essa chave e ajuste a role IRSA.

Antes de `terraform destroy`, remova Argo CD/GitOps, o operator e depois a infraestrutura:

```bash
bash scripts/remove-gitops.sh
bash scripts/remove-external-secrets.sh
terraform -chdir=infra/terraform destroy
```

## Limite desta configuração

A versão, role IRSA, Helm values, SecretStore e exemplo de ExternalSecret estão versionados e passam validação local. O EKS foi destruído após a validação anterior do projeto; portanto, esta integração ainda não foi instalada nem testada contra uma conta AWS ativa. A validação de runtime fica pendente até uma futura sessão autorizada de infraestrutura.
