terraform {
  backend "s3" {
    bucket       = "ecommerce-microsservicos-tfstate-6250d96a"
    key          = "ecommerce-microsservicos/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
