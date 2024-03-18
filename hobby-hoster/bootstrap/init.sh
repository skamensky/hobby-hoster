#!/bin/bash

set -e
set -x


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


# Setup Traefik directories and files (assuming Traefik setup follows)
mkdir -p /mnt/data/traefik
# Make sure to adapt the path in your Traefik Docker commands or configurations to use /mnt/data/traefik for configurations and certificates

mkdir -p /mnt/data/projects
chown -R ubuntu:ubuntu /mnt/data
chown -R ubuntu:ubuntu /mnt/data/*
usermod -aG docker ubuntu

# start traefik

# TODO

