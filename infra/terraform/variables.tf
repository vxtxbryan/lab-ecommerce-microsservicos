variable "aws_region" {
  description = "Regiao AWS onde os recursos serao criados"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto, usado como prefixo nos recursos e como nome do cluster"
  type        = string
  default     = "ecommerce-microsservicos"
}

variable "cluster_version" {
  description = "Versao do Kubernetes no EKS. Use sempre uma versao em suporte padrao (a estendida custa 6x mais no control plane)."
  type        = string
  default     = "1.35"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs com acesso ao endpoint publico da API do EKS. Restrinja ao seu IP (ex: [\"203.0.113.10/32\"]) quando possivel."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_type" {
  description = "Tipo de instancia do node group de sistema (roda ArgoCD, Karpenter e demais componentes de plataforma)"
  type        = string
  default     = "t3.large"
}

variable "node_desired_size" {
  description = "Quantidade desejada de nodes no node group de sistema"
  type        = number
  default     = 2
}

# ----- GitHub Actions (OIDC) -----

variable "github_repo" {
  description = "Repositorio no formato dono/nome"
  type        = string
  default     = "vxtxbryan/lab-ecommerce-microsservicos"
}

variable "github_owner_id" {
  description = "ID numerico do dono do repositorio (o GitHub o inclui no claim sub)"
  type        = string
  default     = "100298866"
}

variable "github_repo_id" {
  description = "ID numerico do repositorio (o GitHub o inclui no claim sub)"
  type        = string
  default     = "1327047271"
}

variable "create_github_oidc_provider" {
  description = "Crie o provedor OIDC do GitHub. Use false se a conta ja tiver um (aws iam list-open-id-connect-providers)."
  type        = bool
  default     = true
}
