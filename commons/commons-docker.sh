#!/bin/bash

# ============================================================
#  Project:   commons-docker.sh
#  Author:    Fabrice TRAN-XUAN
#  Created:   2025-08-10
#
#  License:   MIT License
#
#  Permission is hereby granted, free of charge, to any person
#  obtaining a copy of this software and associated documentation
#  files (the "Software"), to deal in the Software without
#  restriction, including without limitation the rights to use,
#  copy, modify, merge, publish, distribute, sublicense, and/or
#  sell copies of the Software, and to permit persons to whom the
#  Software is furnished to do so, subject to the following
#  conditions:
#
#  The above copyright notice and this permission notice shall be
#  included in all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
#  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
#  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
#  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
#  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
#  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
#  OTHER DEALINGS IN THE SOFTWARE.
# ============================================================

#
# install_docker_container_viewer
# This function installs Docker Container Viewer (DCV) on the specified host.
# Arguments:
#   1. ROOT_USER_ARG: The username for SSH login.
#   2. ROOT_PASS_ARG: The password for SSH login.
#   3. HOST_IP_ARG: The IP address of the host where DCV should be installed.
#
install_docker_container_viewer() {
    local ROOT_USER_ARG="$1"
    local ROOT_PASS_ARG="$2"
    local HOST_IP_ARG="$3"

    log_debug "\t- Installing Docker Container Viewer (DCV) on $HOST_IP_ARG ..."

    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" << 'EOF_DCV'
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    export DEBCONF_NOWARNINGS=yes

    # --- Detect if we need sudo ---
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
    else
        SUDO="sudo"
    fi

    # --- Retry wrapper for curl ---
    CURL_RETRY() {
        local URL="$1" OUTPUT="$2" MAX_RETRIES=5 DELAY=5 COUNT=0
        until [ $COUNT -ge $MAX_RETRIES ]; do
            if curl -fsSL --retry 3 --retry-delay 3 -o "$OUTPUT" "$URL"; then
                return 0
            fi
            COUNT=$((COUNT+1))
            echo "⚠️ curl failed ($COUNT/$MAX_RETRIES). Retrying in ${DELAY}s..."
            sleep $DELAY
        done
        echo "❌ ERROR: Failed to download $URL after $MAX_RETRIES attempts"
        exit 1
    }

    # --- Architecture detection ---
    LOCAL_ARCHITECTURE=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case "$LOCAL_ARCHITECTURE" in
        amd64 | x86_64) GO_ARCH="amd64"; DCV_ARCH="amd64" ;;
        arm64 | aarch64) GO_ARCH="arm64"; DCV_ARCH="arm64" ;;
        armhf | armv7l) GO_ARCH="armv6l"; DCV_ARCH="armhf" ;;  # adjust if needed
        *) echo "❌ Unsupported architecture: $LOCAL_ARCHITECTURE"; exit 1 ;;
    esac

    echo "ℹ️ Installing for architecture: $LOCAL_ARCHITECTURE"

    # --- Install Go if missing ---
    if ! command -v go >/dev/null 2>&1; then
        echo "📦 Installing Go for $GO_ARCH"
        $SUDO apt-get update -y
        $SUDO apt-get remove -y golang-go || true
        $SUDO rm -rf /usr/local/go
        cd /tmp
        CURL_RETRY "https://go.dev/dl/go1.24.0.linux-${GO_ARCH}.tar.gz" "GO.TAR.GZ"
        $SUDO tar -C /usr/local -xzf GO.TAR.GZ
        echo 'export PATH=$PATH:/usr/local/go/bin' | $SUDO tee /etc/profile.d/go.sh
    fi

    if /usr/local/go/bin/go version >/dev/null 2>&1; then
         echo "✅ Go is installed: $(/usr/local/go/bin/go version)"
    else
         echo "❌ Go installed but version check failed"
    fi

    # --- Install DCV if missing ---
    if ! command -v dcv >/dev/null 2>&1; then
        echo "📦 Installing DCV"
        cd /tmp
        CURL_RETRY "https://github.com/tokuhirom/dcv/releases/latest/download/dcv_linux_${DCV_ARCH}.tar.gz" "DCV.TAR.GZ"
        $SUDO tar -xzf DCV.TAR.GZ
        DCV_BIN=$($SUDO find . -type f -name dcv -perm -u+x | head -n1)
        [ -n "$DCV_BIN" ] && [ -x "$DCV_BIN" ] || { echo "❌ DCV binary not found"; exit 1; }
        $SUDO mv "$DCV_BIN" /usr/local/bin/dcv
    fi

    command -v dcv >/dev/null && echo "✅ DCV installed at $(command -v dcv)"
EOF_DCV
}

#
# install_docker
# This function installs Docker on the specified host.
# Arguments:
#   1. ROOT_USER_ARG: The username for SSH login.
#   2. ROOT_PASS_ARG: The password for SSH login.
#   3. HOST_IP_ARG: The IP address of the host where Docker should be installed.
#   4. REGISTRY_IP_ARG: The IP address of the Docker registry (optional).
#   5. REGISTRY_PORT_ARG: The port of the Docker registry (optional).
#   6. REGISTRY_CERTIFICATE_ARG: The path to the Docker registry certificate (optional).
#
install_docker() {
    local ROOT_USER_ARG="$1"
    local ROOT_PASS_ARG="$2"
    local HOST_IP_ARG="$3"
    local REGISTRY_IP_ARG="$4"
    local REGISTRY_PORT_ARG="$5"
    local REGISTRY_CERTIFICATE_ARG="$6"

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
    sudo -E apt-get install -y -qq git jq 1>/dev/null
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
        echo "Attempt $ATTEMPT of $MAX_ATTEMPTS..."
        curl -fsSL https://get.docker.com -o get-docker.sh && break
        echo "  ❌ Download failed. Retrying in 3 seconds..."
        sleep 3
        ATTEMPT=$((ATTEMPT + 1))
    done

    if [ $ATTEMPT -gt $MAX_ATTEMPTS ]; then
        echo "❌ Failed to download get-docker.sh after $MAX_ATTEMPTS attempts."
        exit 1
    else    
        ATTEMPT=1

        while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
            echo "Attempt $ATTEMPT of $MAX_ATTEMPTS: Running get-docker.sh..."
    
            if sudo sh get-docker.sh; then
                echo "✅ Docker installation script ran successfully!"
                break
            else
                echo "❌ Script failed. Retrying in 5 seconds..."
                sleep 5
                ATTEMPT=$((ATTEMPT + 1))
            fi
        done

        if [ $ATTEMPT -gt $MAX_ATTEMPTS ]; then
            echo "😵 Gave up after $MAX_ATTEMPTS attempts. Something’s still off."
            exit 1
        fi

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

         echo "      - Installing IPVS modules"
         sudo modprobe ip_vs
         sudo modprobe ip_vs_rr
         sudo modprobe ip_vs_wrr
         sudo modprobe ip_vs_sh

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
   
    if [ -n "${REGISTRY_IP_ARG}" ] && [ -n "${REGISTRY_PORT_ARG}" ]; then
        local REGISTRY_URL

        REGISTRY_URL="${REGISTRY_IP_ARG}:${REGISTRY_PORT_ARG}"

        log_debug "\t- Setting up the access to the Docker registry ${REGISTRY_IP_ARG}:${REGISTRY_PORT_ARG} ..."
        sshpass -p "${ROOT_PASS_ARG}" ssh -o StrictHostKeyChecking=no "${ROOT_USER_ARG}@${HOST_IP_ARG}" "sudo jq --arg val \"$REGISTRY_URL\" '.[\"insecure-registries\"] = (. [\"insecure-registries\"] // []) + [\$val]' /etc/docker/daemon.json > /tmp/daemon.json && sudo mv /tmp/daemon.json /etc/docker/daemon.json"

        if [ -n "${REGISTRY_CERTIFICATE_ARG}" ]; then
             local CERTIFICATE_FILENAME=$(basename "${REGISTRY_CERTIFICATE_ARG}")

             log_warning "\t\t- Adding the certificate for the Docker registry ${REGISTRY_URL} ..."
             copy_file_to_host "${ROOT_USER_ARG}" "${ROOT_PASS_ARG}" "${HOST_IP_ARG}" "${REGISTRY_CERTIFICATE_ARG}" "/usr/local/share/ca-certificates/" 
             sshpass -p "${ROOT_PASS_ARG}" ssh -o StrictHostKeyChecking=no "${ROOT_USER_ARG}@${HOST_IP_ARG}" "sudo mkdir -p /etc/docker/certs.d/${REGISTRY_URL}"
             sshpass -p "${ROOT_PASS_ARG}" ssh -o StrictHostKeyChecking=no "${ROOT_USER_ARG}@${HOST_IP_ARG}" "sudo cp /usr/local/share/ca-certificates/${CERTIFICATE_FILENAME} /etc/docker/certs.d/${REGISTRY_URL}/ca.crt"
             sshpass -p "${ROOT_PASS_ARG}" ssh -o StrictHostKeyChecking=no "${ROOT_USER_ARG}@${HOST_IP_ARG}" "sudo update-ca-certificates"

             # Run curl and capture both output and HTTP status code
             log_warning "\t\t- Testing the connection to the Docker registry ${REGISTRY_URL} ..."

             RESPONSE=$(curl -sk -w "%{http_code}" -o /tmp/catalog_response.json "https://${REGISTRY_URL}/v2/_catalog")

             # Check if request was successful
             if [[ "$RESPONSE" -eq 200 ]]; then
                 log_warning "\t\t\t✅ Docker registry is reachable."

                 # Optional: Parse the catalog response
                 if jq -e '.repositories | length > 0' /tmp/catalog_response.json > /dev/null; then
                     log_warning "\t\t\t✅ Repositories found"
                 else
                     log_error "\t\t\t⚠️ No repositories found."
                 fi
             else
                 log_error "\t\t\t❌ Failed to reach registry. Status code: $RESPONSE"
                 log_error "\t\t\tYou can add -v to curl for verbose SSL/certificate/debug details."
                 exit 1
             fi
        fi

        log_debug "\t- Restarting Docker service to apply the changes ..."
        sshpass -p "${ROOT_PASS_ARG}" ssh -o StrictHostKeyChecking=no "${ROOT_USER_ARG}@${HOST_IP_ARG}" "sudo systemctl restart docker"
    fi

    if [ $? -eq 0 ]; then
       log_debug "\t✅ Docker installation completed successfully."
       install_docker_container_viewer "${ROOT_USER_ARG}" "${ROOT_PASS_ARG}" "${HOST_IP_ARG}"
    else
       log_debug "\t❌ Docker installation has failed ..."
       exit 1
    fi
}
