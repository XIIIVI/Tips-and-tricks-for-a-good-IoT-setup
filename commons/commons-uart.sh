#!/bin/bash

#
# activate_uart
# This function activates UART on the specified host by ensuring the necessary modules and configurations are in place.
# It also disables the serial console to free up the UART for other uses.
# Arguments:
#   1. ROOT_USER_ARG: The username for SSH login.
#   2. ROOT_PASS_ARG: The password for SSH login.
#   3. HOST_IP_ARG: The IP address of the host where I2C should be activated.
#
activate_uart() {
    local ROOT_USER_ARG="$1"
    local ROOT_PASS_ARG="$2"
    local HOST_IP_ARG="$3"

    log_debug "\t- Activating UART on $HOST_IP_ARG ..."

    log_warning "\t\t- Activating the UART"
    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" "sed -i '/^enable_uart=/d' /boot/config.txt"
    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" "echo 'enable_uart=1' | sudo tee -a /boot/config.txt"

    log_warning "\t\t- Disabling the serial console"
    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" "sudo sed -i 's|^\\(console=serial0,115200 \\)\\?\\(console=tty1 \\)\\?||' /boot/cmdline.txt"
}