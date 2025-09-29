#!/bin/bash

# ============================================================
#  Project:   commons-uart.sh
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
    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" "sudo sed -i '/^enable_uart=/d' /boot/config.txt"
    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" "echo 'enable_uart=1' | sudo tee -a /boot/config.txt"

    log_warning "\t\t- Disabling the serial console"
    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no "$ROOT_USER_ARG@$HOST_IP_ARG" "sudo sed -i 's|^\\(console=serial0,115200 \\)\\?\\(console=tty1 \\)\\?||' /boot/cmdline.txt"
}