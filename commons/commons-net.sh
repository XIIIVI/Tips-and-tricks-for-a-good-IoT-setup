#!/bin/bash

declare -A HOSTMAP

#
# find_devices_by_prefix
#
find_devices_by_prefix() {
  local PREFIX="$1"

  # Get subnet (assuming /24)
  local SUBNET=$(ip route | awk '/src/ {split($1,a,"/"); print a[1]}' | head -n 1 | sed 's/\.[0-9]*$/./')

  for i in {1..254}; do
    IP="${SUBNET}${i}"
    HOSTNAME=$(getent hosts "$IP" | awk '{print $2}')
    if [[ "$HOSTNAME" == "$PREFIX"* ]]; then
      HOSTMAP["$HOSTNAME"]="$IP"
    fi
  done
}

# === Call the function ===
# find_devices_by_prefix "mydevice"

# === Use the global dictionary outside ===
# echo "📦 Devices found:"
# for HOST in "${!HOSTMAP[@]}"; do
#   echo "  $HOST => ${HOSTMAP[$HOST]}"
# done
