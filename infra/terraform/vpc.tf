data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.101.0/24", "10.0.102.0/24"]

  # Sem NAT Gateway por enquanto -- decisao de custo para o laboratorio.
  # Os node groups do EKS vao rodar nas subnets publicas.
  enable_nat_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags exigidas pelo EKS para o Kubernetes reconhecer as subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/${var.project_name}"  = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/${var.project_name}"  = "shared"
  }

  tags = {
    Project = var.project_name
  }
}
