#!/bin/bash

set -e
set -x

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )


# Update and install necessary packages
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common nvme-cli
# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-compose-plugin




# hack to find correct device since AWS attaches it as a different name than specified in TF.
# neither nvme nor the metadata api gave me the correct device name
# obviously this won't work if there are multiple devices with the same size
VOLUME_SIZE=$1
DEVICE_NAME=$(lsblk -o NAME,SIZE | grep "$VOLUME_SIZE"G | awk '{print $1}' | head -n 1)
if [ -z "$DEVICE_NAME" ]; then
  echo "No device found with the specified size of $VOLUME_SIZE GB."
  exit 1
else
  echo "Device found: $DEVICE_NAME"
fi



# Check if /dev/$DEVICE_NAME has a filesystem
if ! blkid /dev/$DEVICE_NAME; then
  echo "Creating filesystem on /dev/$DEVICE_NAME"
  mkfs -t ext4 /dev/$DEVICE_NAME
fi

if ! mount | grep -q '/mnt/data'; then
  mkdir -p /mnt/data
  # Mount EBS Volume (assuming it's attached and available at /dev/$DEVICE_NAME)
  mount /dev/$DEVICE_NAME /mnt/data
fi

# Configure Docker to use the EBS volume for all data storage
mkdir -p /mnt/data/docker
cat > /etc/docker/daemon.json <<EOF
{
  "data-root": "/mnt/data/docker"
}
EOF

# Restart Docker to apply configuration
systemctl restart docker


# Check if docker network "traefik-public" exists, if not, create it
if ! docker network ls | grep -q "traefik-public"; then
  echo "Creating docker network 'traefik-public'"
  docker network create traefik-public
else
  echo "Docker network 'traefik-public' already exists"
fi



mkdir -p /mnt/data/traefik/
cp -rf $SCRIPT_DIR/traefik/* /mnt/data/traefik/

mkdir -p /mnt/data/traefik/letsencrypt
touch /mnt/data/traefik/letsencrypt/acme.json
chmod 600 /mnt/data/traefik/letsencrypt/acme.json


# Check if traefik service exists
TRAFFIK_SERVICE_PATH="/etc/systemd/system/traefik.service"
if [ -f "$TRAFFIK_SERVICE_PATH" ]; then
  echo "Traefik service exists. Stopping and removing it."
  systemctl stop traefik.service
  systemctl disable traefik.service
  rm "$TRAFFIK_SERVICE_PATH"
  systemctl daemon-reload
else
  echo "Traefik service does not exist, no need to stop or remove."
fi


DOCKER_PATH=$(which docker)
# Create a new traefik service
cat > $TRAFFIK_SERVICE_PATH <<EOF
[Unit]
Description=Traefik Docker Compose Service
Requires=docker.service
After=docker.service

[Service]
Type=simple
WorkingDirectory=/mnt/data/traefik
ExecStart=$DOCKER_PATH compose up
ExecStop=$DOCKER_PATH compose down
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, enable and start traefik service
systemctl daemon-reload
systemctl enable traefik.service
systemctl start traefik.service




mkdir -p /mnt/data/projects
chown -R ubuntu:ubuntu /mnt/data
chown -R ubuntu:ubuntu /mnt/data/*
usermod -aG docker ubuntu

