data "aws_iam_policy_document" "external_secrets" {
  statement {
    sid       = "ReadProjectSecrets"
    actions   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/*"]
  }
}

module "external_secrets_irsa" {
  source = "./modules/irsa"

  name               = "${var.project_name}-external-secrets"
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider      = module.eks.oidc_provider
  namespace          = "external-secrets"
  service_account    = "external-secrets"
  inline_policy_json = data.aws_iam_policy_document.external_secrets.json
}

output "external_secrets_role_arn" {
  description = "Role IRSA do External Secrets Operator, limitada a segredos com prefixo do projeto"
  value       = module.external_secrets_irsa.role_arn
}
