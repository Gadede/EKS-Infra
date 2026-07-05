terraform {
  backend "s3" {
    bucket       = "richeks-tfstate-bucket"
    key          = "eks/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
    encrypt      = true
  }
}
