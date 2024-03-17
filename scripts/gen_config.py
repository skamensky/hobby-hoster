#!/usr/bin/env python3

from pathlib import Path
import json
from textwrap import dedent


# Set the root directory based on the file location
root_dir = Path(__file__).parent.parent

# Load the configuration from config.json
config_path = root_dir / 'config.json'
with open(config_path, 'r') as config_file:
    config = json.load(config_file)


def generate_main_tf():
    # Generate the main.tf content with auto-generated comment
    main_tf_content = dedent(f"""\
    # This file is auto-generated. Do not manually edit this file.
    # To change the configuration, please modify the `config.json` file and rerun the `./scripts/gen_config.py`
    
    # The reason we needed to generate this is because terraform doesn't allow access to external program, variables, locals, environment variables, etc in "terraform" blocks
    # And bucket, key, region, enerated from the config.json file

    provider "aws" {{
        region = var.region_name
    }}

    terraform {{
        required_providers {{
            aws = {{
                source  = "hashicorp/aws"
                version = "~> 3.0"
            }}
        }}
        backend "s3" {{
            bucket         = "{config['tf_state']['bucket']}"
            key            = "{config['tf_state']['key']}"
            region         = "{config['tf_state']['region']}"
            encrypt        = true
        }}
    }}
    """)

    output_path = root_dir / 'terraform' / 'main' / 'modules' / 'region_agnostic_deployment' / 'main.tf'

    # Write the generated content to the main.tf file
    with open(output_path, 'w') as output_file:
        output_file.write(main_tf_content)

    print(f"main.tf has been generated successfully at {output_path}")

import shutil
def gen_region_terragrunt():
    regions_dir = root_dir / 'terraform' / 'main' / 'regions'
    # Ensure the regions directory exists
    regions_dir.mkdir(parents=True, exist_ok=True)

    # Load regions from config
    config_regions = {region.get('region') for region in config.get('regions', [])}
    existing_dirs = {region_dir.name for region_dir in regions_dir.iterdir() if region_dir.is_dir()}

    removed_regions = []
    added_regions = []
    # Remove directories for regions not in config
    for region_dir in existing_dirs - config_regions:
        shutil.rmtree(regions_dir / region_dir)
        removed_regions.append(region_dir)
        print(f"Removed {region_dir}")



    # Generate terragrunt files for regions in config
    for region_name in config_regions - existing_dirs:
        region_dir = regions_dir / region_name
        region_dir.mkdir(exist_ok=True)
        terragrunt_file_path = region_dir / 'terragrunt.hcl'
        terragrunt_content = dedent(f"""\
                                    
        # This file is auto-generated. Do not manually edit this file.
        # To change the configuration, please modify the `config.json` file and rerun the `./scripts/gen_config.py`
                                    
        # The reason we needed to generate this is because we have multiple regions and we need to generate an identical terragrunt file for each region

        terraform {{
          source = "../../modules/region_agnostic_deployment"
        }}

        inputs = {{
          region_name = "{region_name}"
          repo_root = get_repo_root()
        }}""")
        with open(terragrunt_file_path, 'w') as terragrunt_file:
            terragrunt_file.write(terragrunt_content)
        
        added_regions.append(region_name)
        print(f"Terragrunt configuration has been generated for {region_name}")
        
    if not removed_regions and not added_regions:
        print(f"No changes need to be made to regions directory")
        return

def main():
    generate_main_tf()
    gen_region_terragrunt()


if __name__=="__main__":
    main()