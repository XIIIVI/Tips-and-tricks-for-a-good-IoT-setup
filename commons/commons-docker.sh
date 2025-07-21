#!/bin/bash

install_docker() {
    local ROOT_USER_ARG="$1"
    local ROOT_PASS_ARG="$2"
    local HOST_IP_ARG="$3"

    for ATTEMPT in {1..5}; do
       log_debug "\t- Installing Docker on $HOST_IP_ARG (attempt ${ATTEMPT}/5) ..."

       sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" <<'EOF_SSH'
if command -v docker &> /dev/null; then
    echo "Docker is already installed."
else
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive

    echo "🔧 Cleaning up broken apt states..."
    sudo rm -f /var/lib/dpkg/lock*
    sudo rm -f /var/cache/apt/archives/lock
    sudo rm -f /var/lib/apt/lists/lock
    sudo rm -f /var/lib/dpkg/lock-frontend
    sudo dpkg --configure -a || true

    # Step 1 & 2: Identify and kill the first apt-related process
    kill_pid=$(ps aux | grep -i apt | grep -v grep | awk '{print $2}' | head -n 1)
    
    if [ -n "$kill_pid" ]; then
        sudo kill -9 "$kill_pid"
        echo "Killed apt process with PID $kill_pid"
    fi

    # Step 3: Remove the lock file if it exists
    [ -f /var/lib/dpkg/lock-frontend ] && sudo rm /var/lib/dpkg/lock-frontend

    # Step 4: Reconfigure dpkg
    sudo dpkg --configure -a 1>/dev/null

    # Step 5: Update package list
    sudo DEBIAN_FRONTEND=noninteractive apt update 1>/dev/null
    
    echo "      - Installing required packages"

    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git 1>/dev/null
    echo "      - Updating and upgrading the OS"
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -y -qq 1>/dev/null
    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq 1>/dev/null
    echo "      - Installing Docker modules"
    curl --retry 5 --retry-delay 2 --retry-max-time 60 --retry-all-errors -fsSL https://get.docker.com -o get-docker.sh
    sudo DEBIAN_FRONTEND=noninteractive sh get-docker.sh

# Setup a 10 MiB rolling log with 3 files
    echo "      - Setting up Docker logging configuration..."
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
    echo "      - Restarting Docker service... |"
    sudo systemctl restart docker

    # Test the Docker installation
    sudo docker run hello-world    
fi
EOF_SSH

        # If the SSH command succeeds, exit the loop
        if [ $? -eq 0 ]; then
           log_debug "\t✅ Docker installation completed successfully."
           break
        else
           log_debug "\t❌ Docker installation failed, retrying ..."
           sleep 2
        fi
    done
}
