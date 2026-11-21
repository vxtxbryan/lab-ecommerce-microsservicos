data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Publicas: so Load Balancers e o NAT Gateway.
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  # Privadas: nodes e pods. Cada pod usa um IP da subnet (VPC CNI), por isso
  # sao /20 (4091 IPs cada) e nao /24: com o Karpenter escalando nodes, uma
  # /24 acabaria rapido.
  private_subnets = ["10.0.16.0/20", "10.0.32.0/20"]

  # 1 unico NAT Gateway (compartilhado entre as AZs) para economizar.
  # Em producao: 1 por AZ, para nao ter ponto unico de falha.
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.project_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.project_name}" = "shared"
    # Descoberta de subnets pelo Karpenter (EC2NodeClass)
    "karpenter.sh/discovery" = var.project_name
  }
}
