#!/bin/bash

source "../../commons/commons-cli.sh"
source "../../commons/commons-log.sh"
source "../../commons/commons-net.sh"
source "../../commons/commons-ssh.sh"

# === Usage function ===
usage() {
    log_debug "Usage: $0 --login=<LOGIN>"
    log_debug "          --password=<PASSWORD>"
    log_debug "         [--manager-hostname-prefix=<PREFIX> (orchestrator by default)]"
    log_debug "         [--size-gib=<NUMBER> (5 GiB by default)]"
    log_debug "         [--volume-name=<VOLUME_NAME> (gulsterdb by default)"]
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
    log_debug "SIZE_GIB               : ${SIZE_GIB}"
    log_debug "VOLUME_NAME            : ${VOLUME_NAME}"
}

# === Main logic ===
main() {
    MANDATORY_PARAMETER_LIST=("LOGIN" "PASSWORD")

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
        --size-gib=*)
            SIZE_GIB="${ARG#*=}"
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
    local VOLUME_NAME="${VOLUME_NAME:-glusterdb}"
    local DISK_INDEX=1
    local BRICKS=()

    check_all_mandatory_parameters "${MANDATORY_PARAMETER_LIST[@]}"
    display_settings

    log_info "Installing required packages"
    apt-get install -qq -y dnsutils

    log_info "Looking for managers with prefix ${MANAGER_HOSTNAME_PREFIX} ..."
    for i in {1..254}; do
        IP="$SUBNET.$i"
        (
            if ping -c 1 -W 1 "$IP" &>/dev/null; then
                HOSTNAME=$(dig +short -x "$IP" | sed 's/\.$//')
                if [[ "$HOSTNAME" =~ ${MANAGER_HOSTNAME_PREFIX} ]]; then
                    log_warning "\t\t- Setup GlusterFS server on ${HOST} (${IP})"
                    execute_script "$HOST" \
                        --login="${LOGIN}" \
                        --password="${PASSWORD}" \
                        "./create-disk.sh" \
                        --disk-index="${DISK_INDEX}"

                    BRICKS+=("${HOST}:/mnt/glusterfs/brick")
                    DISK_INDEX=$((DISK_INDEX + 1))
                fi
            fi
        ) &
    done

    if [[ ${#BRICKS[@]} -eq 0 ]]; then
        log_error "❌ No devices found with prefix ${MANAGER_HOSTNAME_PREFIX}. Aborting."
        exit 1
    else
        log_debug "\t📦 Devices found:"
        log_debug "\t🔗 Creating GlusterFS volume '$VOLUME_NAME'..."

        # Build the brick list string
        BRICK_LIST=$(
            IFS=' '
            echo "${BRICKS[*]}"
        )
        gluster volume create "${VOLUME_NAME}" replica "${#BRICKS[@]}" "${BRICK_LIST}" force
        gluster volume start "${VOLUME_NAME}"
        gluster volume info "${VOLUME_NAME}"
    fi
}

# === Track and report duration ===
time main "$@"
