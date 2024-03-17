# Project Architecture Overview

This document outlines the architecture for hosting multiple web-based hobby projects on a single AWS EC2 instance, leveraging Terraform for infrastructure as code, Docker for containerization, and Traefik for reverse proxy and TLS management. The setup ensures that each project is self-contained, easily manageable, and secure, with the flexibility to add, remove, and edit projects as needed.

## Infrastructure Setup with Terraform

- **EC2 Instance**: An EC2 instance is created with a public static IP address using an Elastic IP (EIP) for consistent access. This instance will host all Docker containers for the projects. We are using Ubuntu 22.04 LTS. The AMI is different per region. Region to AMI is kept in the config/region-mapping.json file.
  https://cloud-images.ubuntu.com/locator/ec2/


- **External Disk**: An Elastic Block Store (EBS) volume is attached for persistent data storage across projects, mounted at a consistent path. This ensures that all project data is kept on an external disk, facilitating easy management and backup.

- **Data Backup**: Daily snapshots of the EBS volume are automated with a retention policy of 7 days, using AWS Backup or a custom Lambda function. This meets the requirement for disk snapshots to happen daily and expire after 7 days.

- **Emergency Restore**: A Terraform script is available to initiate an EC2 instance from a specified EBS snapshot ID for quick recovery, allowing for emergency restores as needed.

## EC2 Instance Initialization

A bootstrap bash script ([bootstrap/init.sh](file:///home/shmuel/repos/kelev-infra/bootstrap/init.sh)) prepares the EC2 instance by installing Docker, Docker Compose, and setting up Traefik as a reverse proxy. This script ensures the EC2 instance is properly set up to host the projects.

## Project Management and Deployment

- **Docker Compose**: Each project is contained within its own Docker Compose setup for isolation and easy management. This allows for each project to be a self-contained Docker Compose project. Any github repo mentioned in [projects.json](file:///home/shmuel/repos/kelev-infra/projects.json#1%2C1-1%2C1) will be cloned and run as a docker-compose project.

- **Project Repositories**: Projects are maintained in separate GitHub repositories for modular development. This supports the requirement for each project to be maintained in its own GitHub repo.

- **CI/CD**: GitHub Actions in each project repository handle CI/CD, with deployment triggers that are based on tags of this repo. For each new tag, the CI/CD is run. All interactions with the server are done via ssh.
The CI/CD will  iterate over each project
- checkout the repo
- hash the contents of the repo
- check if that hash exists in github artifacts
- if it does, no need to do anything for that service
- if it doesn't, tell the management agent to clone the repo and rebuild the service. Then update the github artifacts with the new hash.


## Management Agent
The ec2 instance has an agent which can respond to various management commands. Current commands supported:
- Rebuild all services
- Rebuild a specific service
- Clone github repo to a specific directory (and commit)



## Reverse Proxy and TLS Management

- **Traefik Configuration**: Traefik is configured to route traffic based on domain names to the correct Docker container. It automates LetsEncrypt certificate generation and renewal, ensuring TLS management is handled efficiently. The domain purchased and pointed to this IP in DNS settings is fully supported by this setup.**


- **DNS**: I purchased the domain from cloudflare. I have a terraform script that will create the dns records for the domain. The script will also create a wildcard record for the domain. This will allow me to create subdomains on the fly. 

## Logging and Monitoring

- **Logging**: Centralized logging is recommended, using either an ELK stack or AWS CloudWatch. This ensures good logging practices are in place.

- **Monitoring**: Tools like Prometheus and Grafana, or AWS CloudWatch, are used for monitoring with configured alerts. This ensures the infrastructure and applications are closely monitored for any issues.

## Data Persistence and Security

- **EBS Volume**: Containers use volumes backed by the attached EBS volume for data persistence. This ensures that all data is kept on an external disk, as required.

This architecture supports the dynamic addition, removal, and editing of projects, with each project maintained in its own GitHub repository. It emphasizes automation, security, and ease of management for hobby projects.

Integrating the details from [projects.json](file:///home/shmuel/repos/kelev-infra/projects.json#1%2C1-1%2C1) into the architecture overview clarifies how individual project repositories interact with the overall infrastructure, particularly in terms of deployment and domain routing.

## Enhanced Project Management and Deployment

Each project, as defined in [projects.json](file:///home/shmuel/repos/kelev-infra/projects.json#1%2C1-1%2C1), is encapsulated within its own Docker Compose setup and maintained in a separate GitHub repository. This structure allows for modular development and version control. The [projects.json](file:///home/shmuel/repos/kelev-infra/projects.json#1%2C1-1%2C1) file serves as a manifest for the projects, detailing their names, repository URLs, and domains.

### Deployment Workflow:

1. **CI/CD Integration**: GitHub Actions within each project repository are configured for Continuous Integration and Deployment. These actions build Docker images and, upon manual trigger, deploy updates to the EC2 environment.

2. **Domain Routing**: Traefik, set up on the EC2 instance, uses the domain information from [projects.json](file:///home/shmuel/repos/kelev-infra/projects.json#1%2C1-1%2Cinfra/projects.json#1%2C1-1%2C1) to route incoming requests to the appropriate Docker container based on the project's domain. This is achieved by configuring Docker labels in the compose files, which Traefik recognizes for routing.

### Example Traefik Docker Label for  [fun-n-games](file:///home/shmuel/repos/kelev-infra/projects.json#3%2C14-3%2C14):

This label tells Traefik to route requests for `fun-n-games.kelev.dev` to the container running the `fun-n-games` project.

### Continuous Deployment:

The CI/CD process can be further automated by integrating with the `projects` object in `config.json`. Upon a successful build and Docker image creation, a script can update the EC2 instance's Docker Compose configurations to pull the latest image versions, ensuring that the deployment reflects the most recent changes in the repositories.

### Summary:

The `projects` object in `config.json` file acts as a central manifest for managing the deployment and domain routing of individual projects. By leveraging GitHub Actions for CI/CD and Traefik for reverse proxying, each project can be independently developed, versioned, and deployed, with the infrastructure automatically routing traffic to the correct project based on its domain. This architecture ensures that all deployment and infrastructure setup from start to finish is done in Terraform on AWS, meeting the project's requirements for automation, security, and ease of management.


### Project requirements:

Software to run this project is maintained in a nix flake. The flake will contain all the software needed to run the project.

For more information on nix, see the nix flake documentation.

### Secrets

Terraform will read the .env file for secrets

### Manual steps

For now, I'm manually updating A records in the cloudflare dashboard. They don't support changing nameservers and I can't transfer the domain to a different registrar for the next 60 days.


### Run terraform:
Initial: in bootstrap, do terraform init and terraform apply
After: Generate the terragrunt files for each region by running ./scripts/gen_config.py

Then, run the following command to apply the changes to the ec2 instance:
```sh
cd terraform/region/REGION_NAME
terragrunt apply
```

#### Config
When making configuation changes to config.json, there is some generation that needs to happen. This is done by running the following command:
```sh
./scripts/gen_config.py
```


### allowed ssh sources
The allowed ssh sources are defined in the config.json file. This is a list of ip addresses that are allowed to ssh into the ec2 instance.

To add your current machine, run the following commands:
```sh
./scripts/allow_current_machine_ssh.sh
cd terraform/region/REGION_NAME
terragrunt apply


