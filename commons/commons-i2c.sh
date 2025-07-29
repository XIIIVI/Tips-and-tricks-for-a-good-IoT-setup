#!/bin/bash

#
# activate_i2c
# This function activates I2C on the specified host by ensuring the necessary modules and configurations are in place.
# Arguments:
#   1. ROOT_USER_ARG: The username for SSH login.
#   2. ROOT_PASS_ARG: The password for SSH login.
#   3. HOST_IP_ARG: The IP address of the host where I2C should be activated.
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
sudo apt update -y  1>/dev/null
sudo DEBIAN_FRONTEND=noninteractive apt install -y -qq i2c-tools 1>/dev/null
EOF_I2C
}

#
# install_uctronics_pi_rack
# This function installs the Uctronics Pi Rack on the specified host.
# Arguments:
#   1. ROOT_USER_ARG: The username for SSH login.
#   2. ROOT_PASS_ARG: The password for SSH login.
#   3. HOST_IP_ARG: The IP address of the host where the Uctronics Pi Rack should be installed.
#   4. DIR_DATA_ARG: The directory containing the necessary files for installation.
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
# 🧩 Prevent config prompts during dpkg
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NOWARNINGS=yes

# 📦 Reconfigure any unpacked packages, quietly and safely
sudo -E dpkg --force-confnew --force-confdef --configure -a 1>/dev/null

# ⚙️ Install Python tools and git without interaction
sudo -E apt-get update -qq
sudo -E apt-get install -y -qq python3-pip python3-venv git 1>/dev/null

# 📁 Clone the UCTRONICS SSD1306 repo
cd /tmp
git clone --quiet https://github.com/UCTRONICS/U6143_ssd1306.git

# 🐍 Upgrade pip safely (inside virtualenv to avoid system conflicts)
python3 -m venv "/$HOME/uctronics-env"
source "/$HOME/uctronics-env/bin/activate"
pip install --upgrade pip setuptools --quiet

# 📦 Install required Python packages
pip install pillow Adafruit-Blinka Adafruit-SSD1306 adafruit-circuitpython-ssd1306 RPi.GPIO --quiet

# 🛠️ Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable uctronics.service
sudo systemctl start uctronics.service
EOF_UCTRONICS

    log_debug "\t- Uctronics Pi Rack installation complete."
}
