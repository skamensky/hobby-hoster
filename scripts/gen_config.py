#!/usr/bin/env python3


from dotenv import load_dotenv
import os
from passlib.apache import HtpasswdFile
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
          storage: /letsencrypt/acme.json
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

def generate_traefik_compose_yml():
    domain = config['domain_name']

    # Read BASIC_AUTH_PASSWORD from .env file
    basic_auth_user = os.getenv('TRAEFIK_BASIC_AUTH_USERNAME')
    if not basic_auth_user:
        raise ValueError("TRAEFIK_BASIC_AUTH_USERNAME not found in .env file.")
    
    basic_auth_password=os.getenv('TRAEFIK_BASIC_AUTH_PASSWORD')
    if not basic_auth_password:
        raise ValueError("TRAEFIK_BASIC_AUTH_PASSWORD not found in .env file.")


    # Create a new HtpasswdFile instance in memory (no file argument means it won't be read from or written to disk)
    ht = HtpasswdFile()

    ht.set_password(basic_auth_user, basic_auth_password)

    # Get the hashed password line for the user, which includes the username
    hashed_password_line = ht.to_string().decode().strip()

    escaped_for_yaml = hashed_password_line.replace('$','$$')
    template = dedent(f'''
                      
    # This file is auto-generated. Do not manually edit this file.
    # To change the configuration, please modify the `config.json` file and rerun the `./scripts/gen_config.py`
    
    # The reason we need to generate this file, is because it uses domain name and hashed password.
                      
    version: '3.7'

    services:
      traefik:
        image: traefik:v2.11.0
        command:
          - "--api.dashboard=true"
          - "--accesslog"
          - "--log"
          - --entrypoints.web.address=:80
          - --entrypoints.websecure.address=:443
          - --providers.docker
          - --providers.docker.exposedByDefault=false
          - --api
          - --certificatesresolvers.le.acme.email={config['email']}
          - --certificatesresolvers.le.acme.storage=/certificates/acme.json
          - --certificatesresolvers.le.acme.tlschallenge=true
        ports:
          - "80:80"
          - "443:443"
        volumes:
          - "/var/run/docker.sock:/var/run/docker.sock"
          - "traefik-certificates:/certificates"
        networks:
          - traefik-public
        labels:
          - "traefik.enable=true"
          - "traefik.http.routers.traefik.rule=Host(`traefik.{domain}`)"
          - "traefik.http.routers.traefik.service=api@internal"
          - "traefik.http.routers.traefik.tls.certresolver=le"
          - "traefik.http.routers.traefik.entrypoints=websecure"
          - "traefik.http.routers.traefik.middlewares=auth"
          # Add basic auth middleware for security, ignore differences to this line when generating since it will always change
          # IGNORE_DIFF_START
          # All services will use this same basic auth middleware. For us to pick up on it they need to add hobby-hoster.private=true to their labels
          - "traefik.http.middlewares.auth.basicauth.users={escaped_for_yaml}"
          # IGNORE_DIFF_END

    volumes:
      traefik-certificates:
        external: true

    networks:
      traefik-public:
        external: true 
    ''').strip()
    traefik_compose_yml_path = root_dir /'hobby-hoster' / 'bootstrap' / 'traefik' / 'docker-compose.yml'



    old_file_parts = traefik_compose_yml_path.read_text().split("# IGNORE_DIFF_START")
    old_file = old_file_parts[0] + old_file_parts[1].split("# IGNORE_DIFF_END")[1] if len(old_file_parts) > 1 else old_file_parts[0]

    new_file_parts = template.split("# IGNORE_DIFF_START")
    new_file = new_file_parts[0] + new_file_parts[1].split("# IGNORE_DIFF_END")[1] if len(new_file_parts) > 1 else new_file_parts[0]

    if old_file == new_file:
        print(f"Traefik docker-compose configuration is already up to date at {nice_path_name(traefik_compose_yml_path)}")
    else:
        traefik_compose_yml_path.write_text(template)
        print(f"Traefik docker-compose configuration has been generated at {nice_path_name(traefik_compose_yml_path)}")

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

def generate_readme_subdomains():
    subdomains = config.get('projects', [])
    subdomain_content = "\n\n".join([f"- **{project['subdomain']}**: Located at [{project['subdomain']}.{config['domain_name']}](https://{project['subdomain']}.{config['domain_name']}). Hosted at {project['repo']}. {project['description']}" for project in subdomains])

    readme_path = root_dir / 'README.md'
    with open(readme_path, 'r+') as readme_file:
        content = readme_file.read()
        start_tag = "<!--INJECT_SUBDOMAINS_START-->"
        end_tag = "<!--INJECT_SUBDOMAINS_END-->"
        start = content.find(start_tag) + len(start_tag)
        end = content.find(end_tag)
        new_content = content[:start] + "\n" + subdomain_content + "\n" + content[end:]

        if new_content == content:
            print(f"README.md is already up to date at {nice_path_name(readme_path)}")
            return
        else:
          readme_file.seek(0)
          readme_file.write(new_content)
          readme_file.truncate()
          print(f"README.md has been updated successfully at {nice_path_name(readme_path)}")
def main():
    load_dotenv(root_dir / '.env')
    validate_config()
    generate_main_tf()
    generate_region_terragrunt()
    generate_traefik_yml()
    generate_traefik_compose_yml()
    generate_readme_subdomains()

if __name__=="__main__":
    main()