#!/bin/bash

source "../../commons/commons-cli.sh"
source "../../commons/commons-log.sh"
source "../../commons/commons-net.sh"

# === Usage function ===
usage() {
    log_debug "Usage: $0 --login=<LOGIN>"
    log_debug "          --password=<PASSWORD>" 
    log_debug "         [--disk_label=<MYDISK> (default: database)]"
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
    log_debug "DEVICE    : ${DEVICE}"
    log_debug "DISK_LABEL: ${DISK_LABEL}"
    log_debug "SIZE_GIB  : ${SIZE_GIB}"
}

# === Main logic ===
main() {
    MANDATORY_PARAMETER_LIST=("LOGIN" "PASSWORD")

    for ARG in "$@"; do
        case $ARG in
        --disk-label=*)
            DISK_LABEL="${ARG#*=}"
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
        *)
            echo "Unknown argument: $ARG"
            usage
            ;;
        esac
    done

    check_all_mandatory_parameters "${MANDATORY_PARAMETER_LIST[@]}"
    display_settings

    DISK_LABEL="${DISK_LABEL:-database}"  # Default label if not set

    log_info "Looking for orchestrators ..."
    find_devices_by_prefix "orchestrator"

    # === Use the global dictionary outside ===
    log_debug "\t📦 Devices found:"
    for HOST in "${!HOSTMAP[@]}"; do
        log_warning "\t\t- Creation a disk partition ${DISK_LABEL} on $HOST (${HOSTMAP[$HOST]})"
        execute_script "$HOST" "./create-disk.sh" \
            --disk-label="$DISK_LABEL" \
            --size-gib="${SIZE_GIB}" \
            --login="${LOGIN}" \
            --password="${PASSWORD}"
    done
}

# === Track and report duration ===
time main "$@"
