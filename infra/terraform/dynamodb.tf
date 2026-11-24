locals {
  service_table_actions = {
    users    = ["GetItem", "PutItem", "Scan"]
    payments = ["GetItem", "PutItem"]
    orders   = ["GetItem", "PutItem", "UpdateItem", "Scan"]
    products = ["GetItem", "PutItem", "UpdateItem", "DeleteItem", "Scan"]
  }
}

resource "aws_dynamodb_table" "service" {
  for_each     = toset(local.services)
  name         = "${var.project_name}-${each.key}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

module "service_irsa" {
  for_each          = toset(local.services)
  source            = "./modules/irsa"
  name              = "${var.project_name}-${each.key}"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider     = module.eks.oidc_provider
  namespace         = "default"
  service_account   = each.key
}

resource "aws_iam_role_policy" "service_table" {
  for_each = aws_dynamodb_table.service
  name     = "service-table"
  role     = module.service_irsa[each.key].role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [for action in local.service_table_actions[each.key] : "dynamodb:${action}"]
      Resource = each.value.arn
    }]
  })
}

output "service_helm_values" {
  description = "Valores Helm específicos da conta e região por serviço"
  value = {
    for service in local.services : service => {
      image          = { repository = aws_ecr_repository.services[service].repository_url }
      serviceAccount = { roleArn = module.service_irsa[service].role_arn }
      env = {
        "${upper(service)}_TABLE" = aws_dynamodb_table.service[service].name
        AWS_DEFAULT_REGION        = var.aws_region
      }
    }
  }
}
