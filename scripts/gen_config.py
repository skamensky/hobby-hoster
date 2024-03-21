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


def nice_path_name(path:Path):
    return f"{path.parent.name}/{path.name}"

def generate_traefik_yml():
    template = dedent(f'''
    global:
      checkNewVersion: false
      sendAnonymousUsage: false

    entryPoints:
      web:
        address: ":80"
        http:
          redirections:
            entryPoint:
              to: websecure
              scheme: https
      websecure:
        address: ":443"

    certificatesResolvers:
      httpsResolver:
        acme:
          email: {config['email']}
          httpChallenge:
            entryPoint: web

    providers:
      docker:
        watch: true
        exposedByDefault: false
        network: "traefik-public"
    ''').strip()
    traefik_yml_path = root_dir /'hobby-hoster' / 'bootstrap' / 'traefik' / 'traefik.yml'
    file_exists = traefik_yml_path.exists()
    if file_exists and traefik_yml_path.read_text() == template:
        print(f"Traefik configuration is already up to date at {nice_path_name(traefik_yml_path)}")
        return
    with open(traefik_yml_path, 'w') as traefik_yml:
        traefik_yml.write(template)
        print(f"Traefik configuration has been generated at {nice_path_name(traefik_yml_path)}")

def validate_config():
    subdomains = [project['subdomain'] for project in config['projects']]
    if len(subdomains) != len(set(subdomains)):
        raise ValueError("Duplicate subdomains found in config.json")

    expected_keys = ["projects", "regions", "ssh", "tf_state", "domain_name", "base_tag",'email']
    missing_keys = [key for key in expected_keys if key not in config]
    if missing_keys:
        raise KeyError(f"Missing expected keys in config.json: {', '.join(missing_keys)}")

    ssh_keys = ["public_key_path", "private_key_path"]
    missing_ssh_keys = [key for key in ssh_keys if not Path(config['ssh'][key]).expanduser().exists()]
    if missing_ssh_keys:
        raise FileNotFoundError(f"Missing SSH keys: {', '.join(missing_ssh_keys)}")

    print("Config is valid")
    
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
    # Only write if there's a difference between the existing file and the generated content

    file_exists = output_path.exists()
    if file_exists and output_path.read_text() == main_tf_content:
        print(f"main.tf is already up to date at {nice_path_name(output_path)}")
        return

    with open(output_path, 'w') as output_file:
        output_file.write(main_tf_content)
        print(f"main.tf has been generated successfully at {nice_path_name(output_path)}")

import shutil
def generate_region_terragrunt():
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
    validate_config()
    generate_main_tf()
    generate_region_terragrunt()
    generate_traefik_yml()


if __name__=="__main__":
    main()