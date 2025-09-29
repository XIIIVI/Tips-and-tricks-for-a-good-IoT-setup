#!/usr/bin/env bash

# ============================================================
#  Project:   commons-grafana.sh
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

set -eo pipefail

# --------------------------------------
# Retry helper
# --------------------------------------
retry_cmd() {
  local retries=$1; shift
  local delay=$1; shift
  local count=0
  until "$@"; do
    exit_code=$?
    count=$((count + 1))
    if [ $count -lt $retries ]; then
      log_warning "⚠️ Command failed (exit $exit_code). Retrying in ${delay}s... [${count}/${retries}]"
      sleep "$delay"
    else
      log_error "❌ Command failed after ${retries} attempts: $*"
      return $exit_code
    fi
  done
  return 0
}

#---------------------------------------------
# Function: get_prefix
# Returns the prefix based on folder name.
# Parameters:
#   FOLDER_ARG - folder name.
# Returns:
#   Echoes the prefix string (may be empty).
#---------------------------------------------
get_prefix() {
  local FOLDER_ARG="$1"
  case "${FOLDER_ARG}" in
    alert-contact-points) echo "acp_" ;;
    alert-notification-templates) echo "ant_" ;;
    alert-rules) echo "ar_" ;;
    dashboards) echo "dash_" ;;
    datasources) echo "ds_" ;;
    folders) echo "dir_" ;;
    library-elements) echo "lib" ;;   # Note: "lib" has no underscore
    *) echo "" ;;
  esac
}

#---------------------------------------------
# Function: to_snake_case
# Converts a string to snake_case lowercase.
# Parameters:
#   STRING_ARG - input string.
# Returns:
#   Echoes snake_case string.
#---------------------------------------------
to_snake_case() {
  local STRING_ARG="$1"
  echo "${STRING_ARG}" \
    | sed -E 's/[^a-zA-Z0-9]+/_/g' \
    | sed -E 's/_+/_/g' \
    | sed -E 's/^_|_$//g' \
    | tr '[:upper:]' '[:lower:]'
}

#---------------------------------------------
# Function: strip_any_leading_prefixes
# Removes all leading occurrences of any known prefixes from STRING_ARG.
# This handles both folder-mapped prefixes (e.g., ds_, dir_, dash_) and legacy
# human-readable variants (e.g., dashboard_, datasource_, folder_, lib).
# Parameters:
#   STRING_ARG - input snake_case string to strip.
# Returns:
#   Echoes the stripped string (core name).
#---------------------------------------------
strip_any_leading_prefixes() {
  local STRING_ARG="$1"

  # Known leading prefixes to strip repeatedly (ordered short-first is fine)
  local KNOWN_PREFIXES=(
    "acp_" "ant_" "ar_" "dash_" "ds_" "dir_" "lib" "lib_"
    "dashboard_" "datasource_" "folder_" "library_element_"
    "alert_rule_" "alert_contact_point_" "alert_notification_template_"
  )

  local STRIPPED="${STRING_ARG}"
  local CHANGED="yes"
  while [[ "${CHANGED}" == "yes" && -n "${STRIPPED}" ]]; do
    CHANGED="no"
    for PFX in "${KNOWN_PREFIXES[@]}"; do
      if [[ "${STRIPPED}" == ${PFX}* ]]; then
        STRIPPED="${STRIPPED#${PFX}}"
        CHANGED="yes"
        break
      fi
    done
  done

  echo "${STRIPPED}"
}

#---------------------------------------------
# Function: normalize_uid
# Normalizes spec.uid and metadata.name, and renames the file.
# Strategy:
#   - BASE_NAME from metadata.name or spec.title.
#   - SNAKE_NAME = snake_case(BASE_NAME).
#   - CORE_NAME = SNAKE_NAME with all known leading prefixes stripped.
#   - If existing NAME starts with expected PREFIX_ARG:
#       * Compare REMAINDER (NAME minus PREFIX_ARG) with CORE_NAME.
#       * If equal → no change.
#       * If not equal → recompute NEW_UID = PREFIX_ARG + CORE_NAME (or hash if >40).
#   - If NAME doesn't start with expected prefix → compute NEW_UID = PREFIX_ARG + CORE_NAME (or hash if >40).
#   - Update JSON (spec.uid, metadata.name), rename file to SNAKE_NAME.json,
#     and replace old UID occurrences across GRIZZLY_BASEDIR_ARG.
# Parameters:
#   FILE_ARG - path to JSON file.
#   PREFIX_ARG - expected prefix string.
#   GRIZZLY_BASEDIR_ARG - base directory for cross-file UID replacements.
# Returns:
#   Updates the JSON file in place and renames the file.
#---------------------------------------------
normalize_uid() {
  local FILE_ARG="${1}"
  local PREFIX_ARG="${2}"
  local GRIZZLY_BASEDIR_ARG="${3}"

  local NAME
  NAME=$(jq -r '.metadata.name // empty' "${FILE_ARG}")
  local UID
  UID=$(jq -r '.spec.uid // empty' "${FILE_ARG}")

  if [[ -z "${NAME}" || -z "${UID}" ]]; then
    # Delete file if either NAME or UID is empty
    log_warning "[DELETED] File: ${FILE_ARG} (missing .metadata.name or .spec.uid)"
    rm -f "${FILE_ARG}"
  else
    local TITLE
    TITLE=$(jq -r '.spec.title // empty' "${FILE_ARG}")
    local BASE_NAME="${NAME:-$TITLE}"

    # Compute snake_case and strip any leading known prefixes
    local SNAKE_NAME
    SNAKE_NAME=$(to_snake_case "${BASE_NAME}")

    local CORE_NAME
    CORE_NAME=$(strip_any_leading_prefixes "${SNAKE_NAME}")

    # If stripping removed everything, fallback to short hash as core
    if [[ -z "${CORE_NAME}" ]]; then
      CORE_NAME=$(echo -n "${BASE_NAME}" | sha1sum | cut -c1-12)
    fi

    local NEW_UID=""
    local NEED_UPDATE="yes"

    # Validate existing NAME if it already has the expected prefix
    if [[ -n "${PREFIX_ARG}" && "${NAME}" == ${PREFIX_ARG}* ]]; then
      local REMAINDER="${NAME#${PREFIX_ARG}}"
      if [[ "${REMAINDER}" == "${CORE_NAME}" ]]; then
        NEED_UPDATE="no"
      else
        local CANDIDATE="${PREFIX_ARG}${CORE_NAME}"
        if [[ ${#CANDIDATE} -le 40 ]]; then
          NEW_UID="${CANDIDATE}"
        else
          local HASH
          HASH=$(echo -n "${BASE_NAME}" | sha1sum | cut -c1-12)
          NEW_UID="${PREFIX_ARG}${HASH}"
        fi
      fi
    else
      # No matching prefix → compute fresh UID
      local CANDIDATE="${PREFIX_ARG}${CORE_NAME}"
      if [[ ${#CANDIDATE} -le 40 ]]; then
        NEW_UID="${CANDIDATE}"
      else
        local HASH
        HASH=$(echo -n "${BASE_NAME}" | sha1sum | cut -c1-12)
        NEW_UID="${PREFIX_ARG}${HASH}"
      fi
    fi

    if [[ "${NEED_UPDATE}" == "yes" && -n "${NEW_UID}" && "${NAME}" != "${NEW_UID}" ]]; then
      local TMPFILE
      TMPFILE=$(mktemp)
      jq --arg newuid "${NEW_UID}" \
         --arg newname "${NEW_UID}" \
         '.spec.uid=$newuid | .metadata.name=$newname' \
         "${FILE_ARG}" > "${TMPFILE}"
      mv "${TMPFILE}" "${FILE_ARG}"

      local DIRNAME
      DIRNAME=$(dirname "${FILE_ARG}")
      local NEW_FILE="${DIRNAME}/${SNAKE_NAME}.json"
      mv "${FILE_ARG}" "${NEW_FILE}"

      if [[ -n "${NAME}" ]]; then
        # Replace old UID occurrences across all files
        grep -rl -- "${NAME}" "${GRIZZLY_BASEDIR_ARG}" | xargs sed -i "s/${NAME}/${NEW_UID}/g"
      fi

      # Logging
      log_info "[UPDATED] File: ${NEW_FILE}"
      log_info "          Old UID: ${NAME}"
      log_info "          New UID: ${NEW_UID}"
    else
      log_warning "[SKIPPED] File: ${FILE_ARG} (already normalized)"
    fi
  fi
}

#---------------------------------------------
# Function: process_grizzly_resources
# Processes all JSON files (Grizzly's resources) in a folder using its mapped prefix.
# Parameters:
#   FOLDER_ARG - folder path.
#   GRIZZLY_BASEDIR_ARG - base directory for cross-file UID replacements.
#---------------------------------------------
process_grizzly_resources() {
  local FOLDER_ARG="${1}"
  local GRIZZLY_BASEDIR_ARG="${2}"
  local PREFIX
  PREFIX=$(get_prefix "$(basename "${FOLDER_ARG}")")

  if [[ -n "${PREFIX}" ]]; then
    find "${FOLDER_ARG}" -type f -name "*.json" | while read -r FILE; do
      normalize_uid "${FILE}" "${PREFIX}" "${GRIZZLY_BASEDIR_ARG}"
    done
  fi
}

# ---------------------------------------------
# Function: install_grizzly
# Installs grizzly (grr) if missing, along with Go if needed.
# ---------------------------------------------
install_grizzly() {
    local HOST_ARCH_ARG="${1}"

    log_info "📦 Installing Grizzly"

    if ! command -v grr >/dev/null 2>&1; then
      log_warning "\t⚠️ grr not found. Attempting installation via 'go install'..."
  
      if ! command -v go >/dev/null 2>&1; then
        log_warning "Go not found. Installing for host arch ${HOST_ARCH_ARG}..."
        GO_VERSION="1.22.7"
        case "${HOST_ARCH_ARG}" in
          amd64|arm64) GO_TARBALL="go${GO_VERSION}.linux-${HOST_ARCH_ARG}.tar.gz" ;;
          armv7)       GO_TARBALL="go${GO_VERSION}.linux-armv6l.tar.gz" ;;
          *) log_error "\t❌ Unsupported host arch for Go: ${HOST_ARCH_ARG}"; exit 1 ;;
        esac
        GO_URL="https://go.dev/dl/${GO_TARBALL}"
        TMP_DIR="$(mktemp -d)"
        pushd "${TMP_DIR}" >/dev/null
    
        # Retry curl download
        retry_cmd 3 5 curl -fsSLO "${GO_URL}" || exit 1
    
        sudo tar -C /usr/local -xzf "${GO_TARBALL}"
        popd >/dev/null
        rm -rf "${TMP_DIR}"
        export PATH="/usr/local/go/bin:${PATH}"
      fi
  
      # Respect GOBIN; otherwise use GOPATH/bin or default ~/go/bin
      GOBIN_DIR="${GOBIN:-}"
      if [[ -z "${GOBIN_DIR}" ]]; then
        GOPATH_DIR="${GOPATH:-$HOME/go}"
        GOBIN_DIR="${GOPATH_DIR}/bin"
      fi

      mkdir -p "${GOBIN_DIR}"
  
      # Retry grr install
      retry_cmd 3 5 env GO111MODULE=on GOBIN="${GOBIN_DIR}" go install github.com/grafana/grizzly/cmd/grr@latest || exit 1
  
      export PATH="${GOBIN_DIR}:${PATH}"
      if ! command -v grr >/dev/null 2>&1; then
        log_error "❌ Failed to install grr after retries."
        exit 1
      fi
    fi
}

# ---------------------------------------------
# Function: install_and_configure_grafana_builder
# Installs and runs a Grafana container for building the custom image.
# Parameters:
#   TARGET_ARCH_ARG - Target architecture (e.g., amd64, arm64, armv7).
#   VERSION_NUMBER_ARG - Grafana version (e.g., 12.2.0).
#   GRAFANA_HOST_ARG - Hostname or IP for Grafana access.
#   GRAFANA_PORT_ARG - Host port to map to Grafana (e.g., 3000).
#   ADMIN_PASSWD_ARG - Admin password to set.
#   GRAFANA_CONTAINER_ARG - Name of the Grafana Docker container.
# Exports:
#   BUILDER_SA_TOKEN - Service account token valid for 1 day.
# ---------------------------------------------
install_and_configure_grafana_builder() {
    local TARGET_ARCH_ARG="${1}"
    local VERSION_NUMBER_ARG="${2}"
    local GRAFANA_HOST_ARG="${3}"
    local GRAFANA_PORT_ARG="${4}"
    local ADMIN_PASSWD_ARG="${5}"
    local GRAFANA_CONTAINER_ARG="${6}"    
    # Names & tags
    local GRAFANA_IMAGE="grafana/grafana:${VERSION_NUMBER_ARG}"
    local GRAFANA_URL="http://${GRAFANA_HOST_ARG}:${GRAFANA_PORT_ARG}"

    # --------------------------------------
    # Pull and run Grafana
    # --------------------------------------
    log_info "⤵️ Pulling Grafana image ${GRAFANA_IMAGE} for linux/${TARGET_ARCH_ARG}..."
    docker pull --platform "linux/${TARGET_ARCH_ARG}" "${GRAFANA_IMAGE}"

    # Stop/remove if exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${GRAFANA_CONTAINER_ARG}\$"; then
      log_warning "\t- 🚮 Container ${GRAFANA_CONTAINER_ARG} exists. Removing..."
      docker rm -f "${GRAFANA_CONTAINER_ARG}" >/dev/null 2>&1 || true
    fi

    log_debug "\t- ▶️ Starting Grafana container ${GRAFANA_CONTAINER_ARG}..."
    docker run -d --name "${GRAFANA_CONTAINER_ARG}" \
      -p "${GRAFANA_PORT_ARG}:3000" \
      -e "GF_SECURITY_ADMIN_PASSWORD=${ADMIN_PASSWD_ARG}" \
      --platform "linux/${TARGET_ARCH_ARG}" \
      "${GRAFANA_IMAGE}" >/dev/null

    # Wait for Grafana readiness
    log_debug "\t- 🕗 Waiting for Grafana to be ready at ${GRAFANA_URL}..."
    for i in {1..60}; do
      if curl -fsS "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
        break
      fi
      sleep 2
      if [[ $i -eq 60 ]]; then
        log_error "❌ Grafana did not become ready in time."
        exit 1
      fi
    done

    # --------------------------------------
    # Ensure admin password (explicit API change)
    # --------------------------------------
    # Even though GF_SECURITY_ADMIN_PASSWORD initialized it, explicitly set via API to be sure.
    log_debug "\t- Setting admin password via API..."
    curl -fsS -X PUT "${GRAFANA_URL}/api/admin/users/1/password" \
      -u "admin:${ADMIN_PASSWD_ARG}" \
      -H 'Content-Type: application/json' \
      -d "{\"password\":\"${ADMIN_PASSWD_ARG}\"}" >/dev/null

    # --------------------------------------
    # Create 1-day service account and token
    # --------------------------------------
    log_debug "\t- Creating service account and token valid for 1 day..."
    local SA_NAME="grizzly-sa-$(date +%s)"
    # Create Service Account
    local SA_ID=$(
      curl -fsS -X POST "${GRAFANA_URL}/api/serviceaccounts" \
        -u "admin:${ADMIN_PASSWD_ARG}" \
        -H 'Content-Type: application/json' \
        -d "{\"name\":\"${SA_NAME}\",\"role\":\"Admin\"}" | jq -r '.id'
    )
    if [[ -z "${SA_ID}" || "${SA_ID}" == "null" ]]; then
      log_error "❌ Failed to create service account."
      exit 1
    fi

    # Create Service Account token (1 day = 86400 seconds)
    local BUILDER_SA_TOKEN=$(
      curl -fsS -X POST "${GRAFANA_URL}/api/serviceaccounts/${SA_ID}/tokens" \
        -u "admin:${ADMIN_PASSWD_ARG}" \
        -H 'Content-Type: application/json' \
        -d "{\"name\":\"${SA_NAME}-token\",\"role\":\"Admin\",\"secondsToLive\":86400}" | jq -r '.key'
    )
    if [[ -z "${BUILDER_SA_TOKEN}" || "${BUILDER_SA_TOKEN}" == "null" ]]; then
      log_error "❌ Failed to create service account token."
      exit 1
    fi

    # Export for later steps within this shell
    export BUILDER_SA_TOKEN
}

# ---------------------------------------------
# Function: export_grafana_resources
# Uses grizzly (grr) to export Grafana resources to GRIZZLY_BASEDIR_ARG.
# Parameters:
#   GRAFANA_URL_ARG - URL of the Grafana instance.
#   SA_TOKEN_ARG - Service account token for authentication.
#   GRIZZLY_BASEDIR_ARG - Base directory to store exported resources.
# ---------------------------------------------
export_grafana_resources() {
    local GRAFANA_URL_ARG="${1}"
    local SA_TOKEN_ARG="${2}"
    local GRIZZLY_BASEDIR_ARG="${3}"

    log_info "📦 Exporting Grafana resources (${GRAFANA_URL_ARG}) using Grizzly"
    log_debug "\t- Configuring Grizzly context..."
    grr config set grafana.url "${GRAFANA_URL_ARG}"
    grr config set grafana.token "${SA_TOKEN_ARG}"
    grr config set targets Datasource,DashboardFolder,LibraryElement,Dashboard,AlertRuleGroup,AlertNotificationPolicy,AlertContactPoint,AlertNotificationTemplate
    grr config set output-format json

    log_debug "\t- Exporting resources to ${GRIZZLY_BASEDIR_ARG}..."
    grr pull "${GRIZZLY_BASEDIR_ARG}"
    tree "${GRIZZLY_BASEDIR_ARG}"
}


# ---------------------------------------------
# Function: import_grafana_resources
# Uses grizzly (grr) to import Grafana resources from GRIZZLY_BASEDIR_ARG.
# Parameters:
#   GRAFANA_URL_ARG - URL of the Grafana instance.
#   SA_TOKEN_ARG - Service account token for authentication.
#   GRIZZLY_BASEDIR_ARG - Base directory to load exported resources.
# ---------------------------------------------
import_grafana_resources() {
    local GRAFANA_URL_ARG="${1}"
    local SA_TOKEN_ARG="${2}"
    local GRIZZLY_BASEDIR_ARG="${3}"

    log_info "📦 Importing Grafana resources from ${GRIZZLY_BASEDIR_ARG} into ${GRAFANA_URL_ARG}"

    if [[ ! -d "${GRIZZLY_BASEDIR_ARG}" ]]; then
      log_error "❌ Grizzly base directory not found: ${GRIZZLY_BASEDIR_ARG}"
      exit 1
    fi

    log_debug "\t- Configuring Grizzly context..."
    grr config set grafana.url "${GRAFANA_URL_ARG}"
    grr config set grafana.token "${SA_TOKEN_ARG}"
    grr config set targets Datasource,DashboardFolder,LibraryElement,Dashboard,AlertRuleGroup,AlertNotificationPolicy,AlertContactPoint,AlertNotificationTemplate
    grr config set output-format json

    log_debug "\t- Normalizing UIDs in ${GRIZZLY_BASEDIR_ARG}..."
    while IFS= read -r -d '' DIR; do
         log_warning "\t\t- Processing folder: ${DIR}"
         process_grizzly_resources "${DIR}" "${GRIZZLY_BASEDIR_ARG}"
    done < <(find "${GRIZZLY_BASEDIR_ARG}" -type d -print0)
    
    log_debug "\t- Importing resources to ${GRIZZLY_BASEDIR_ARG}..."
    grr push "${GRIZZLY_BASEDIR_ARG}"
}