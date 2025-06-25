#!/bin/bash

#
# activate_i2c
#
activate_i2c() {
    local ROOT_USER_ARG="$1"
    local ROOT_PASS_ARG="$2"
    local HOST_IP_ARG="$3"

    log_info "Activating I2C on $HOST_IP_ARG ..."

    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" << 'EOF_I2C'
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

    log_info "Installing Uctronics Pi Rack on $HOST_IP_ARG ..."

    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" << 'EOF_UCTRONICS'
    sudo apt-get install -y python3-pip
    cd $HOME
    git clone https://github.com/UCTRONICS/U6143_ssd1306.git
    sudo pip3 install Adafruit-Blinka
    sudo pip3 install Adafruit-SSD1306
    sudo pip3 install adafruit-circuitpython-ssd1306

    cat << 'EOF_SSD1306' > /opt/ssd1306_stats.py
# SPDX-FileCopyrightText: 2017 Tony DiCola for Adafruit Industries
# SPDX-FileCopyrightText: 2017 James DeVito for Adafruit Industries
# SPDX-License-Identifier: MIT

# This example is for use on (Linux) computers that are using CPython with
# Adafruit Blinka to support CircuitPython libraries. CircuitPython does
# not support PIL/pillow (python imaging library)!
import math
import time
import subprocess

from board import SCL, SDA
import busio
from PIL import Image, ImageDraw, ImageFont
import adafruit_ssd1306
# Create the I2C interface.
i2c = busio.I2C(SCL, SDA)
# Create the SSD1306 OLED class.
# The first two parameters are the pixel width and pixel height.  Change these
# to the right size for your display!
disp = adafruit_ssd1306.SSD1306_I2C(128, 32, i2c)

# Clear display.
disp.fill(0)
disp.show()

# Create blank image for drawing.
# Make sure to create image with mode '1' for 1-bit color.
width = disp.width
height = disp.height
image = Image.new("1", (width, height))

# Get drawing object to draw on image.
draw = ImageDraw.Draw(image)
# Draw a black filled box to clear the image.
draw.rectangle((0, 0, width, height), outline=0, fill=0)
# Load default font.
#font = ImageFont.load_default()
#font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 28)
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20)


# Draw text.
draw.text((0, 5), "ENERSYS", font=font, fill=255)
  # Display image.
disp.image(image)
disp.show()
# Pause briefly before drawing next frame.
time.sleep(3)

font = ImageFont.load_default()
# Draw some shapes.
# First define some constants to allow easy resizing of shapes.
padding = -2
top = padding
bottom = height - padding
# Move left to right keeping track of the current x position for drawing shapes.
x = 0
while True:
    # Draw a black filled box to clear the image.
    draw.rectangle((0, 0, width, height), outline=0, fill=0)

    # Shell scripts for system monitoring from here:
    # https://unix.stackexchange.com/questions/119126/command-to-display-memory-usage-disk-usage-and-cpu-load
    cmd = "hostname -I | cut -d' ' -f1"
    IP = subprocess.check_output(cmd, shell=True).decode("utf-8")
    cmd = "top -bn1 | grep load | awk '{printf \"CPU Load: %.2f\", $(NF-2)}'"
    CPU = subprocess.check_output(cmd, shell=True).decode("utf-8")
    cmd = "free -m | awk 'NR==2{printf \"Mem: %.2f%%\", $3*100/$2 }'"
    MemUsage = subprocess.check_output(cmd, shell=True).decode("utf-8")
    cmd = 'df -h | awk \'$NF=="/"{printf "Disk: %s", $5}\''
    Disk = subprocess.check_output(cmd, shell=True).decode("utf-8")
    cmd = "cat /etc/hostname"
    Hostname = subprocess.check_output(cmd, shell=True).decode("utf-8")

    # Write four lines of text.

    draw.text((x, top + 0), "IP: " + IP, font=font, fill=255)
    draw.text((x, top + 8), Hostname, font=font, fill=255)
    draw.text((x, top + 16), CPU, font=font, fill=255)
    draw.text((x, top + 25), f"{Disk} {MemUsage}", font=font, fill=255)

    # Display image.
    disp.image(image)
    disp.show()
    time.sleep(0.1)
EOF_SSD1306

    cat << 'EOF_SERVICE' > /etc/systemd/system/uctronics.service
[Unit]
Description=Uctronics display
After=multi-user.target
[Service]
Type=simple
Restart=always
ExecStart=/usr/bin/python3 /opt/ssd1306_stats.py

[Install]
WantedBy=multi-user.target    
EOF_SERVICE

    sudo systemctl daemon-reload
    sudo systemctl enable uctronics.service
    sudo systemctl start uctronics.service

EOF_UCTRONICS

    log_info "Uctronics Pi Rack installation complete."
}