#!/bin/bash

set -e

SCRIPT_DIR=$(dirname "$0")

# Get the public IP of the running machine
public_ip=$(curl -s https://ipinfo.io/ip)

# if public_ip is empty, exit
if [ -z "$public_ip" ]; then
  echo "Public IP is empty, exiting"
  exit 1
fi

# Check if the IP is already in the allowed_ssh_sources array
allowed_ips=$(jq -r '.allowed_ssh_sources[]' "$SCRIPT_DIR/../config.json")
already_in_allowed_ips=false
for ip in $allowed_ips
do
  if [ "$ip" == "$public_ip" ]; then
    already_in_allowed_ips=true
    break
  fi
done

if [ "$already_in_allowed_ips" == false ]; then
  # If not, add the public IP to the allowed_ssh_sources array in the config.json file
  jq --arg ip "$public_ip" '.allowed_ssh_sources += [$ip]' "$SCRIPT_DIR/../config.json" > "$SCRIPT_DIR/temp.json" && mv "$SCRIPT_DIR/temp.json" "$SCRIPT_DIR/../config.json"
fi
