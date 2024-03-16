#!/bin/env python
import os
import json
from pathlib import Path

env_file=Path(__file__).parent.parent / '.env'
data = {}

if env_file.exists():
    lines = env_file.read_text().splitlines()
    for line in lines:
        # Skip empty lines and comments
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        # Split line into name and value. Only split on the first = to allow for values with = in them
        name, value = line.split('=', 1)
        data[name] = value

print(json.dumps(data))
