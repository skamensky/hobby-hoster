#!/usr/bin/env python3

import sys
import json
import subprocess
import os
from pathlib import Path

BASE_PATH = Path(__file__).resolve().parent.parent
REGION = sys.argv[1] if len(sys.argv) > 1 else None
NO_CACHE = sys.argv[2] if len(sys.argv) > 2 else None
CONFIG_FILE = f"{BASE_PATH}/config.json"
TERRAGRUNT_OUTPUT_FILE = f"{BASE_PATH}/terraform/main/regions/{REGION}/terragrunt.hcl"
CACHE_FILE = f"{BASE_PATH}/tmp_cache.json"

if not os.path.exists(CACHE_FILE):
    with open(CACHE_FILE, 'w') as cache_file:
        cache_file.write('{"ips": {}}')

if not REGION:
    with open(CONFIG_FILE, 'r') as config_file:
        config = json.load(config_file)
        REGION = config['regions'][0]['region']
    print(f"Warning: No region specified. Defaulting to first region in config: {REGION}")
    print(f"Usage: {sys.argv[0]} <region> [--no-cache]")

def extract_ip():
    # run terragrunt output
    command = ["terragrunt", "output", "-raw", "public_ip"]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=f"{BASE_PATH}/terraform/main/regions/{REGION}")
    output, error = process.communicate()
    if process.returncode != 0:
        print(f"Error getting IP: {error.decode().strip()}")
        sys.exit(1)
    return output.decode().strip().strip('"')

def verify_region():
    with open(CONFIG_FILE, 'r') as file:
        config = json.load(file)
        regions = [region['region'] for region in config['regions']]
        if REGION not in regions:
            print(f"Region {REGION} not found in {CONFIG_FILE}")
            sys.exit(1)


def update_cache(ip_address,region):
    with open(CACHE_FILE, 'r') as cache_file:
        cache = json.loads(cache_file.read())
        cache['ips'][region] = ip_address
    with open(CACHE_FILE, 'w') as cache_file:
        cache_file.write(json.dumps(cache, indent=4))

def ip_in_cache(region):
    with open(CACHE_FILE, 'r') as cache_file:
        cache = json.load(cache_file)
        return cache['ips'].get(region)

def ip_from_cache(region):
    return ip_in_cache(region)

def main():
    verify_region()

    if NO_CACHE == "--no-cache":
        print("Skipping cache...")
        ip_address = extract_ip()
    elif ip_in_cache(REGION):
        ip_address = ip_from_cache(REGION)
        print(f"Using cached ip for region {REGION}: {ip_address}")
    else:
        print(f"ip for {REGION} not found in cache. Retreiving...")
        ip_address = extract_ip()

    if not ip_address:
        print(f"ip not found for region {REGION}")
        sys.exit(1)
    else:
        update_cache(ip_address,REGION)
        print(f"Connecting to server at {ip_address}...")
        subprocess.run(["ssh", f"ubuntu@{ip_address}"])


if __name__ == "__main__":
    main()

