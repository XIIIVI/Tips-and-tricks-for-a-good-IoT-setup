#!/bin/bash

source "../../commons/commons-cli.sh"
source "../../commons/commons-log.sh"

# === Usage function ===
usage() {
  log_debug "Usage: $0 --disk-index=<NUMBER>"
  log_debug "                   [--size-mib=<NUMBER> (1000 MiB by default)]"
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
  log_debug "DISK_INDEX: ${DISK_INDEX}"
  log_debug "SIZE_MIB  : ${SIZE_MIB} MiB"
}

#
# create_xfs_partition
#
create_xfs_partition() {
  local SIZE_MIB_ARG="${1}"
  local DISK_INDEX_ARG="${2}"
  local PARTITION="${DISK}${DISK_INDEX_ARG}"
  local MOUNT_POINT="/mnt/gluster"
  local DISK=$(lsblk -b -l -o NAME,SIZE,TYPE | awk '$3 == "part" {print $1, $2}' | sort -k2 -nr | head -n1 | awk '{print $1}')

  log_info " - 🔧 Creating partition..."
  (
    echo n                 # new partition
    echo p                 # primary
    echo 1                 # partition number
    echo                   # default first sector
    echo +${SIZE_MIB_ARG}M # last sector
    echo w                 # write and exit
  ) | fdisk "${DISK}"

  log_debug "\t- ⌛ Waiting for partition to be recognized ..."
  sleep 2
  partprobe "${DISK}"

  log_debug "\t- 🧼 Formatting with XFS ..."
  mkfs.xfs "${PARTITION}"

  log_debug "\t- 📁 Creating mount point at ${MOUNT_POINT} ..."
  mkdir -p "${MOUNT_POINT}"
  mount "${PARTITION}" "${MOUNT_POINT}"

  log_debug "🔁 Adding to /etc/fstab ..."
  UUID=$(blkid -s UUID -o value "${PARTITION}")
  echo "UUID=${UUID} ${MOUNT_POINT} xfs defaults 0 0" >>/etc/fstab
}

#
# setup_glusterfs
#
setup_glusterfs() {
  local MOUNT_POINT="/mnt/gluster"

  log_debug "📦 Installing GlusterFS ..."
  apt update
  apt upgrade -y
  apt install -qq -y xfsprogs attr glusterfs-server glusterfs-common glusterfs-client

  log_debug "\t- 🚀 Starting GlusterFS server service ..."
  systemctl enable glusterfs-server

  log_debug "\t- 🧱 Creating GlusterFS brick directory ..."
  mkdir -p "$MOUNT_POINT/brick"

  log_debug "\t- ✅ Done!"
}

#
# Main logic
#
create_disk() {
  MANDATORY_PARAMETER_LIST=("DISK_INDEX")

  for ARG in "$@"; do
    case $ARG in
    --disk-index=*)
      DISK_INDEX="${ARG#*=}"
      shift
      ;;
    --size-mib=*)
      SIZE_MIB="${ARG#*=}"
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

  SIZE_MIB="${SIZE_MIB:-1000}" # Default to 5 GiB if not set

  create_xfs_partition "$SIZE_MIB" "$DISK_INDEX"
  setup_glusterfs
}

# === Track and report duration ===
time main "$@"
