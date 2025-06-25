#!/bin/bash

START_IP_ADDRESS=

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

#
# set_ip_address
#
set_static_ip_address() {
  local LOGIN_ARG="$1"
  local PASSWORD_ARG="$2"
  local OLD_IP_ARG="$3"
  local NEW_IP_ARG="$4"

  # If NEW_IP_ARG is provided
  if [[ -z "$NEW_IP_ARG" ]]; then
    echo "No new IP address provided. Aborting."
  else
    local LAST_OCTET="${NEW_IP_ARG##*.}"

    if ((LAST_OCTET > 240)); then
      echo "New IP $NEW_IP_ARG exceeds the xxx.xxx.xxx.240 limit."
      return 1
    fi

    echo "Pinging $NEW_IP_ARG to check if it's already in use..."
    if ping -c 1 -W 1 "$NEW_IP_ARG" &>/dev/null; then
      echo "IP address $NEW_IP_ARG is already active. Aborting."
      return 1
    fi

    echo "Connecting to $OLD_IP_ARG to reconfigure network using nmcli..."

    sshpass -p "$PASSWORD_ARG" ssh -o StrictHostKeyChecking=no "$LOGIN_ARG@$OLD_IP_ARG" bash -s <<EOF
DEVICE="\$(sudo nmcli |  grep -v "externally" | grep "connected" | sed 's/^.*: connected to //g')"

if [[ -z "\$DEVICE" ]]; then
    echo "No active network device found. Exiting."
    exit 1
fi

echo "Applying static IP $NEW_IP_ARG on \$DEVICE"
sudo nmcli con mod "\$DEVICE" ipv4.addresses "$NEW_IP_ARG/24"
sudo nmcli con mod "\$DEVICE" ipv4.gateway "${NEW_IP_ARG%.*}.1"
sudo nmcli con mod "\$DEVICE" ipv4.dns "8.8.8.8 8.8.4.4"
sudo nmcli con mod "\$DEVICE" ipv4.method manual

sudo nmcli con down "\$DEVICE"
sudo nmcli con up "\$DEVICE"

echo "IP changed to $NEW_IP_ARG via nmcli."
EOF
  fi
}

#
# increment_ip
#
# Helper to increment the last octet, skipping those already in use
increment_ip() {
  local BASE="${1%.*}"
  local LAST="${1##*.}"

  while ((LAST < 240)); do
    ((LAST++))
    local NEW_TRY="${BASE}.${LAST}"
    if ! ping -c 1 -W 1 "$NEW_TRY" &>/dev/null; then
      echo "$NEW_TRY"
      return 0
    fi
  done

  echo "NONE" # signify no valid IP found
  return 1
}

#
# change_ip_addresses
#
# Function that sets IPs on each remote machine
change_ip_address() {
  if [ -z "${START_IP_ADDRESS}" ]; then
    local LOGIN_ARG="$1"
    local PASSWORD_ARG="$2"
    local OLD_IP_ARG="$3"

    log_debug "\t\t- Assigning new IP $START_IP_ADDRESS to ${OLD_IP_ARG} ..."

    if set_static_ip_address "${LOGIN_ARG}" "${PASSWORD_ARG}" "${OLD_IP_ARG}" "${START_IP_ADDRESS}"; then
      local NEXT_IP

      log_warning "\t\t\t✅ Success for $OLD_IP_ARG. Moving to next IP..."

      NEXT_IP=$(increment_ip "$START_IP_ADDRESS")

      if [ "$NEXT_IP" == "NONE" ]; then
        log_error "No valid IPs left to assign."
        return 1
      fi

      START_IP_ADDRESS="$NEXT_IP"
    else
      log_error "❌ Failed to assign IP to $TARGET_IP. Skipping."
    fi
  else
    log_warning "⚠️ START_IP_ADDRESS is not set. Cannot proceed with IP assignment."
  fi
}

# === Call the function ===
# find_devices_by_prefix "mydevice"

# === Use the global dictionary outside ===
# echo "📦 Devices found:"
# for HOST in "${!HOSTMAP[@]}"; do
#   echo "  $HOST => ${HOSTMAP[$HOST]}"
# done
