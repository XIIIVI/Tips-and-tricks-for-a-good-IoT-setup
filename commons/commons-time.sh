#!/usr/bin/env bash
set -eo pipefail

# ============================================================
#  Project:   commons-time.sh
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

    log_info "Configuring NTP on the node $IP_ADDRESS_ARG..."

    sshpass -p "$PASS_ARG" ssh -o StrictHostKeyChecking=no "$USER_ARG@$IP_ADDRESS_ARG" bash -s <<EOF
set -eo pipefail

# Install chrony if missing
if ! command -v chronyd >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y && sudo apt-get install -y -qq chrony
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

  log_debug "\t-✅ Chrony NTP setup complete on the node $IP_ADDRESS_ARG."
}
