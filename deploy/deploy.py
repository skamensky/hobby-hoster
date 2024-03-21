import json
import os
import subprocess
import paramiko
from io import StringIO
from pathlib import Path
from typing import Union

ROOT_DIR = Path(__file__).parent.parent


def run_agent_command(ssh_client, command, args:Union[dict,list[str]]):
    if type(args) is dict:
        args = json.dumps(args)
        args = args.replace('"', '\\"')
        args = f'"{args}"'
    else:
        args = " ".join(args)
    stdin, stdout, stderr = ssh_client.exec_command(f'/mnt/data/agent/cli {command} {args} --json')
    error = stderr.read().decode()
    if error:
        raise Exception(f"Error running {command}: {error}")
    
    data_str = stdout.read().decode()
    try:
        data = json.loads(data_str)
    except Exception as e:
        print(f"Error parsing json: {data_str}")
        raise e
    if type(data) is dict and data.get('error'):
        raise Exception(f"Error running {command}: {data['error']}")
    return data


def get_current_services(projects):
    results = []
    for project in projects:
        repo_url = project['repo']
        subdomain = project['subdomain']
        last_commit = subprocess.check_output(['git', 'ls-remote', repo_url, 'HEAD']).decode().split()[0]
        results.append({'subdomain': subdomain, 'last_commit': last_commit, 'repo_url': repo_url})
    return results


def rebuild_projects(ssh_client, projects_to_build, domain):

    # tell agent to clone:

    clone_args = []
    for project in projects_to_build:
        clone_args.append(project['repo_url'])
        clone_args.append(project['subdomain'])
    run_agent_command(ssh_client, "clone", clone_args)

    projects_json = {
            "domain": domain,
            "subdomains": [
                {
                    "subdomain": project['subdomain'],
                    "extra_traefik_labels": project.get('extra_traefik_labels', [])
                } for project in projects_to_build
            ]
        }

    run_agent_command(ssh_client, "rebuild", projects_json)
    
def destroy_projects(ssh_client, projects_to_destroy):
    run_agent_command(ssh_client, "remove", projects_to_destroy)

def get_remote_services(ssh_client):
    return run_agent_command(ssh_client, "list-services",[])

def run_scripts_and_terragrunt_apply():
    # Run allow_current_machine_ssh.sh script
    subprocess.run(["./scripts/allow_current_machine_ssh.sh"], check=True)

    # Run gen_config.py script
    subprocess.run(["python3", "./scripts/gen_config.py"], check=True)

    # Load the updated configuration to get the list of regions
    with open('config.json') as f:
        config = json.load(f)

    # Iterate through each region and run terragrunt apply noninteractively
    for region in config['regions']:
        region_name = region['region']
        terragrunt_dir = f"terraform/main/regions/{region_name}"
        print(f"Applying terragrunt configuration in {region_name}")
        subprocess.run(["terragrunt", "apply", "-auto-approve"], cwd=terragrunt_dir, check=True)

def main():

    # deploy latest changes and add current machine to the list of allowed machines
    run_scripts_and_terragrunt_apply()

    with open('config.json') as f:
        config = json.load(f)

    ssh_key_path = Path(config['ssh'].get('private_key_path', '')).expanduser().absolute()
    domain = config['domain_name']

    if ssh_key_path and ssh_key_path.exists() and ssh_key_path.is_file():
        ssh_key = ssh_key_path.read_text()
    elif os.environ.get('SSH_PRIVATE_KEY'):
        ssh_key = os.environ.get('SSH_PRIVATE_KEY')
    else:
        raise Exception("SSH private key not found.")
    for region in config['regions']:
        ssh_client = paramiko.SSHClient()
        ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        pkey = paramiko.RSAKey.from_private_key(StringIO(ssh_key))

        region = region['region']
        terragrunt_dir = f"terraform/main/regions/{region}"
        os.chdir(ROOT_DIR/terragrunt_dir)
        process = subprocess.Popen(['terragrunt', 'output', '-raw', 'public_ip'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, stderr = process.communicate()
        if stderr:
            raise Exception(f"Error getting public IP: {stderr.decode()}")
        public_ip = stdout.decode().strip()

        ssh_client.connect(
            hostname=public_ip,
            username=config['ssh']['user'],
            pkey=pkey
        )

        remote_services = {service['subdomain']: service for service in get_remote_services(ssh_client)}
        local_services = {service['subdomain']: service for service in get_current_services(config['projects'])}


        new_services = []
        services_to_update = []
        # new or changed
        services_to_build = []
        services_to_destroy = []

        

        for subdomain,service in local_services.items():
            if subdomain not in remote_services:
                new_services.append(service)
            elif service['last_commit'] != remote_services[service['subdomain']]['last_commit']:
                services_to_update.append(service)

        services_to_build = new_services + services_to_update

        for service in remote_services:
            if service not in local_services:
                services_to_destroy.append(service)


        print(f"Building new services {new_services}, services to update {services_to_update}")
        if services_to_build:
            rebuild_projects(ssh_client, services_to_build,domain)

        print(f"Destroying {services_to_destroy}")
        if services_to_destroy:
            destroy_projects(ssh_client, services_to_destroy)

        ssh_client.close()

    print('Done!')



if __name__ == "__main__":
    main()