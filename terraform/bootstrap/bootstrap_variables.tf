data "local_file" "config" {
  filename = "${path.module}/../../config.json"
}


locals {
  config = jsondecode(data.local_file.config.content)
  tf_state_bucket = local.config.tf_state.bucket
  tf_state_lock_table = local.config.tf_state.lock_table
  tf_state_region = local.config.tf_state.region
}
