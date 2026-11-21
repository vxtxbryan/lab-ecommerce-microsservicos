########################################################################
# Addon EBS CSI: necessario para volumes persistentes (Prometheus, Loki,
# Grafana). Usa IRSA, com a role criada pelo modulo local modules/irsa.
########################################################################

module "ebs_csi_irsa" {
  source = "./modules/irsa"

  name              = "${var.project_name}-ebs-csi"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider     = module.eks.oidc_provider
  namespace         = "kube-system"
  service_account   = "ebs-csi-controller-sa"

  policy_arns = {
    ebs_csi = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa.role_arn

  # Aguarda os nodes existirem antes de instalar
  depends_on = [module.eks]
}
