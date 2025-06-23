#!/bin/bash

# === Function: setup_runoverssh ===
install_runoverssh() {
  if ! command -v runoverssh &> /dev/null; then
    echo "🔧 Installing runoverssh..."
    pip install runoverssh || { log_error "❌ Failed to install runoverssh"; exit 1; }
  else
    log_info "✅ runoverssh is already installed."
  fi
}

# === Function: execute_command ===
execute_command() {
  local TARGET="$1"
  local USER="$2"
  local PASSWORD="$3"
  local CMD="$4"

  if [[ -z "$TARGET" || -z "$USER" || -z "$PASSWORD" || -z "$CMD" ]]; then
    log_error "Usage: execute_command <target> <login> <password> <command>"
    return 1
  fi

  log_info "🚀 Executing remote command on $TARGET..."
  runoverssh -h "$TARGET" -l "$USER" -p "$PASSWORD" -c "$CMD"
}

# === Function: execute_script ===
execute_script() {
  local TARGET="$1"
  local USER="$2"
  local PASSWORD="$3"
  local SCRIPT_PATH="$4"
  shift 4
  local SCRIPT_ARGS=("$@")

  if [[ -z "$TARGET" || -z "$USER" || -z "$PASSWORD" || -z "$SCRIPT_PATH" ]]; then
    log_error "Usage: execute_script <target> <login> <password> <script_path>"
    return 1
  fi

  if [[ ! -f "$SCRIPT_PATH" ]]; then
    log_error "❌ Local script not found: $SCRIPT_PATH"
    return 1
  fi

  log_info "📄 Uploading and executing script on $TARGET..."
  runoverssh -h "$TARGET" -l "$USER" -p "$PASSWORD" -f "$SCRIPT_PATH" -- "${SCRIPT_ARGS[@]}"
}
