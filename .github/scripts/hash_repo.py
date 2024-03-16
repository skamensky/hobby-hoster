import hashlib
import os

def hash_directory(directory):
    sha_hash = hashlib.sha1()
    if not os.path.exists (directory):
        raise FileNotFoundError(f"Directory {directory} does not exist")

    for root, dirs, files in os.walk(directory):
        if '.git' in root.split(os.sep):
            continue
        for names in files:
            filepath = os.path.join(root, names)
            with open(filepath, 'rb') as f1:
                while True:
                    buf = f1.read(4096)  # Read in 4096 byte chunks
                    if not buf:
                        break
                    sha_hash.update(hashlib.sha1(buf).hexdigest().encode())
    if sha_hash.hexdigest() == "":
        raise ValueError("Empty digest returned")

    return sha_hash.hexdigest()

repo_hash = hash_directory('.')
print(f"::set-output name=repo_hash::{repo_hash}")
