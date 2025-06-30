#!/bin/bash

#
# activate_i2c
#
activate_i2c() {
    local ROOT_USER_ARG="$1"
    local ROOT_PASS_ARG="$2"
    local HOST_IP_ARG="$3"

    log_debug "\t- Activating I2C on $HOST_IP_ARG ..."

    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" 'bash -s' <<'EOF_I2C'
# Ensure i2c-dev is in /etc/modules
if ! grep -q "^i2c-dev" /etc/modules; then
    echo "i2c-dev" | sudo tee -a /etc/modules
fi

# Ensure dtparam=i2c_arm=on is present and uncommented
CONFIG_FILE="/boot/firmware/config.txt"
if grep -q "^#dtparam=i2c_arm=on" "$CONFIG_FILE"; then
    sudo sed -i 's|^#dtparam=i2c_arm=on|dtparam=i2c_arm=on|' "$CONFIG_FILE"
elif ! grep -q "^dtparam=i2c_arm=on" "$CONFIG_FILE"; then
    echo "dtparam=i2c_arm=on" | sudo tee -a "$CONFIG_FILE"
fi

# Load module and install tools
sudo modprobe i2c-dev
sudo apt update -y
sudo DEBIAN_FRONTEND=noninteractive apt install -y -qq i2c-tools
EOF_I2C
}

#
# install_uctronics_pi_rack
#
install_uctronics_pi_rack() {
    local ROOT_USER_ARG="$1"
    local ROOT_PASS_ARG="$2"
    local HOST_IP_ARG="$3"
    local DIR_DATA_ARG="$4"

    log_debug "\t- Installing Uctronics Pi Rack on $HOST_IP_ARG ..."

    activate_i2c "$ROOT_USER_ARG" "$ROOT_PASS_ARG" "$HOST_IP_ARG"
    copy_file_to_host "$ROOT_USER_ARG" "$ROOT_PASS_ARG" "$HOST_IP_ARG" "${DIR_DATA_ARG}/uctronics.service" "/etc/systemd/system"
    copy_file_to_host "$ROOT_USER_ARG" "$ROOT_PASS_ARG" "$HOST_IP_ARG" "${DIR_DATA_ARG}/ssd1306_stats.py" "/opt"

    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" 'bash -s' <<'EOF_UCTRONICS'
sudo dpkg --configure -a    
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-pip git
cd "/tmp"
git clone https://github.com/UCTRONICS/U6143_ssd1306.git
sudo pip3 install --upgrade pip setuptools
sudo pip3 install pillow Adafruit-Blinka Adafruit-SSD1306 adafruit-circuitpython-ssd1306 --break-system-packages --quiet

sudo systemctl daemon-reload
sudo systemctl enable uctronics.service
sudo systemctl start uctronics.service
EOF_UCTRONICS

    log_debug "\t- Uctronics Pi Rack installation complete."
}
