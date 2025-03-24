#!/bin/bash -e

# Load configurations from config.env
source config.env

setup_axonops_repo() {
    cat > /etc/yum.repos.d/axonops-yum.repo << EOL
[axonops-yum]
name=axonops-yum
baseurl=${AXONOPS_REPO_URL:-https://packages.axonops.com/yum/}
enabled=1
repo_gpgcheck=0
gpgcheck=0
EOL
}