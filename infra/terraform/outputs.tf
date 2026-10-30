output "vpc_id" {
  description = "ID da VPC criada"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "IDs das subnets publicas"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "IDs das subnets privadas"
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

output "ecr_repository_urls" {
  description = "URLs dos repositorios ECR"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}
