data "local_file" "config" {
  filename = "${path.module}/config.json"
}

locals {
  config = jsondecode(data.local_file.config.content)
}

variable "tf_state_bucket" {
  description = "The S3 bucket to store terraform state"
  type        = string
  default     = local.config.tf_state_bucket
}

variable "tf_state_lock_table" {
  description = "The DynamoDB table for state locking"
  type        = string
  default     = local.config.tf_state_lock_table
}


variable "tf_state_region" {
  description = "The region to store the terraform state" 
  type        = string
  default     = local.config.tf_state_region
}