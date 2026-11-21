module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.project_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # nodes e ENIs do control plane

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Cria o provedor OIDC do cluster, base do IRSA (roles IAM por service account)
  enable_irsa = true

  enable_cluster_creator_admin_permissions = true

  # Addons gerenciados. O aws-ebs-csi-driver fica em addons.tf porque precisa
  # de uma role IRSA que depende do OIDC deste modulo.
  cluster_addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    kube-proxy = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
  }

  # Node group "de sistema": pequeno e fixo. Roda os componentes de plataforma
  # (Karpenter, ArgoCD, ALB Controller...). Os nodes de carga de trabalho serao
  # criados pelo Karpenter (fase 1).
  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]
      capacity_type  = "ON_DEMAND"

      min_size     = 2
      max_size     = 3
      desired_size = var.node_desired_size

      labels = {
        workload = "system"
      }

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
    }
  }

  # O Karpenter encontra o security group dos nodes por esta tag
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.project_name
  }
}
