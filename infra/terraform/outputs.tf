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
