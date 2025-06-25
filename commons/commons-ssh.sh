#!/bin/bash

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
  local USER_ARG="$1"
  local PASSWORD_ARG="$2"
  local TARGET_ARG="$3"
  local SCRIPT_PATH_ARG="$4"
  shift 4
  local SCRIPT_ARGS=("$@")

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

  sshpass -p "$ROOT_PASS_ARG" scp -o StrictHostKeyChecking=no "${SOURCE_FILE_ARG}" "${ROOT_USER_ARG}@${HOST_IP_ARG}:/tmp/"
  sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_INDEX}" sudo mv /tmp/"$(basename \"${SOURCE_FILE_ARG}\")" "${TARGET_DIR_ARG}"
}
