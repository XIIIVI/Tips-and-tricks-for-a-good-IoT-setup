#!/usr/bin/env bash
set -eo pipefail

#
# install_chrony_ntp
# Deploy and configure chrony NTP on a list of nodes
# Arguments:
#   USER_ARG - SSH username
#   PASS_ARG - SSH password
#   IP_ADDRESS_ARG - IP address of the host to configure
#
install_chrony_ntp() {
  local USER_ARG="$1"
  local PASS_ARG="$2"
  local IP_ADDRESS_ARG="$3"   # pass array by name

  # --- NTP SERVER DEFINITION (embedded here) ---
  read -r -d '' NTP_SERVERS_ARG <<'EOF'
pool fr.pool.ntp.org iburst
server ntp.univ-lyon1.fr iburst
server ntp.obspm.fr iburst
server time.cloudflare.com iburst
server time.google.com iburst
pool pool.ntp.org iburst
EOF

    log_info "Configuring NTP on the node $NODE..."

    sshpass -p "$PASS_ARG" ssh -o StrictHostKeyChecking=no "$USER_ARG@$IP_ADDRESS_ARG" bash -s <<EOF
set -eo pipefail

# Install chrony if missing
if ! command -v chronyd >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y && sudo apt-get install -y chrony
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y chrony
  fi
fi

# Write config
sudo bash -c "cat > /etc/chrony/chrony.conf <<EOC
# Managed remotely
$NTP_SERVERS_ARG

makestep 1.0 3
driftfile /var/lib/chrony/chrony.drift
logdir /var/log/chrony
EOC"

# Restart service
sudo systemctl restart chrony || sudo systemctl restart chronyd
sudo systemctl enable chrony || sudo systemctl enable chronyd

# Verify
chronyc tracking || true
chronyc sources -v || true
EOF

  log_debug "\t-✅ Chrony NTP setup complete on the node $NODE."
}
