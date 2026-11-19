########################################################################
# OIDC GitHub Actions -> AWS
# Permite que o workflow do GitHub assuma uma role na AWS sem chaves de
# acesso guardadas no repositorio. A role so pode ser assumida por
# pushes na branch main deste repositorio.
########################################################################

locals {
  github_repo = "vxtxbryan/lab-ecommerce-microsservicos"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # A AWS valida o certificado do GitHub por conta propria; o valor e
  # exigido por algumas versoes do provider.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Project = var.project_name
  }
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Somente a branch main deste repositorio
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json

  tags = {
    Project = var.project_name
  }
}

data "aws_iam_policy_document" "github_ecr_push" {
  # O token de login do ECR nao aceita restricao por recurso
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push apenas nos 4 repositorios do projeto
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [for repo in aws_ecr_repository.services : repo.arn]
  }
}

resource "aws_iam_role_policy" "github_ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_ecr_push.json
}

output "github_actions_role_arn" {
  description = "ARN da role que o GitHub Actions assume (guardar na variavel AWS_ROLE_ARN do repositorio)"
  value       = aws_iam_role.github_actions.arn
}
