
data "local_file" "config" {
  filename = "${var.repo_root}/config.json"
}

data "external" "env" {
  program = ["python", "${var.repo_root}/scripts/env_to_json.py"]
}

locals {
  config = jsondecode(data.local_file.config.content)
  env = data.external.env.result
  base_tag = local.config.base_tag
  domain_name = local.config.domain_name
  region = [for r in local.config.regions : r if r.region == var.region_name][0]
  allowed_ssh_sources = local.config.allowed_ssh_sources
  ssh_pub_key_path = pathexpand(local.config.ssh.public_key_path)
  ssh_private_key_path = pathexpand(local.config.ssh.private_key_path)
  attached_volume_size = local.region.attached_volume_size
  project_root = var.repo_root
}

variable "region_name" {
  type        = string
  description = "The name of the region where resources will be deployed."
  
}

variable "repo_root" {
  type        = string
  description = "The root path of the repository."
}