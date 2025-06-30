#!/bin/bash

install_docker() {
    local ROOT_USER_ARG="$1"
    local ROOT_PASS_ARG="$2"
    local HOST_IP_ARG="$3"

    log_debug "\t- Installing Docker on $HOST_IP_ARG ..."

    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" <<'EOF_SSH'
if command -v docker &> /dev/null; then
    echo "Docker is already installed."
else
    set -e
    echo "+-------------------+"
    echo "| Installing Docker |"
    echo "+-------------------+"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git 1>/dev/null
    sudo curl -sL https://raw.githubusercontent.com/ezekeal/scripts/main/docker-pi.sh | bash
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "+---------------------------------------------+"
    echo "| Adding Docker repository to sources list... |"
    echo "+---------------------------------------------+"
    sudo echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    echo "+-------------------------------+"
    echo "| Updating and upgrading the OS |"
    echo "+-------------------------------+"
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -y -qq 1>/dev/null
    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq 1>/dev/null
    echo "+---------------------------+"
    echo "| Installing Docker modules |"
    echo "+---------------------------+"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 1>/dev/null

# Setup a 10 MiB rolling log with 3 files
    echo "+--------------------------------------------+"
    echo "| Setting up Docker logging configuration... |"
    echo "+--------------------------------------------+"
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF_DOCKER_DAEMON'
{
    "log-driver": "local",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "deprecated-key-path": "/var/lib/docker/key.json"
}
EOF_DOCKER_DAEMON

    # Restarts Docker to take in charge the new configuration
    echo "+------------------------------+"
    echo "| Restarting Docker service... |"
    echo "+------------------------------+"
    sudo systemctl restart docker

    # Test the Docker installation
    sudo docker run hello-world    
    echo "Docker installation complete."
fi
EOF_SSH
}
