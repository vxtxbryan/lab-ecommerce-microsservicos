# Política upstream do controller v3.6.3 (docs/install/iam_policy.json).
module "load_balancer_irsa" {
  source = "./modules/irsa"

  name               = "${var.project_name}-alb-controller"
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider      = module.eks.oidc_provider
  namespace          = "kube-system"
  service_account    = "aws-load-balancer-controller"
  inline_policy_json = file("${path.module}/policies/load-balancer-controller.json")
}

output "load_balancer_settings" {
  value = {
    clusterName = module.eks.cluster_name
    region      = var.aws_region
    vpcId       = module.vpc.vpc_id
    serviceAccount = {
      name        = "aws-load-balancer-controller"
      annotations = { "eks.amazonaws.com/role-arn" = module.load_balancer_irsa.role_arn }
    }
  }
}
