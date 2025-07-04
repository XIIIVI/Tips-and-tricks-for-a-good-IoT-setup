#!/bin/bash

source "../../commons/commons-cli.sh"
source "../../commons/commons-log.sh"
source "../../commons/commons-net.sh"

# === Usage function ===
display_help() {
    log_debug "Usage: $0 --login=<LOGIN>"
    log_debug "          --password=<PASSWORD>"
    log_debug "          --subnet=<xxx.xxx.xxx>"
    log_debug "         [--manager-hostname-prefix=<PREFIX> (orchestrator by default)]"
    log_debug "         [--size-gib=<NUMBER> (1 GiB by default)]"
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
    log_debug "SIZE_MIB               : ${SIZE_MIB}"
    log_debug "SUBNET                 : ${SUBNET}"
    log_debug "VOLUME_NAME            : ${VOLUME_NAME}"
}

#
# create_xfs_partition
#
create_xfs_partition() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local IP_ADDRESS_ARG="${3}"
    local SIZE_MIB_ARG="${4}"
    local DISK_INDEX_ARG="${5}"
    local PARTITION="${DISK}${DISK_INDEX_ARG}"
    local MOUNT_POINT="/mnt/gluster"
    local DISK=$(lsblk -b -l -o NAME,SIZE,TYPE | awk '$3 == "part" {print $1, $2}' | sort -k2 -nr | head -n1 | awk '{print $1}')

    log_info " - 🔧 Creating partition..."
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "(\
        echo n                 # new partition \
        echo p                 # primary \
        echo 1                 # partition number \
        echo                   # default first sector \
        echo +${SIZE_MIB_ARG}M # last sector \
        echo w                 # write and exit \
    ) | fdisk ${DISK}"

    log_debug "\t- ⌛ Waiting for partition to be recognized ..."
    sleep 2
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "partprobe ${DISK}"

    log_debug "\t- 🧼 Formatting with XFS ..."
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "mkfs.xfs ${PARTITION}"

    log_debug "\t- 📁 Creating mount point at ${MOUNT_POINT} ..."
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "mkdir -p ${MOUNT_POINT}"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "mount ${PARTITION} ${MOUNT_POINT}"

    log_debug "🔁 Adding to /etc/fstab ..."
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "echo \"UUID=$(blkid -s UUID -o value "${PARTITION}") ${MOUNT_POINT} xfs defaults 0 0\" >>/etc/fstab"
}

#
# setup_glusterfs
#
setup_glusterfs() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local IP_ADDRESS_ARG="${3}"

    local MOUNT_POINT="/mnt/gluster"

    log_debug "📦 Installing GlusterFS ..."
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "apt update"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "apt upgrade -y -qq"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "apt install -qq -y xfsprogs attr glusterfs-server glusterfs-common glusterfs-client"

    log_debug "\t- 🚀 Starting GlusterFS server service ..."
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "systemctl enable glusterfs-server"

    log_debug "\t- 🧱 Creating GlusterFS brick directory ..."
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "mkdir -p $MOUNT_POINT/brick"

    log_debug "\t- ✅ Done!"
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
        --size-gib=*)
            SIZE_MIB="${ARG#*=}"
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
    local VOLUME_NAME="${VOLUME_NAME:-glusterdb}"
    SIZE_MIB="${SIZE_MIB:-1024}" # Default size in MiB (1 GiB)
    local DISK_INDEX=1
    local BRICKS=()

    check_all_mandatory_parameters "${MANDATORY_PARAMETER_LIST[@]}"
    display_settings

    log_info "Installing required packages"
    apt-get install -qq -y dnsutils

    log_info "Looking for managers with prefix ${MANAGER_HOSTNAME_PREFIX} in the subnet ${SUBNET} ..."
    for i in {1..254}; do
        IP="$SUBNET.$i"
        (
            if ping -c 1 -W 1 "$IP" &>/dev/null; then
                HOSTNAME=$(dig +short -x "$IP" | sed 's/\.$//')
                if [[ "$HOSTNAME" =~ ${MANAGER_HOSTNAME_PREFIX} ]]; then
                    log_warning "\t\t- Setup GlusterFS server on ${HOSTNAME} (${IP})"
                    create_xfs_partition "$LOGIN" "$PASSWORD" "$IP" "$SIZE_MIB" "$DISK_INDEX"
                    setup_glusterfs "$LOGIN" "$PASSWORD" "$IP"

                    BRICKS+=("${HOST}:/mnt/glusterfs/brick")
                    DISK_INDEX=$((DISK_INDEX + 1))
                fi
            fi
        ) &
    done

    wait

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
