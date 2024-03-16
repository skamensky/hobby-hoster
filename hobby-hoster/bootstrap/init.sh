#!/bin/bash

# Mount EBS Volume (assuming it's attached and available at /dev/sdh)
mkdir -p /mnt/data
mount /dev/sdh /mnt/data

# Update and install necessary packages
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce

# Configure Docker to use the EBS volume for all data storage
mkdir -p /mnt/data/docker
cat > /etc/docker/daemon.json <<EOF
{
  "data-root": "/mnt/data/docker"
}
EOF

# Restart Docker to apply configuration
systemctl restart docker

# Install Docker Compose (replace with the latest version suitable for your setup)
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Setup Traefik directories and files (assuming Traefik setup follows)
mkdir -p /mnt/data/traefik
# Make sure to adapt the path in your Traefik Docker commands or configurations to use /mnt/data/traefik for configurations and certificates


# Install Go
wget https://golang.org/dl/go1.15.6.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.15.6.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Setup and install the management agent
go build -o /mnt/data/agent /mnt/data/bootstrap/agent

mkdir /mnt/data/projects

# start traefik