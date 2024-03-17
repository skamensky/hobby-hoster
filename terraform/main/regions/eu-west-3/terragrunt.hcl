
# This file is auto-generated. Do not manually edit this file.
# To change the configuration, please modify the `config.json` file and rerun the `./scripts/gen_config.py`

# The reason we needed to generate this is because we have multiple regions and we need to generate an identical terragrunt file for each region

terraform {
  source = "../../modules/region_agnostic_deployment"
}

inputs = {
  region_name = "eu-west-3"
  repo_root = get_repo_root()
}