#!/bin/bash

#
# split_partition
# - param1: Size of the second partition in MiB
# - param2: Dry run mode (true/false)
split_partition() {
    local SECOND_SIZE_MIB="$1"
    local DRY_RUN="$2"

    log_info "Splitting the partition and adding a new XFS partition of size ${SECOND_SIZE_MIB} MiB"

    # Detect root partition and device
    local ROOT_PARTITION
    ROOT_PARTITION=$(findmnt -n -o SOURCE /)  # e.g. /dev/sda1

    local DEVICE
    DEVICE=$(echo "$ROOT_PARTITION" | sed 's/[0-9]*$//')  # e.g. /dev/sda

    local PARTITION="$ROOT_PARTITION"

    local CURRENT_PART_NUM
    CURRENT_PART_NUM=$(echo "$ROOT_PARTITION" | grep -o '[0-9]*$')
    local NEW_PART_NUM=$((CURRENT_PART_NUM + 1))

    local TOTAL_SIZE_MIB
    TOTAL_SIZE_MIB=$(parted "$DEVICE" --script unit MiB print | awk '/^Disk/ {gsub(/MiB/, "", $3); print int($3)}')

    local RESIZED_SIZE_MIB=$((TOTAL_SIZE_MIB - SECOND_SIZE_MIB))
    local START_SECOND="${RESIZED_SIZE_MIB}MiB"
    local END_SECOND="${TOTAL_SIZE_MIB}MiB"

    log_debug "🧠 Plan:"
    log_warning "\t- Root partition: $PARTITION"
    log_warning "\t- Base device: $DEVICE"
    log_warning "\t- Resize ${PARTITION} to ${RESIZED_SIZE_MIB} MiB"
    log_warning "\t- Create ${DEVICE}${NEW_PART_NUM} from ${START_SECOND} to ${END_SECOND}"
    log_warning "\t- Format as XFS"

    if [[ "$DRY_RUN" == true ]]; then
        log_warning "\t- 🧪 Dry-run mode enabled. No changes applied."
    else
        log_warning "\t- 🚀 Performing changes..."
        parted "$DEVICE" --script resizepart "$CURRENT_PART_NUM" "${RESIZED_SIZE_MIB}MiB"
        parted "$DEVICE" --script mkpart primary xfs "$START_SECOND" "$END_SECOND"
        mkfs.xfs -f "${DEVICE}${NEW_PART_NUM}"
        log_warning "\t- ✅ Success: New XFS partition created as ${DEVICE}${NEW_PART_NUM}"
    fi
}