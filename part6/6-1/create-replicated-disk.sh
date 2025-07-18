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
    log_debug "         [--size-mib=<NUMBER> (1024 MiB=1 GiB by default)]"
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

    log_info " - 🔧 Creating partition..."
    sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "sudo bash -s" <<EOF
set -x

# Get largest disk (not partition!)
DISK_NAME=$(lsblk -b -l -o NAME,SIZE,TYPE | awk '$3 == "disk" {print $1, $2}' | sort -k2 -nr | head -n1 | awk '{print $1}')
DISK="/dev/${DISK_NAME}"

# Partition it
echo -e "n\np\n1\n\n+${SIZE_MIB_ARG}M\nw" | fdisk "$DISK"
sleep 2
partprobe "$DISK"
EOF

    log_debug "\t- 🧼 Formatting with XFS ..."
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "sudo mkfs.xfs ${PARTITION}"

    log_debug "\t- 📁 Creating mount point at ${MOUNT_POINT} ..."
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "sudo mkdir -p ${MOUNT_POINT}"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "sudo mount ${PARTITION} ${MOUNT_POINT}"

    log_debug "🔁 Adding to /etc/fstab ..."
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "sudo echo \"UUID=$(blkid -s UUID -o value "${PARTITION}") ${MOUNT_POINT} xfs defaults 0 0\" >>/etc/fstab"
}

#
# setup_glusterfs
#
setup_glusterfs() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local IP_ADDRESS_ARG="${3}"
    local MOUNT_POINT="/mnt/gluster"
    local BRICK_SOURCE="/data/gluster-brick" # Fallback or real data dir

    log_debug "📦 Installing GlusterFS on ${IP_ADDRESS_ARG}..."
    sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_ADDRESS_ARG}" <<'EOF_GLUSTERFS'
    set -e
    
    # Step 1 & 2: Identify and kill the first apt-related process
    kill_pid=$(ps aux | grep -i apt | grep -v grep | awk '{print $2}' | head -n 1)
    
    if [ -n "$kill_pid" ]; then
        sudo kill -9 "$kill_pid"
        echo "Killed apt process with PID $kill_pid"
    fi

    # Step 3: Remove the lock file if it exists
    [ -f /var/lib/dpkg/lock-frontend ] && sudo rm /var/lib/dpkg/lock-frontend

    # Step 4: Reconfigure dpkg
    sudo dpkg --configure -a 1>/dev/null
    
    sudo apt update -qq && sudo apt install -qq -y xfsprogs attr glusterfs-server glusterfs-common glusterfs-client
EOF_GLUSTERFS

    log_debug "\t- 🚀 Enabling and starting GlusterFS service ..."
    sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "sudo systemctl enable --now glusterd"

    log_debug "\t- 📁 Preparing brick mount point at ${MOUNT_POINT}/brick ..."

    sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "bash -s" <<EOF
set -e

sudo mkdir -p "${BRICK_SOURCE}"
sudo mkdir -p "${MOUNT_POINT}/brick"

# If MOUNT_POINT isn't already mounted, bind BRICK_SOURCE
if ! mountpoint -q "${MOUNT_POINT}/brick"; then
    sudo mount --bind "${BRICK_SOURCE}" "${MOUNT_POINT}/brick"

    # Persist in /etc/fstab if not already present
    if ! grep -q "${MOUNT_POINT}/brick" /etc/fstab; then
        echo "${BRICK_SOURCE} ${MOUNT_POINT}/brick none bind 0 0" | sudo tee -a /etc/fstab > /dev/null
    fi
fi
EOF

    log_debug "\t- ✅ GlusterFS setup complete on ${IP_ADDRESS_ARG}!"
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
        --size-mib=*)
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
    local BRICKS=()

    check_all_mandatory_parameters "${MANDATORY_PARAMETER_LIST[@]}"
    display_settings

    log_info "Installing required packages"
    apt-get install -qq -y dnsutils

    log_info "Looking for managers with prefix ${MANAGER_HOSTNAME_PREFIX} in the subnet ${SUBNET} ..."
    unset MASTER_IP # Ensure it's clean before the loop

    for i in {1..254}; do
        IP="${SUBNET}.${i}"

        # Print current IP being checked (overwrites the same line)
        log_progress_bar "🔍 Testing ${IP} ..." "$((i + 1))" 254

        if ping -c 1 -W 1 "$IP" &>/dev/null; then
            HOSTNAME=$(dig +short -x "$IP" | sed 's/\.$//')

            if [[ "$HOSTNAME" =~ ${MANAGER_HOSTNAME_PREFIX} ]]; then
                log_warning "\t\t- Setup GlusterFS server on ${HOSTNAME} (${IP})"

                # Capture the first matching IP
                if [[ -z "$MASTER_IP" ]]; then
                    MASTER_IP="$IP"
                    log_info "\t\t🔑 Master node selected: $MASTER_IP"
                fi

                setup_glusterfs "$LOGIN" "$PASSWORD" "$IP" 

                BRICKS+=("${HOSTNAME}:/mnt/gluster/brick")
            fi
        fi
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

        sshpass -p "${PASSWORD}" ssh -o StrictHostKeyChecking=no "${LOGIN}@${MASTER_IP}" bash -s <<EOF
set -e
echo "Creating GlusterFS volume '${VOLUME_NAME}'..."
sudo gluster volume create "${VOLUME_NAME}" replica ${#BRICKS[@]} ${BRICK_LIST} force

echo "Starting GlusterFS volume '${VOLUME_NAME}'..."
sudo gluster volume start "${VOLUME_NAME}"

echo "Volume Info:"
sudo gluster volume info "${VOLUME_NAME}"
EOF
    fi
}

# === Track and report duration ===
time main "$@"
