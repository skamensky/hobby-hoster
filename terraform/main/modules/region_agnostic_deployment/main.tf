# This file is auto-generated. Do not manually edit this file.
# To change the configuration, please modify the `config.json` file and rerun the `./scripts/gen_config.py`

# The reason we needed to generate this is because terraform doesn't allow access to external program, variables, locals, environment variables, etc in "terraform" blocks
# And bucket, key, region, enerated from the config.json file

provider "aws" {
    region = var.region_name
}

terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 3.0"
        }
    }
    backend "s3" {
        bucket         = "terraform-state-kelev.dev"
        key            = "kelev.dev/terraform.tfstate"
        region         = "us-east-1"
        encrypt        = true
    }
}
