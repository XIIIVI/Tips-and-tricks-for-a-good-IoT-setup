#!/bin/bash

#
# remove_ssh_host
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
# execute_command
#
execute_command() {
  local USER_ARG="$1"
  local PASSWORD_ARG="$2"
  local TARGET_ARG="$3"
  local CMD="$4"

  install_runoverssh

  if [[ -z "$TARGET_ARG" || -z "$USER_ARG" || -z "$PASSWORD_ARG" || -z "$CMD" ]]; then
    log_error "Usage: execute_command <target> <login> <password> <command>"
    return 1
  fi

  log_info "🚀 Executing remote command on $TARGET_ARG..."
  runoverssh -h "$TARGET_ARG" -l "$USER_ARG" -p "$PASSWORD_ARG" -c "$CMD"
}

#
# execute_script
#
execute_script() {
  local TARGET_ARG="$1"
  local USER_ARG="$2"
  local PASSWORD_ARG="$3"
  local SCRIPT_PATH_ARG="$4"
  shift 4
  local SCRIPT_ARGS=("$@")

  install_runoverssh

  if [[ -z "$TARGET_ARG" || -z "$USER_ARG" || -z "$PASSWORD_ARG" || -z "$SCRIPT_PATH_ARG" ]]; then
    log_error "Usage: execute_script <target> <login> <password> <script_path>"
    return 1
  fi

  if [[ ! -f "$SCRIPT_PATH_ARG" ]]; then
    log_error "❌ Local script not found: $SCRIPT_PATH_ARG"
    return 1
  fi

  log_info "📄 Uploading and executing script on $TARGET_ARG..."
  runoverssh -h "$TARGET_ARG" -l "$USER_ARG" -p "$PASSWORD_ARG" -f "$SCRIPT_PATH_ARG" -- "${SCRIPT_ARGS[@]}"
}

#
# copy_file_to_host
#
copy_file_to_host() {
  local ROOT_USER_ARG="$1"
  local ROOT_PASS_ARG="$2"
  local HOST_IP_ARG="$3"
  local SOURCE_FILE_ARG="$4"
  local TARGET_DIR_ARG="$5"

  log_warning "\t\t- Copying file ${SOURCE_FILE_ARG} to ${TARGET_DIR_ARG} on ${HOST_IP_ARG}..."
  sshpass -p "${ROOT_PASS_ARG}" scp -o StrictHostKeyChecking=no "${SOURCE_FILE_ARG}" "${ROOT_USER_ARG}@${HOST_IP_ARG}:/tmp/$(basename ${SOURCE_FILE_ARG}).tmp"
  sshpass -p "${ROOT_PASS_ARG}" ssh "${ROOT_USER_ARG}@${HOST_IP_ARG}" sudo mv /tmp/"$(basename ${SOURCE_FILE_ARG}).tmp" "${TARGET_DIR_ARG}/$(basename ${SOURCE_FILE_ARG})"
}

#
# reboot
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
  log_warning "\t- ${REMOTE_HOST_ARG} is back online !"
}
