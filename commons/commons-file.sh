#!/bin/bash

#
# get_ip_by_hostname
# 
# This function retrieves the IP address associated with a given hostname
# from a JSON configuration file. It handles default hostname prefixes for
# swarm managers and workers.
# Arguments:
#   1. HOSTNAME_ARG: The hostname to look up.
#   2. JSON_ARG: The JSON content of the configuration file.
# Returns:
#   The IP address corresponding to the provided hostname, or an empty string if not found. 
get_ip_by_hostname() {
  local HOSTNAME_ARG="$1"
  local JSON_ARG="$2"

  # Step 1: Extract all hostnames and IPs into a temp list
  local HOST_LIST
  HOST_LIST=$(echo "${JSON_ARG}" | jq -r '
    def assign_hostnames(prefix; list):
      [ range(0; list | length) as $i
        | (list[$i] + {hostname: (list[$i].hostname // (prefix + ($i+1|tostring)))})
        | "\(.hostname) \(.["ip-address"])"
      ];

    (assign_hostnames(.swarm.managers["hostname-default-prefix"]; .swarm.managers.members)[]) ,
    (assign_hostnames("worker"; .swarm.workers)[])
  ')

  # Step 2: Search for the hostname in the list
  echo "$HOST_LIST" | awk -v h="$HOSTNAME_ARG" '$1 == h {print $2}'
}

#
# deploy_glusterfs_mount_units
#
# Installs systemd .mount and .automount units for GlusterFS
# on each node, ensuring reliable on-demand mounting.
#
# Args:
#   1. LOGIN_ARG
#   2. PASSWORD_ARG
#   3. VOLUME_NAME_ARG
#   4. MASTER_IP (primary peer to contact)
#   5. BACKUP_IP (secondary peer for resilience)
#   6+. NODE_IPS (list of all node IPs)
#
deploy_glusterfs_mount_units() {
    local ROOT_USER_ARG="$1"
    local ROOT_PASS_ARG="$2"
    local HOST_IP_ARG="$3"
    local MOUNT_PATH="$4"        # e.g. /mnt/replicated-data
    local GLUSTER_VOL="$5"       # e.g. replicated-data

    log_debug "\t- Deploying GlusterFS mount units on $HOST_IP_ARG ..."

    # Derive proper unit names from the mount path
    local MOUNT_UNIT
    local AUTOMOUNT_UNIT
    MOUNT_UNIT="$(systemd-escape -p --suffix=mount "$MOUNT_PATH")"
    AUTOMOUNT_UNIT="$(systemd-escape -p --suffix=automount "$MOUNT_PATH")"

    log_warning "\t\t- Using units: $MOUNT_UNIT / $AUTOMOUNT_UNIT"

    # Create the .mount unit
    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no \
        "$ROOT_USER_ARG@$HOST_IP_ARG" "cat <<'EOF' | sudo tee /etc/systemd/system/$MOUNT_UNIT > /dev/null
[Unit]
Description=GlusterFS mount for $GLUSTER_VOL
After=network-online.target
Wants=network-online.target

[Mount]
What=localhost:/$GLUSTER_VOL
Where=$MOUNT_PATH
Type=glusterfs
Options=_netdev

[Install]
WantedBy=multi-user.target
EOF"

    # Create the .automount unit
    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no \
        "$ROOT_USER_ARG@$HOST_IP_ARG" "cat <<'EOF' | sudo tee /etc/systemd/system/$AUTOMOUNT_UNIT > /dev/null
[Unit]
Description=Automount GlusterFS $GLUSTER_VOL

[Automount]
Where=$MOUNT_PATH
TimeoutIdleSec=60

[Install]
WantedBy=multi-user.target
EOF"

    # Ensure mountpoint exists
    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no \
        "$ROOT_USER_ARG@$HOST_IP_ARG" "sudo mkdir -p $MOUNT_PATH"

    # Reload systemd and enable automount
    sshpass -p "$ROOT_PASS_ARG" ssh -o StrictHostKeyChecking=no \
        "$ROOT_USER_ARG@$HOST_IP_ARG" "sudo systemctl daemon-reload && \
                                        sudo systemctl enable --now $AUTOMOUNT_UNIT"
}


#
# setup_replicated_volumes
#
# Arguments:
#   1. LOGIN_ARG: SSH username
#   2. PASSWORD_ARG: SSH password
#   3. VOLUME_NAME_ARG: Gluster volume name (e.g., replicated-data)
#   4. SWARM_JSON_ARG: Swarm inventory JSON (for get_ip_by_hostname)
#   5+. HOSTNAME_LIST_ARG: hostnames (order defines brick index)
#
setup_replicated_volumes() {
  set -eo pipefail

  local LOGIN_ARG="${1}"
  local PASSWORD_ARG="${2}"
  local VOLUME_NAME_ARG="${3}"
  local SWARM_JSON_ARG="${4}"
  shift 4
  local HOSTNAME_LIST_ARG=("$@")

  if [[ ${#HOSTNAME_LIST_ARG[@]} -eq 0 ]]; then
    echo "⚠️ Host list is empty." >&2
    return 1
  fi

  local FINAL_MOUNT_POINT="/mnt/${VOLUME_NAME_ARG}"
  local GLUSTER_DIR="/gluster-${VOLUME_NAME_ARG}/bricks"
  local GLUSTERFS_TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${GLUSTERFS_TMP_DIR}"' EXIT

  local ETC_HOSTS_FILE="${GLUSTERFS_TMP_DIR}/etc_hosts.addon"
  : > "${ETC_HOSTS_FILE}"

  local DISCOVERED_IPS=()
  for HOST in "${HOSTNAME_LIST_ARG[@]}"; do
    local IP="$(get_ip_by_hostname "${HOST}" "${SWARM_JSON_ARG}" 2>/dev/null || true)"
    [[ -z "${IP}" ]] && IP="$(getent hosts "${HOST}" | awk '{print $1}' | head -1)"
    [[ -z "${IP}" ]] && { echo "❌ Failed to resolve ${HOST}" >&2; return 1; }
    echo "${IP} ${HOST}" >> "${ETC_HOSTS_FILE}"
    DISCOVERED_IPS+=("${IP}")
  done

  local MASTER_IP="${DISCOVERED_IPS[0]}"
  local REPLICA_COUNT="${#DISCOVERED_IPS[@]}"

  # Prepare each node
  local IDX=0
  for IP in "${DISCOVERED_IPS[@]}"; do
    IDX=$((IDX+1))
    sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP}" bash -s <<EOF
set -eo pipefail
while read -r LINE; do
  grep -qxF "\$LINE" /etc/hosts || echo "\$LINE" | sudo tee -a /etc/hosts >/dev/null
done < <(cat <<EOT
$(<"${ETC_HOSTS_FILE}")
EOT
)

sudo mkdir -p "${GLUSTER_DIR}/${IDX}"
sudo chown root:root "${GLUSTER_DIR}/${IDX}"
sudo chmod 755 "${GLUSTER_DIR}/${IDX}"
sudo mkdir -p "${FINAL_MOUNT_POINT}"

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq glusterfs-server glusterfs-cli tree
sudo systemctl enable --now glusterd
EOF
  done

  # Probe peers
  for IP in "${DISCOVERED_IPS[@]}"; do
    [[ "${IP}" == "${MASTER_IP}" ]] && continue
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP}" \
      "sudo gluster peer probe ${IP} || true"
    sleep 1
  done

  # Wait for trusted pool
  sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP}" bash -s <<EOF
set -eo pipefail
for i in {1..60}; do
  COUNT=\$(sudo gluster peer status | awk '/State: Peer in Cluster/{c++} END{print c+0}')
  [[ "\$COUNT" -ge $((REPLICA_COUNT - 1)) ]] && exit 0
  sleep 1
done
echo "❌ Peers did not join in time" >&2
exit 1
EOF

  # Create volume if missing
  local CREATE_CMD="sudo gluster volume create ${VOLUME_NAME_ARG} replica ${REPLICA_COUNT} transport tcp"
  IDX=0
  for HOST in "${HOSTNAME_LIST_ARG[@]}"; do
    IDX=$((IDX+1))
    CREATE_CMD+=" ${HOST}:${GLUSTER_DIR}/${IDX}"
  done
  CREATE_CMD+=" force"

  sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP}" bash -s <<EOF
set -eo pipefail
if ! sudo gluster volume info "${VOLUME_NAME_ARG}" >/dev/null 2>&1; then
  ${CREATE_CMD}
fi
STATE=\$(sudo gluster volume info "${VOLUME_NAME_ARG}" | awk -F': ' '/Status:/ {print \$2}')
[[ "\$STATE" != "Started" ]] && sudo gluster volume start "${VOLUME_NAME_ARG}"
EOF

  # Set auth.allow
  local ALLOW_LIST="$(IFS=, ; echo "${DISCOVERED_IPS[*]}")"
  sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP}" \
    "sudo gluster volume set ${VOLUME_NAME_ARG} auth.allow ${ALLOW_LIST}"

  # Mount volume on each node
  IDX=0
  for IP in "${DISCOVERED_IPS[@]}"; do
    IDX=$((IDX+1))
    local BACKUP="${MASTER_IP}"
    [[ "${IP}" == "${BACKUP}" ]] && BACKUP="${DISCOVERED_IPS[1]:-${MASTER_IP}}"
    local MOUNTLINE="${IP}:/${VOLUME_NAME_ARG} ${FINAL_MOUNT_POINT} glusterfs defaults,_netdev,backupvolfile-server=${BACKUP} 0 0"

    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP}" bash -s <<EOF
set -eo pipefail
sudo sed -i '\#[[:space:]]${FINAL_MOUNT_POINT}[[:space:]]#d' /etc/fstab
echo '${MOUNTLINE}' | sudo tee -a /etc/fstab >/dev/null
sudo systemctl daemon-reload
sudo mkdir -p "${FINAL_MOUNT_POINT}"
mountpoint -q "${FINAL_MOUNT_POINT}" && sudo umount "${FINAL_MOUNT_POINT}" || true
sudo mount -a
EOF
  done

# Create systemd mount + automount units on each node
log_debug "\t- Setting up systemd mount units on all nodes..."

for IP in "${DISCOVERED_IPS[@]}"; do
  sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP}" bash -s <<EOF
set -euo pipefail

# Mount unit
cat <<UNIT | sudo tee /etc/systemd/system/mnt-replicated-data.mount > /dev/null
[Unit]
Description=GlusterFS mount for replicated-data
After=network-online.target glusterd.service
Wants=network-online.target glusterd.service

[Mount]
What=${IP}:/${VOLUME_NAME_ARG}
Where=/mnt/replicated-data
Type=glusterfs
Options=_netdev,backupvolfile-server=${MASTER_IP}

[Install]
WantedBy=multi-user.target
UNIT

# Automount unit
cat <<AUTOUNIT | sudo tee /etc/systemd/system/mnt-replicated-data.automount > /dev/null
[Unit]
Description=Automount for GlusterFS replicated-data
After=network-online.target glusterd.service
Wants=network-online.target glusterd.service

[Automount]
Where=/mnt/replicated-data

[Install]
WantedBy=multi-user.target
AUTOUNIT

# Enable and reload
sudo systemctl daemon-reload
sudo systemctl enable mnt-replicated-data.mount
sudo systemctl enable mnt-replicated-data.automount
EOF
done

  # Test replication
  local TS="$(date +%s)"
  sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP}" \
    "echo 'Hello ${VOLUME_NAME_ARG} ${TS}' | sudo tee '${FINAL_MOUNT_POINT}/test-${TS}.txt' >/dev/null"

  for IP in "${DISCOVERED_IPS[@]}"; do
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP}" \
      "sudo cat '${FINAL_MOUNT_POINT}/test-${TS}.txt' || echo '❌ Missing test file on ${IP}'"
  done

  echo "✅ GlusterFS volume ${VOLUME_NAME_ARG} is set up and replicating."

  # Deploying healthcheck
  deploy_glusterfs_mount_units "${LOGIN_ARG}" "${PASSWORD_ARG}" "${VOLUME_NAME_ARG}" "${MASTER_IP_ADDRESS}" "${DISCOVERED_IPS[1]}" "${DISCOVERED_IPS[@]}"
}
