output "vpc_id" {
  description = "ID da VPC criada"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "IDs das subnets publicas (Load Balancers e NAT)"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "IDs das subnets privadas (nodes e pods)"
  value       = module.vpc.private_subnets
}

output "cluster_name" {
  description = "Nome do cluster EKS"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint da API do cluster"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Versao do Kubernetes"
  value       = module.eks.cluster_version
}

output "oidc_provider_arn" {
  description = "ARN do provedor OIDC do cluster (base do IRSA)"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider" {
  description = "Issuer OIDC do cluster, sem https://"
  value       = module.eks.oidc_provider
}

output "node_security_group_id" {
  description = "Security group dos nodes"
  value       = module.eks.node_security_group_id
}

output "account_id" {
  description = "ID da conta AWS em uso"
  value       = data.aws_caller_identity.current.account_id
}

output "ecr_repository_urls" {
  description = "URLs dos repositorios ECR"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

output "configure_kubectl" {
  description = "Comando para conectar o kubectl ao cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
