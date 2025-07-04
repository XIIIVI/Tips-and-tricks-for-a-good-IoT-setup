#!/bin/bash

source "../../commons/commons-cli.sh"
source "../../commons/commons-log.sh"

# === Usage function ===
usage() {
  log_debug "Usage: $0 [--device-name=sdX]"
  log_debug "                    --disk-label=<MYDISK>"
  log_debug "                   [--size-gib=<NUMBER> (5 GiB by default)]"
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
create_disk() {
  MANDATORY_PARAMETER_LIST=("SIZE_GIB" "DISK_LABEL")

  for ARG in "$@"; do
    case $ARG in
      --device-name=*)
        DEVICE="${ARG#*=}"
        shift
        ;;
      --size-gib=*)
        SIZE_GIB="${ARG#*=}"
        shift
        ;;
      --disk-label=*)
        DISK_LABEL="${ARG#*=}"
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

  DEVICE="${DEVICE:-$(lsblk -b -l -o NAME,SIZE,TYPE | awk '$3 == "part" {print $1, $2}' | sort -k2 -nr | head -n1 | awk '{print $1}')}"
  SIZE_GIB="${SIZE_GIB:-5}"  # Default to 5 GiB if not set
  FULL_DEV="/dev/$DEVICE"
  PARTITION="${FULL_DEV}1"
  MOUNT_DIR="/mnt/$DISK_LABEL"

  log_info "Creating ${SIZE_GIB} GiB partition on $FULL_DEV with label '$DISK_LABEL'..."

  # Partitioning
  echo -e "n\np\n1\n\n+${SIZE_GIB}G\nw" | fdisk "$FULL_DEV"

  # Formatting
  mkfs.ext4 -L "$DISK_LABEL" "$PARTITION"

  # Mounting
  mkdir -p "$MOUNT_DIR"
  mount "$PARTITION" "$MOUNT_DIR"

  # Add to /etc/fstab using UUID
  UUID=$(blkid -s UUID -o value "$PARTITION")
  echo "UUID=$UUID $MOUNT_DIR ext4 defaults 0 2" >> /etc/fstab

  log_debug "\t✅ Partition $PARTITION created, labeled '$DISK_LABEL', mounted at $MOUNT_DIR"
  log_debug "\t📌 Entry added to /etc/fstab for persistent mounting."
}

# === Track and report duration ===
time main "$@"
