terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.75.0"
    }
  }
}

provider "aws" {
  version = "~> 3.0"
  region  = var.tf_state_region
}


resource "aws_s3_bucket" "tf_state_bucket" {
  bucket = var.tf_state_bucket
  acl    = "private"

  versioning {
    enabled = true
  }
}

resource "aws_dynamodb_table" "tf_state_lock" {
  name           = var.tf_state_lock_table
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}