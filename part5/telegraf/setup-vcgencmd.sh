#!/bin/bash

# Define paths and systemd service names
SCRIPT_PATH="/usr/local/bin/vcgencmd_metrics.sh"
TMP_DIR="/tmp/telegraf_metrics"
METRICS_FILE="$TMP_DIR/vcgencmd.influx"
SERVICE_NAME="vcgencmd.service"
TIMER_NAME="vcgencmd.timer"

# Create temporary directory for storing metrics with correct permissions
echo "Creating temporary directory..."
mkdir -p $TMP_DIR
chmod 777 $TMP_DIR

# Create vcgencmd metrics script
echo "Creating vcgencmd script..."
tee $SCRIPT_PATH > /dev/null <<EOF
#!/bin/bash

HOSTNAME=\$(hostname)

echo "rpi_metrics,host=\$HOSTNAME soc_temp=\$(vcgencmd measure_temp | awk -F '=' '{print \$2}' | sed 's/..$//')" > $METRICS_FILE
echo "rpi_metrics,host=\$HOSTNAME core_volts=\$(vcgencmd measure_volts core | awk -F '=' '{print \$2}' | sed 's/..$//')" >> $METRICS_FILE
echo "rpi_metrics,host=\$HOSTNAME arm_freq=\$(vcgencmd measure_clock arm | awk -F '=' '{print \$2}')" >> $METRICS_FILE
echo "rpi_metrics,host=\$HOSTNAME throttled_status=\$(vcgencmd get_throttled | awk -F '=' '{print \$2}')" >> $METRICS_FILE
EOF

# Make the script executable
chmod +x $SCRIPT_PATH

# Create systemd service
echo "Creating SystemD service..."
tee /etc/systemd/system/$SERVICE_NAME > /dev/null <<EOF
[Unit]
Description=Collect vcgencmd metrics for Telegraf
After=network.target

[Service]
ExecStart=$SCRIPT_PATH
Nice=10
Restart=no
EOF

# Create systemd timer
echo "Creating SystemD timer..."
tee /etc/systemd/system/$TIMER_NAME > /dev/null <<EOF
[Unit]
Description=Timer to trigger vcgencmd service every 10s

[Timer]
OnUnitActiveSec=10s
Unit=$SERVICE_NAME

[Install]
WantedBy=timers.target
EOF

# Reload SystemD, enable & start the timer
echo "Enabling and starting the timer..."
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME
systemctl enable $TIMER_NAME
systemctl start $TIMER_NAME

# Verify setup
echo "Checking active timers..."
systemctl list-timers --all | grep $TIMER_NAME

echo "Setup complete! Metrics will update every 10 seconds in: $METRICS_FILE"
