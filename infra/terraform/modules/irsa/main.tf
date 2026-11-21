########################################################################
# Modulo reutilizavel: role IAM assumivel por UM service account do
# Kubernetes (IRSA). Usado por EBS CSI, Karpenter, ALB Controller,
# External Secrets e pelos microsservicos (DynamoDB).
########################################################################

variable "name" {
  description = "Nome da role IAM"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN do provedor OIDC do cluster (module.eks.oidc_provider_arn)"
  type        = string
}

variable "oidc_provider" {
  description = "Issuer do OIDC SEM https:// (module.eks.oidc_provider)"
  type        = string
}

variable "namespace" {
  description = "Namespace do service account"
  type        = string
}

variable "service_account" {
  description = "Nome do service account"
  type        = string
}

variable "policy_arns" {
  description = "Mapa nome => ARN de policies gerenciadas a anexar (as chaves precisam ser conhecidas no plan)"
  type        = map(string)
  default     = {}
}

variable "inline_policy_json" {
  description = "Policy inline opcional (JSON)"
  type        = string
  default     = null
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = var.policy_arns

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  count = var.inline_policy_json == null ? 0 : 1

  name   = "inline"
  role   = aws_iam_role.this.id
  policy = var.inline_policy_json
}

output "role_arn" {
  description = "ARN da role (usar na annotation eks.amazonaws.com/role-arn do service account)"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  value = aws_iam_role.this.name
}
