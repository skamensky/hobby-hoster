#!/bin/bash

# Get the public IP of the running machine
public_ip=$(curl -s https://ipinfo.io/ip)

# Add the public IP to the allowed_ssh_sources array in the config.json file
jq --arg ip "$public_ip" '.allowed_ssh_sources += [$ip]' config.json > temp.json && mv temp.json config.json