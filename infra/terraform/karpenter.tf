module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "20.37.2"

  cluster_name                    = module.eks.cluster_name
  enable_v1_permissions           = true
  enable_pod_identity             = false
  enable_irsa                     = true
  irsa_oidc_provider_arn          = module.eks.oidc_provider_arn
  irsa_namespace_service_accounts = ["kube-system:karpenter"]
  create_instance_profile         = true
  enable_spot_termination         = false # O NodePool deste laboratório aceita apenas On-Demand.

  iam_policy_statements = [
    {
      sid       = "ReadRegionalCapacity"
      actions   = ["ec2:DescribeCapacityReservations", "ec2:DescribeInstanceStatus", "ec2:DescribePlacementGroups"]
      resources = ["*"]
      conditions = [{
        test     = "StringEquals"
        variable = "aws:RequestedRegion"
        values   = [var.aws_region]
      }]
    },
    {
      sid       = "ListProfiles"
      actions   = ["iam:ListInstanceProfiles"]
      resources = ["*"]
    },
  ]
}

output "karpenter_settings" {
  value = {
    cluster         = module.eks.cluster_name
    controller_role = module.karpenter.iam_role_arn
    profile         = module.karpenter.instance_profile_name
    region          = var.aws_region
  }
}
