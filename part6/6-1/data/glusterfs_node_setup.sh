#!/bin/bash

# ─── CONFIG ────────────────────────────────────────────────────────
VOLUME_NAME="gv0"
MOUNT_POINT="/glusterfs"
BRICK_NAME="brick"
PEERS=("$@")
REPLICA_COUNT=${#PEERS[@]}
REPLICA_COUNT=$((REPLICA_COUNT + 1))  # Including self

# ─── DETECT LARGEST ELIGIBLE PARTITION ─────────────────────────────
PARTITIONS=$(df --output=avail,fstype,target | tail -n +2 | awk '$2 ~ /^(nfs4|xfs|btrfs)$/ {print $3}' | sort -hr)
LARGEST=""
for mp in $PARTITIONS; do
    if mountpoint -q "$mp"; then
        LARGEST="$mp"
        break
    fi
done
[ -z "$LARGEST" ] && LARGEST="/"  # Fallback to root

BRICK_DIR="$LARGEST/glusterfs/$BRICK_NAME"
mkdir -p "$BRICK_DIR"
chown -R gluster:gluster "$BRICK_DIR"

# ─── CREATE BRICK LIST ─────────────────────────────────────────────
BRICKS=()
BRICKS+=("$(hostname):$BRICK_DIR")
for peer in "${PEERS[@]}"; do
    BRICKS+=("$peer:$BRICK_DIR")
done

# ─── MOUNT VOLUME ──────────────────────────────────────────────────
mkdir -p "$MOUNT_POINT/brick_$(hostname)"
chown -R gluster:gluster "$MOUNT_POINT/brick_$(hostname)"
mount -t glusterfs "$(hostname):/$VOLUME_NAME" "$MOUNT_POINT"

# ─── CREATE & START VOLUME ─────────────────────────────────────────
gluster volume create "$VOLUME_NAME" replica "$REPLICA_COUNT" "${BRICKS[@]}" force
gluster volume start "$VOLUME_NAME"
gluster volume status "$VOLUME_NAME"
gluster volume info "$VOLUME_NAME"

# ____ SECURITY and PERMISSIONS ____
IFS=',' 
JOINED_STRING="${PEERS[*]}"

gluster volume set gfs auth.allow "${JOINED_STRING}"

echo "✅ GlusterFS '$VOLUME_NAME' mounted at '$MOUNT_POINT' using partition: $LARGEST with replica count: $REPLICA_COUNT"
