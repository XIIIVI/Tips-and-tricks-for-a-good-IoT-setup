#!/bin/bash

#
# activate_i2c
#
activate_i2c() {
    local ROOT_USER_ARG="$1"
    local ROOT_PASS_ARG="$2"
    local HOST_IP_ARG="$3"

    log_info "Activating I2C on $HOST_IP_ARG ..."

    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" <<'EOF_I2C'
if ! grep -q "i2c-dev" /etc/modules; then
    sed -i 's|#dtparam=i2c_arm=on|dtparam=i2c_arm=on|g' /boot/firmware/config.txt
    echo "i2c-dev" | sudo tee -a /etc/modules
    sudo modprobe i2c-dev
    sudo apt update -y
    sudo apt install -y i2c-tools
fi
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

    log_info "Installing Uctronics Pi Rack on $HOST_IP_ARG ..."

    copy_file_to_host "$ROOT_USER_ARG" "$ROOT_PASS_ARG" "$HOST_IP_ARG" "${DIR_DATA_ARG}/uctronics.service" "/etc/systemd/system"
    copy_file_to_host "$ROOT_USER_ARG" "$ROOT_PASS_ARG" "$HOST_IP_ARG" "${DIR_DATA_ARG}/ssd1306_stats.py" "/opt"

    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" 'bash -s' <<'EOF_UCTRONICS'
sudo apt-get install -y python3-pip git
cd "\$HOME"
git clone https://github.com/UCTRONICS/U6143_ssd1306.git
sudo pip3 install Adafruit-Blinka Adafruit-SSD1306 adafruit-circuitpython-ssd1306

sudo systemctl daemon-reload
sudo systemctl enable uctronics.service
sudo systemctl start uctronics.service
EOF_UCTRONICS

    log_info "Uctronics Pi Rack installation complete."
}
