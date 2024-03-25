#!/bin/bash

set -e
set -x

  GO_VERSION="1.21.8"
  GO_WORKSPACE="/mnt/data/go"
  GO_MODULE_CACHE="/mnt/data/go/pkg/mod"

  # Ensure the directories exist
  mkdir -p "$GO_WORKSPACE"
  mkdir -p "$GO_MODULE_CACHE"


  GO_INSTALL_DIR="/mnt/data/bin/go"
  PATH=$PATH:$GO_INSTALL_DIR/bin

  if ! go version &> /dev/null; then
    echo "Go is not installed. Installing Go $GO_VERSION."
    wget https://go.dev/dl/go$GO_VERSION.linux-amd64.tar.gz
    mkdir -p "$GO_INSTALL_DIR"
    sudo tar -C "$GO_INSTALL_DIR" -xzf go$GO_VERSION.linux-amd64.tar.gz --strip-components=1
    echo "export PATH=$PATH:$GO_INSTALL_DIR/bin" >> $HOME/.profile
    echo "export GOPATH=$GO_WORKSPACE" >> $HOME/.profile
    echo "export GOMODCACHE=$GO_MODULE_CACHE" >> $HOME/.profile
    source $HOME/.profile
  else
    echo "Go is already installed."
  fi



mkdir -p /mnt/data/agent
# Setup and install the management agent
(cd /tmp/agent && go build -o /mnt/data/agent/cli cli/main.go)

mkdir -p /mnt/data/projects
chown -R ubuntu:ubuntu /mnt/data
chown -R ubuntu:ubuntu /mnt/data/*
