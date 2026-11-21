# Backend parcial: o nome do bucket NAO fica no codigo (nomes de bucket sao
# unicos no mundo todo). Informe-o na hora do init:
#
#   cp backend.hcl.example backend.hcl      # e edite o bucket
#   terraform init -backend-config=backend.hcl
#
# Se voce ja tinha o state no S3 (versao anterior deste repo), use
# `terraform init -reconfigure -backend-config=backend.hcl` com o MESMO bucket.
terraform {
  backend "s3" {
    key          = "ecommerce-microsservicos/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
