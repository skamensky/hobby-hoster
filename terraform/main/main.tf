provider "aws" {
  region = var.tf_state_region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
    
  }
  backend "s3" {
    bucket = var.tf_state_bucket
    dynamodb_table = var.tf_state_lock_table
    region = var.tf_state_region
    encrypt = true
  }
}
