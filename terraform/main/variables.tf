data "local_file" "config" {
  filename = "${path.module}/config.json"
}

data "external" "env" {
  program = ["python", "${path.module}/../scripts/env_to_json.py"]
}

locals {
  config = jsondecode(data.local_file.config.content)
  env = jsondecode(data.external.env.result)
}





variable "base_tag"{
  description = "The base tag to be used for all resources"
  type        = string
  default     = local.config.base_tag
}



variable "domain_name"{
  description = "The domain name to be used for the Route53 zone"
  type        = string
  default     = local.config.domain_name
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


variable "regions" {
  description = "The regions configuration"
  type        = list(object({
    region = string
    ami = string
    availability_zone = string
  }))
  default = local.config.regions
}

variable "allowed_ssh_sources" {
  description = "The allowed SSH sources"
  type        = list(string)
  default     = local.config.allowed_ssh_sources
}

variable "ssh_pub_key_path" {
  description = "The path to the SSH public key to be used for the EC2 instance"
  type        = string
  default     =  local.config.ssh_public_key_path
}

variable "ssh_private_key_path" {
  description = "The path to the SSH private key to be used for the EC2 instance"
  type        = string
  default     =  local.config.ssh_private_key_path
}

variable "allowed_ssh_sources" {
  description = "The allowed SSH sources"
  type        = list(string)
  default     = local.config.allowed_ssh_sources
}

variable "instance_type" {
  description = "The instance type of the EC2 instance"
  type        = string
  default     = "t3.micro"
}

variable "state_file_path" {
  description = "The path to the Terraform state file"
  type        = string
}

variable "project_root" {
  description = "The root of the project"
  type        = string
  default     = path.module + "/../.."
}

