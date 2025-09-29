#!/bin/bash

# ============================================================
#  Project:   commons-net.sh
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
# check_hostname_conflict
# This function checks if a given hostname conflicts with the local machine or other hosts on the LAN.
# Arguments:
#   1. HOSTNAME_TO_CHECK_ARG: The hostname to check for conflicts.
#
check_hostname_conflict() {
  local HOSTNAME_TO_CHECK_ARG="$1"

  if [[ -z "$HOSTNAME_TO_CHECK_ARG" ]]; then
    return 1
  fi

  local LOCAL_IPS RESOLVED_IP
  LOCAL_IPS=$(hostname -I)
  RESOLVED_IP=$(getent hosts "$HOSTNAME_TO_CHECK_ARG" | awk '{ print $1 }')

  # Hostname not found on LAN
  if [[ -z "$RESOLVED_IP" ]]; then
    return 2
  # Hostname points to this machine.  
  elif [[ $LOCAL_IPS =~ $RESOLVED_IP ]]; then
    return 0
  # Hostname is already in use by a different host on the LAN
  else
    return 3
  fi
}

#
# set_hostname
# This function sets the hostname on a remote machine.
# Arguments:
#   1. LOGIN_ARG: The username for SSH login.
#   2. PASSWORD_ARG: The password for SSH login.
#   3. HOSTNAME_ARG: The new hostname to set.
#   4. NODE_IP_ARG: The IP address of the remote node.
#
set_hostname() {
  local LOGIN_ARG="${1}"
  local PASSWORD_ARG="${2}"
  local HOSTNAME_ARG="${3}"
  local NODE_IP_ARG="${4}"

  log_debug "\t- Setting hostname to ${HOSTNAME_ARG} on node ${NODE_IP_ARG}"
  sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${NODE_IP_ARG}" "sudo sed -i 's/${DEFAULT_HOSTNAME}/${HOSTNAME_ARG}/' /etc/hosts"
  sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${NODE_IP_ARG}" "sudo hostnamectl set-hostname ${HOSTNAME_ARG}"
  sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${NODE_IP_ARG}" "sudo hostname ${HOSTNAME_ARG}"
}
