#!/bin/bash

#
# remove_ssh_host
# This function removes the SSH host key for a given IP address from the known_hosts file.
# Arguments:
#   1. IP_ADDRESS_ARG: The IP address of the host to remove.
#
remove_ssh_host() {
  local IP_ADDRESS_ARG="${1}"

  log_debug "\t- Removing SSH host key for ${IP_ADDRESS_ARG}..."

  # Remove the old host key silently
  ssh-keygen -f "/root/.ssh/known_hosts" -R "${IP_ADDRESS_ARG}" >/dev/null 2>&1

  # Fetch and add the new host key silently
  ssh-keyscan -H "${IP_ADDRESS_ARG}" >>/root/.ssh/known_hosts 2>/dev/null
}

#
# setup_runoverssh
# This function checks if runoverssh is installed and installs it if not.
# It is used to execute commands or scripts on remote hosts over SSH.
#
install_runoverssh() {
  if ! command -v runoverssh &>/dev/null; then
    echo "🔧 Installing runoverssh..."
    pip install runoverssh || {
      log_error "❌ Failed to install runoverssh"
      exit 1
    }
  else
    log_info "✅ runoverssh is already installed."
  fi
}

#
# copy_file_to_host
# This function copies a file from the local machine to a remote host using SSH and scp.
# Arguments:
#   1. ROOT_USER_ARG: The username for SSH login.
#   2. ROOT_PASS_ARG: The password for SSH login.
#   3. HOST_IP_ARG: The IP address of the remote host.
#   4. SOURCE_FILE_ARG: The path to the source file on the local machine.
#   5. TARGET_DIR_ARG: The target directory on the remote host where the file will be copied.
#
copy_file_to_host() {
  local ROOT_USER_ARG="$1"
  local ROOT_PASS_ARG="$2"
  local HOST_IP_ARG="$3"
  local SOURCE_FILE_ARG="$4"
  local TARGET_DIR_ARG="$5"
  local TARGET_FILE
  local TMP_FILE
  
  TARGET_FILE="${TARGET_DIR_ARG}/$(basename ${SOURCE_FILE_ARG})"
  TMP_FILE="/tmp/$(basename ${SOURCE_FILE_ARG}).tmp"

  log_warning "\t\t- Copying file ${SOURCE_FILE_ARG} to the file ${TARGET_FILE} on ${HOST_IP_ARG}..."
  sshpass -p "${ROOT_PASS_ARG}" scp -o StrictHostKeyChecking=no "${SOURCE_FILE_ARG}" "${ROOT_USER_ARG}@${HOST_IP_ARG}:${TMP_FILE}"
  sshpass -p "${ROOT_PASS_ARG}" ssh "${ROOT_USER_ARG}@${HOST_IP_ARG}" "sudo mv \"${TMP_FILE}\" \"${TARGET_FILE}\""
}

#
# reboot
# This function reboots a remote node using SSH.
# Arguments:
#   1. LOGIN_ARG: The username for SSH login.
#   2. PASSWORD_ARG: The password for SSH login.
#   3. NODE_IP_ARG: The IP address of the remote node.
#   4. HOSTNAME_ARG: The hostname of the remote node.
#
reboot() {
  local LOGIN_ARG="${1}"
  local PASSWORD_ARG="${2}"
  local NODE_IP_ARG="${3}"
  local HOSTNAME_ARG="${4}"

  log_debug "\t- Rebooting node ${NODE_IP_ARG} with hostname ${HOSTNAME_ARG}"
  sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${NODE_IP_ARG}" "nohup bash -c 'sudo shutdown -r now'"
  wait_for_device "${HOSTNAME_ARG}"
}

#
# wait_for_device
# This function waits for a remote device to come back online after a reboot.
# Arguments:
#   1. REMOTE_HOST_ARG: The hostname or IP address of the remote device.
#
wait_for_device() {
  local REMOTE_HOST_ARG="${1}"

  # Wait for the device to go down and come back up
  log_debug "\t- Waiting for device ${REMOTE_HOST_ARG} to reboot..."
  while ! ping -c 1 "${REMOTE_HOST_ARG}" &>/dev/null; do
    sleep 5
  done

  # Optional: wait a bit longer to ensure services are up
  sleep 10
  log_debug "\t- ${REMOTE_HOST_ARG} is back online !"
}
