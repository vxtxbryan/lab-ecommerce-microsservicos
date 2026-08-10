variable "aws_region" {
  description = "Regiao AWS onde os recursos serao criados"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto, usado como prefixo nos recursos"
  type        = string
  default     = "ecommerce-microsservicos"
}

variable "cluster_version" {
  description = "Versao do Kubernetes no EKS"
  type        = string
  default     = "1.30"
}
