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

# -----------------------------------------------------------
# install_vcgencmd
# Deploy vcgencmd metrics collection remotely via sshpass
# Arguments:
#   1. SSH username
#   2. SSH password
#   3. SSH host
# -----------------------------------------------------------
install_vcgencmd() {
    # -------------------------------
    # SSH connection parameters
    # -------------------------------
    local USER_ARG="$1"           # SSH username
    local PASS_ARG="$2"           # SSH password
    local HOST_ARG="$3"           # SSH host
    local SCRIPT_PATH="/usr/local/bin/vcgencmd_metrics.sh"
    local TMP_DIR="/tmp/telegraf_metrics"
    local SERVICE_NAME="vcgencmd.service"
    local TIMER_NAME="vcgencmd.timer"

    log_info "Deploying vcgencmd metrics collection to $HOST_ARG ..."

    # -------------------------------
    # Execute remote deployment
    # -------------------------------
    sshpass -p "$PASS_ARG" ssh -o StrictHostKeyChecking=no "$USER_ARG@$HOST_ARG" "bash -s" <<EOF
#!/bin/bash
set -e

METRICS_FILE="$TMP_DIR/vcgencmd.influx"

# -------------------------------
# Ensure vcgencmd is installed
# -------------------------------
if ! command -v vcgencmd >/dev/null 2>&1; then
    echo "Installing vcgencmd (libraspberrypi-bin)..."
    apt-get update -y
    apt-get install -y libraspberrypi-bin
else
    echo "vcgencmd already installed."
fi

# -------------------------------
# Create temporary directory
# -------------------------------
echo "Creating temporary directory: $TMP_DIR"
mkdir -p "$TMP_DIR"
chmod 777 "$TMP_DIR"

# -------------------------------
# Create vcgencmd metrics script
# -------------------------------
echo "Creating vcgencmd script at $SCRIPT_PATH"
tee "$SCRIPT_PATH" > /dev/null <<'EOS'
#!/bin/bash
HOSTNAME=\$(hostname)
echo "rpi_metrics,host=\$HOSTNAME soc_temp=\$(vcgencmd measure_temp | awk -F '=' '{print \$2}' | sed 's/..$//')" > "$METRICS_FILE"
echo "rpi_metrics,host=\$HOSTNAME core_volts=\$(vcgencmd measure_volts core | awk -F '=' '{print \$2}' | sed 's/..$//')" >> "$METRICS_FILE"
echo "rpi_metrics,host=\$HOSTNAME arm_freq=\$(vcgencmd measure_clock arm | awk -F '=' '{print \$2}')" >> "$METRICS_FILE"
echo "rpi_metrics,host=\$HOSTNAME throttled_status=\$(vcgencmd get_throttled | awk -F '=' '{print \$2}')" >> "$METRICS_FILE"
EOS

chmod +x "$SCRIPT_PATH"

# -------------------------------
# Create systemd service
# -------------------------------
echo "Creating systemd service: $SERVICE_NAME"
tee "/etc/systemd/system/$SERVICE_NAME" > /dev/null <<EOS
[Unit]
Description=Collect vcgencmd metrics for Telegraf
After=network.target

[Service]
ExecStart=$SCRIPT_PATH
Nice=10
Restart=no
EOS

# -------------------------------
# Create systemd timer
# -------------------------------
echo "Creating systemd timer: $TIMER_NAME"
tee "/etc/systemd/system/$TIMER_NAME" > /dev/null <<EOS
[Unit]
Description=Timer to trigger vcgencmd service every 10s

[Timer]
OnUnitActiveSec=10s
Unit=$SERVICE_NAME

[Install]
WantedBy=timers.target
EOS

# -------------------------------
# Reload systemd and enable/start
# -------------------------------
echo "Reloading systemd and enabling services..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"
systemctl enable "$TIMER_NAME"
systemctl start "$TIMER_NAME"

# -------------------------------
# Verify setup
# -------------------------------
echo "Checking active timers..."
systemctl list-timers --all | grep "$TIMER_NAME"

echo "Setup complete! Metrics will update every 10 seconds in: $METRICS_FILE"
EOF
}
