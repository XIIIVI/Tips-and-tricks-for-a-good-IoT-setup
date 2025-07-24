#!/bin/bash

install_docker() {
    local ROOT_USER_ARG="$1"
    local ROOT_PASS_ARG="$2"
    local HOST_IP_ARG="$3"

    log_debug "\t- Installing Docker on $HOST_IP_ARG ..."

    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" <<'EOF_SSH'
    export DEBIAN_FRONTEND=noninteractive
    export DEBCONF_NOWARNINGS=yes 

if command -v docker &> /dev/null; then
    echo "Docker is already installed."
else
    echo "🔧 Cleaning up broken apt states..."
    sudo rm -f /var/lib/dpkg/lock*
    sudo rm -f /var/cache/apt/archives/lock
    sudo rm -f /var/lib/apt/lists/lock
    sudo rm -f /var/lib/dpkg/lock-frontend
    sudo -E dpkg --force-confnew --force-confdef --configure -a || true

    # Step 1 & 2: Identify and kill the first apt-related process
    echo "Killing any apt related processes"
    kill_pid=$(ps aux | grep -i apt | grep -v grep | awk '{print $2}' | head -n 1)
    
    if [ -n "$kill_pid" ]; then
        sudo kill -9 "$kill_pid"
        echo "Killed apt process with PID $kill_pid"
    fi

    # Step 3: Remove the lock file if it exists
    echo "Removing the lock file if it exists"
    [ -f /var/lib/dpkg/lock-frontend ] && sudo rm /var/lib/dpkg/lock-frontend

    # Step 4: Reconfigure dpkg
    echo "Reconfiguring dpkg"
    sudo -E dpkg --force-confnew --force-confdef --configure -a 1>/dev/null
    
    echo "      - Installing required packages"
    sudo -E apt-get install -y -qq git 1>/dev/null
    echo "      - Updating the OS"
    MAX_RETRIES=5
    DELAY=10  # seconds between retries
    COUNT=0

    until sudo apt-get update -y -qq; do
       COUNT=$((COUNT + 1))
       if [ "$COUNT" -ge "$MAX_RETRIES" ]; then
           echo "❌ apt-get update failed after $MAX_RETRIES attempts."
           exit 1
       fi
       echo "⚠️ Retry $COUNT/$MAX_RETRIES in $DELAY seconds..."
       sleep "$DELAY"
    done    

    echo "      - Upgrading the OS"
    sudo -E apt-get upgrade -y -qq -o Dpkg::Options::="--force-confnew" -o Dpkg::Options::="--force-confdef" 1>/dev/null
    echo "      - Installing Docker modules"
    MAX_ATTEMPTS=5
    ATTEMPT=1

    while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
        echo "\t\t- Attempt $ATTEMPT of $MAX_ATTEMPTS..."
        curl -fsSL https://get.docker.com -o get-docker.sh && break
        echo "\t\t  ❌ Download failed. Retrying in 3 seconds..."
        sleep 3
        ATTEMPT=$((ATTEMPT + 1))
    done

    if [ $ATTEMPT -gt $MAX_ATTEMPTS ]; then
        echo "❌ Failed to download get-docker.sh after $MAX_ATTEMPTS attempts."
        exit 1
    else    
        sudo sh get-docker.sh

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
        ATTEMPT=1

        while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
            echo "Attempt $ATTEMPT of $MAX_ATTEMPTS: Pulling hello-world image..."
    
            if sudo docker pull hello-world; then
                echo "✅ Docker image pulled successfully!"
                sudo docker run hello-world
                break
            else
                echo "❌ Failed to pull Docker image. Retrying in 5 seconds..."
                sleep 5
                ATTEMPT=$((ATTEMPT + 1))
            fi
        done

        if [ $ATTEMPT -gt $MAX_ATTEMPTS ]; then
             echo "😓 Gave up after $MAX_ATTEMPTS attempts. Network might still be unreachable."
             exit 1
         fi
    fi
fi
EOF_SSH

    if [ $? -eq 0 ]; then
       log_debug "\t✅ Docker installation completed successfully."
    else
       log_debug "\t❌ Docker installation has failed ..."
       exit 1
    fi
}
