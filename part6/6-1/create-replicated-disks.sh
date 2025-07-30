#!/bin/bash

source "../../commons/commons-cli.sh"
source "../../commons/commons-file.sh"
source "../../commons/commons-log.sh"
source "../../commons/commons-net.sh"
source "../../commons/commons-ssh.sh"

# === Usage function ===
display_help() {
    log_debug "Usage: $0 --login=<LOGIN>"
    log_debug "          --password=<PASSWORD>"
    log_debug "          --subnet=<xxx.xxx.xxx>"
    log_debug "         [--manager-hostname-prefix=<PREFIX> (orchestrator by default)]"
    log_debug "         [--volume-name=<VOLUME_NAME> (gfs by default)"]
    log_debug
    log_debug "Available devices:"
    lsblk -dno NAME,SIZE,MODEL
    exit 1
}

#
# display_settings
#
display_settings() {
    log_debug "S E T T I N G S"
    log_debug "MANAGER_HOSTNAME_PREFIX: ${MANAGER_HOSTNAME_PREFIX}"
    log_debug "SUBNET                 : ${SUBNET}"
    log_debug "VOLUME_NAME            : ${VOLUME_NAME}"
}

#
# main
#
main() {
    MANDATORY_PARAMETER_LIST=("LOGIN" "PASSWORD" "SUBNET")

    for ARG in "$@"; do
        case $ARG in
        --manager-hostname-prefix=*)
            MANAGER_HOSTNAME_PREFIX="${ARG#*=}"
            shift
            ;;
        --login=*)
            LOGIN="${ARG#*=}"
            shift
            ;;
        --password=*)
            PASSWORD="${ARG#*=}"
            shift
            ;;
        --subnet=*)
            SUBNET="${ARG#*=}"
            if [[ ! "$SUBNET" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                log_error "❌ Invalid subnet format. Use xxx.xxx.xxx."
                exit 1
            fi
            shift
            ;;
        --volume-name=*)
            VOLUME_NAME="${ARG#*=}"
            shift
            ;;
        *)
            echo "Unknown argument: $ARG"
            usage
            ;;
        esac
    done

    local MANAGER_HOSTNAME_PREFIX="${MANAGER_HOSTNAME_PREFIX:-orchestrator}"
    local VOLUME_NAME="${VOLUME_NAME:-gfs}"
    DISCOVERED_HOSTNAME_LISt=()
    COUNTER=1

    check_all_mandatory_parameters "${MANDATORY_PARAMETER_LIST[@]}"
    display_settings

    log_info "Installing required packages"
    apt-get install -qq -y dnsutils

    log_info "Looking for managers with prefix ${MANAGER_HOSTNAME_PREFIX} in the subnet ${SUBNET} ..."
    COUNTER=1

    for i in {1..254}; do
        IP="${SUBNET}.${i}"

        # Print current IP being checked (overwrites the same line)
        log_progress_bar "🔍 Testing ${IP} ..." "$((i + 1))" 254

        if ping -c 1 -W 1 "$IP" &>/dev/null; then
            HOSTNAME=$(dig +short -x "$IP" | sed 's/\.$//')

            if [[ "$HOSTNAME" =~ ${MANAGER_HOSTNAME_PREFIX} ]]; then
                log_progress_bar "🔍 Testing ${IP} ..." "$((i + 1))" 254 " => Found the candidate ${HOSTNAME} (${IP})"

                DISCOVERED_HOSTNAME_LISt+=("${HOSTNAME}")
                
                COUNTER=$((COUNTER + 1))
            fi
        fi
    done

    setup_replicated_volumes \
        "${LOGIN}" \
        "${PASSWORD}" \
        "${VOLUME_NAME}" \
        "${DISCOVERED_HOSTNAME_LISt[@]}"
}

# === Track and report duration ===
time main "$@"
