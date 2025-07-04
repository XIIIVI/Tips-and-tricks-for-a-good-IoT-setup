#!/bin/bash

source "../../commons/commons-cli.sh"
source "../../commons/commons-log.sh"
source "../../commons/commons-net.sh"

# === Usage function ===
usage() {
    log_debug "Usage: $0 --login=<LOGIN>"
    log_debug "          --password=<PASSWORD>"
    log_debug "          --volume-name=<VOLUME_NAME> (gulsterdb by default)"
    log_debug "         [--size-gib=<NUMBER> (5 GiB by default)]"
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
    log_debug "SIZE_GIB   : ${SIZE_GIB}"
    log_debug "VOLUME_NAME: ${VOLUME_NAME}"
}

# === Main logic ===
main() {
    MANDATORY_PARAMETER_LIST=("LOGIN" "PASSWORD")

    for ARG in "$@"; do
        case $ARG in
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

    VOLUME_NAME="${VOLUME_NAME:-glusterdb}"

    check_all_mandatory_parameters "${MANDATORY_PARAMETER_LIST[@]}"
    display_settings

    log_info "Looking for orchestrators ..."
    find_devices_by_prefix "orchestrator"

    # === Use the global dictionary outside ===
    local DISK_INDEX=1
    local BRICKS=()

    log_debug "\t📦 Devices found:"
    for HOST in "${!HOSTMAP[@]}"; do
        log_warning "\t\t- Setup GlusterFS server on ${HOST} (${HOSTMAP[$HOST]})"
        execute_script "$HOST" "./create-disk.sh" \
            --login="${LOGIN}" \
            --password="${PASSWORD}" \
            --disk-index="${DISK_INDEX}"

        BRICKS+=("${HOST}:/mnt/glusterfs/brick")
        DISK_INDEX=$((DISK_INDEX + 1))
    done

    log_debug "\t🔗 Creating GlusterFS volume '$VOLUME_NAME'..."

    # Build the brick list string
    BRICK_LIST=$(
        IFS=' '
        echo "${BRICKS[*]}"
    )

    # Assume the first host acts as the GlusterFS volume creator
    FIRST_HOST="${!HOSTMAP[@]:0:1}"

    execute_script "$FIRST_HOST" <<EOF
    gluster volume create ${VOLUME_NAME} replica ${#BRICKS[@]} ${BRICK_LIST} force
    gluster volume start ${VOLUME_NAME}
    gluster volume info ${VOLUME_NAME}
EOF
}

# === Track and report duration ===
time main "$@"
