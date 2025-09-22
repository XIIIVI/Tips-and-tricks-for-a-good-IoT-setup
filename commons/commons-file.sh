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
# setup_replicated_volumes
#
# This function sets up replicated disks using GlusterFS on a list of hosts.
# It requires the login credentials and a list of hostnames to operate.
# Arguments:
#   1. LOGIN_ARG: The username for SSH login.
#   2. PASSWORD_ARG: The password for SSH login.
#   3. VOLUME_NAME_ARG: The name of the GlusterFS volume to create.
#   5. HOSTNAME_LIST_ARG: An array of hostnames where the GlusterFS volume will be set up.
#
setup_replicated_volumes_old() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local VOLUME_NAME_ARG="${3}"
    local SWARM_JSON_ARG="${4}"
    shift 4
    local HOSTNAME_LIST_ARG=("$@")

    if [ ${#HOSTNAME_LIST_ARG[@]} -eq 0 ]; then
        log_error "\t⚠️ The list of hosts is empty."
    else
         local GLUSTERFS_TMP_DIR=/$(mktemp -d)
         local ETC_HOSTS_FILE=${GLUSTERFS_TMP_DIR}/etc_hosts.addon
         local ETC_FSTAB_FILE=${GLUSTERFS_TMP_DIR}/etc_fstab.addon
         local GLUSTER_DIR="/gluster-${VOLUME_NAME_ARG}/bricks"
         local COUNTER=1
         local MASTER_IP_ADDRESS
         local DISCOVERED_IPS
         local FINAL_MOUNT_POINT="/mnt"
         local GLUSTERFS_CREATE_CMD="sudo /usr/sbin/gluster volume create ${VOLUME_NAME_ARG} replica ${#HOSTNAME_LIST_ARG[@]} transport tcp"

         log_debug "\t- Setting up replicated disks with GlusterFS"

         # Default to just /mnt if not specified
         if [[ -n "${VOLUME_NAME_ARG}" ]]; then
             FINAL_MOUNT_POINT="${FINAL_MOUNT_POINT}/${VOLUME_NAME_ARG}"
         fi

         MASTER_IP_ADDRESS=$(get_ip_by_hostname "${HOSTNAME_LIST_ARG[0]}" "${SWARM_JSON_ARG}")

         log_warning "\t\t- Master node for GlusterFS setup is ${MASTER_IP_ADDRESS} (${HOSTNAME_LIST_ARG[0]})"

         # Build the IP address list
         DISCOVERED_IPS=()

         for HOSTNAME_INDEX in "${HOSTNAME_LIST_ARG[@]}"; do
             local IP
               
             IP=$(get_ip_by_hostname "${HOSTNAME_INDEX}" "${SWARM_JSON_ARG}")

             DISCOVERED_IPS+=("${IP}")
         done

         log_warning "\t\t- Installing required packages"
         apt-get install -qq -y dnsutils

         log_warning "\t\t- Setting up /etc/hosts and /etc/fstab files for GlusterFS volume ${VOLUME_NAME_ARG}"
         COUNTER=1

         for HOSTNAME in "${HOSTNAME_LIST_ARG[@]}"; do
             local IP_INDEX

             IP_INDEX=$(host "${HOSTNAME}" | awk '/has address/ { print $4 }')

             echo "${IP_INDEX} ${HOSTNAME}" >>"${ETC_HOSTS_FILE}"
             # echo "${HOSTNAME}:/$VOLUME_NAME_ARG  ${GLUSTER_DIR}/${COUNTER}  glusterfs  defaults,_netdev  0  0" >> "${ETC_FSTAB_FILE}"

             GLUSTERFS_CREATE_CMD="${GLUSTERFS_CREATE_CMD} ${HOSTNAME}:${GLUSTER_DIR}/${COUNTER}"
             COUNTER=$((COUNTER + 1))
         done

         unset COUNTER

         log_warning "\t\t- Setting up GlusterFS on discovered hosts: ${DISCOVERED_IPS[*]}"
         COUNTER=1

         for IP_INDEX in "${DISCOVERED_IPS[@]}"; do
             remove_ssh_host "${IP_INDEX}"

             log_warning "\t\t- Declaring the GlusterFS member to /etc/hosts"
             copy_file_to_host "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_INDEX}" "${ETC_HOSTS_FILE}" "/tmp"
             sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_INDEX}" "sudo tee -a /etc/hosts < /tmp/$(basename ${ETC_HOSTS_FILE})"

             log_warning "\t\t- Declaring the GlusterFS member to /etc/fstab"
             copy_file_to_host "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_INDEX}" "${ETC_FSTAB_FILE}" "/tmp"
             sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_INDEX}" "sudo tee -a /etc/fstab < /tmp/$(basename ${ETC_FSTAB_FILE})"

             log_warning "\t\t- Installing GlusterFS on ${IP_INDEX}"
             sshpass -p "$PASSWORD_ARG" ssh -o StrictHostKeyChecking=no "$LOGIN_ARG@$IP_INDEX" <<EOF_GLUSTERFS
    export DEBIAN_FRONTEND=noninteractive
    export DEBCONF_NOWARNINGS=yes 


     # ✅ Check that ${FINAL_MOUNT_POINT} does not already exist
     if [[ -e "${FINAL_MOUNT_POINT}" ]]; then
         echo "\\\\t⚠️ Mount point '${FINAL_MOUNT_POINT}' already exists."
     else
         echo "Creating mount point '${FINAL_MOUNT_POINT}'"
         sudo mkdir -p "${FINAL_MOUNT_POINT}"
     fi

    sudo mkdir -p "${GLUSTER_DIR}/${COUNTER}"
    sudo chown -R root:root "${GLUSTER_DIR}/${COUNTER}"
    sudo chmod 755 "${GLUSTER_DIR}/${COUNTER}"

    sudo -E apt-get update -qq
    sudo -E apt-get install glusterfs-cli glusterfs-server tree -y -qq \
         -o Dpkg::Progress-Fancy="0" \
         -o Dpkg::Use-Pty="0"
    sudo -E apt-get dist-upgrade -y -qq \
         -o Dpkg::Progress-Fancy="0" \
         -o Dpkg::Use-Pty="0"
    sudo systemctl enable glusterd
    sudo systemctl start glusterd
    sudo systemctl status glusterd
EOF_GLUSTERFS

             COUNTER=$((COUNTER + 1))
         done

         unset COUNTER

         # Adding force to the create command to avoid issues with previous failed attempts
         # (as the folder is created in the root folder)
         GLUSTERFS_CREATE_CMD="${GLUSTERFS_CREATE_CMD} force"

         # Probing the peers
         for ((IP_INDEX = 0; IP_INDEX < ${#DISCOVERED_IPS[@]}; IP_INDEX++)); do
             log_warning "\t\t- Probing host ${DISCOVERED_IPS[${IP_INDEX}]} ..."
             sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "sudo /usr/sbin/gluster peer probe ${DISCOVERED_IPS[${IP_INDEX}]}"
             sleep 5
         done

         # Waiting for the peers
         log_debug "\t⏳ Waiting for peers to join trusted pool..."
         sleep 5
         sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "sudo /usr/sbin/gluster peer status"        

         # Creating the volume
         log_warning "\t\t- Creating the volumes ${GLUSTERFS_CREATE_CMD}"
         sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "sudo ${GLUSTERFS_CREATE_CMD}"
         log_warning "\t\t- Starting the volume ${VOLUME_NAME_ARG}"
         sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "sudo /usr/sbin/gluster volume start ${VOLUME_NAME_ARG}"
         log_warning "\t\t- Status of the volume ${VOLUME_NAME_ARG}"
         sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "sudo /usr/sbin/gluster volume status ${VOLUME_NAME_ARG}"
         log_warning "\t\t- Info of the volume ${VOLUME_NAME_ARG}"
         sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "sudo /usr/sbin/gluster volume info ${VOLUME_NAME_ARG}"
         log_warning "\t\t- Setup security and authentication for the volume ${VOLUME_NAME_ARG}"
         sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "sudo /usr/sbin/gluster volume set ${VOLUME_NAME_ARG} auth.allow $(IFS=, ; echo "${DISCOVERED_IPS[*]}")"

         # Mounting the glusterFS volume where applications can access the files
         log_debug "\t- Mounting the GlusterFS volume ${VOLUME_NAME_ARG} on all nodes" 
         for IP_INDEX in "${DISCOVERED_IPS[@]}"; do
            log_warning "\t\t- Mounting the GlusterFS volume ${VOLUME_NAME_ARG} (${FINAL_MOUNT_POINT}) on ${IP_INDEX}"
            sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_INDEX}" \
                    "echo \"localhost:/${VOLUME_NAME_ARG} ${FINAL_MOUNT_POINT} glusterfs defaults,_netdev,backupvolfile-server=localhost 0 0\" | sudo tee -a /etc/fstab > /dev/null"
            sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_INDEX}" "sudo sudo /usr/sbin/mount.glusterfs localhost:/${VOLUME_NAME_ARG} ${FINAL_MOUNT_POINT}"
            sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_INDEX}" "df -Th"
            sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_INDEX}" "sudo systemctl daemon-reload"
         done

         # Testing
         log_warning "\t\t- Testing the GlusterFS volume \"${VOLUME_NAME_ARG}\" on all nodes"
         sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "echo 'Hello World!' | sudo tee ${FINAL_MOUNT_POINT}/test.txt"

         for IP_INDEX in "${DISCOVERED_IPS[@]}"; do
             log_warning "\t\t- Checking the test file on host ${IP_INDEX} ..."
             sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_INDEX}" "cat ${FINAL_MOUNT_POINT}/test.txt"
             sleep 5
         done
     fi
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
  set -euo pipefail

  local LOGIN_ARG="${1}"
  local PASSWORD_ARG="${2}"
  local VOLUME_NAME_ARG="${3}"
  local SWARM_JSON_ARG="${4}"
  shift 4
  local HOSTNAME_LIST_ARG=("$@")

  if [ ${#HOSTNAME_LIST_ARG[@]} -eq 0 ]; then
    log_error "⚠️ Host list is empty."
    return 1
  fi

  # Config
  local GLUSTER_DIR="/gluster-${VOLUME_NAME_ARG}/bricks"
  local FINAL_MOUNT_POINT="/mnt/${VOLUME_NAME_ARG}"

  # Temp dir
  local GLUSTERFS_TMP_DIR
  GLUSTERFS_TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${GLUSTERFS_TMP_DIR}"' EXIT

  local ETC_HOSTS_FILE="${GLUSTERFS_TMP_DIR}/etc_hosts.addon"
  : > "${ETC_HOSTS_FILE}"

  # Resolve hosts -> IPs (preserve order for brick indices)
  local DISCOVERED_IPS=()
  for H in "${HOSTNAME_LIST_ARG[@]}"; do
    # Prefer your helper; fallback to getent if missing
    local IP="$(get_ip_by_hostname "${H}" "${SWARM_JSON_ARG}" 2>/dev/null || true)"
    if [[ -z "${IP}" ]]; then
      IP="$(getent hosts "${H}" | awk '{print $1}' | head -1)"
    fi
    if [[ -z "${IP}" ]]; then
      log_error "Failed to resolve IP for ${H}"
      return 1
    fi
    echo "${IP} ${H}" >> "${ETC_HOSTS_FILE}"
    DISCOVERED_IPS+=("${IP}")
  done

  local MASTER_IP_ADDRESS="${DISCOVERED_IPS[0]}"
  log_warning "Master for GlusterFS setup: ${MASTER_IP_ADDRESS} (${HOSTNAME_LIST_ARG[0]})"
  log_warning "Installing and preparing nodes: ${DISCOVERED_IPS[*]}"

  # Prepare each node: hosts entries, packages, brick dir, glusterd
  local idx=0
  for IPN in "${DISCOVERED_IPS[@]}"; do
    idx=$((idx+1))
    sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IPN}" bash -s <<EOF
set -euo pipefail
sudo mkdir -p /tmp
# Add all cluster hosts to /etc/hosts (idempotent)
while read -r LINE; do
  grep -qxF "\$LINE" /etc/hosts || echo "\$LINE" | sudo tee -a /etc/hosts >/dev/null
done < <(cat <<'EOT'
$(sed "s/'/'\"'\"'/g" "${ETC_HOSTS_FILE}")
EOT
)

# Create brick directory for this node (index ${idx})
sudo mkdir -p "${GLUSTER_DIR}/${idx}"
sudo chown root:root "${GLUSTER_DIR}/${idx}"
sudo chmod 755 "${GLUSTER_DIR}/${idx}"

# Ensure mount point for client usage
sudo mkdir -p "${FINAL_MOUNT_POINT}"

# Install gluster and start daemon
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
if ! dpkg -s glusterfs-server glusterfs-cli >/dev/null 2>&1; then
  sudo apt-get install -y -qq glusterfs-server glusterfs-cli
fi
sudo systemctl enable --now glusterd
# Wait for glusterd socket to be ready
for i in {1..20}; do
  systemctl is-active --quiet glusterd && break
  sleep 1
done
EOF
  done

  # Probe peers from master (skip self)
  for ip in "${DISCOVERED_IPS[@]}"; do
    [[ "${ip}" == "${MASTER_IP_ADDRESS}" ]] && continue
    log_warning "Probing ${ip} from ${MASTER_IP_ADDRESS}..."
    sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" \
      "sudo gluster peer probe ${ip} || true"
    sleep 1
  done

  # Wait for trusted pool
  log_debug "Waiting for trusted pool to form..."
  sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" bash -s <<'EOF'
set -euo pipefail
for i in {1..60}; do
  # Count peers "Peer in Cluster"
  OK=$(sudo gluster peer status 2>/dev/null | awk '/State: Peer in Cluster/{c++} END{print c+0}')
  # We expect all non-master peers to be up
  if [ "$OK" -ge '"$((${#DISCOVERED_IPS[@]}-1))"' ]; then
    exit 0
  fi
  sleep 1
done
echo "Peers did not all join in time" >&2
exit 1
EOF

  # Create volume if absent
  log_warning "Ensuring volume ${VOLUME_NAME_ARG} exists..."
  local CREATE_CMD="sudo gluster volume create ${VOLUME_NAME_ARG} replica ${#HOSTNAME_LIST_ARG[@]} transport tcp"
  idx=0
  for H in "${HOSTNAME_LIST_ARG[@]}"; do
    idx=$((idx+1))
    CREATE_CMD="${CREATE_CMD} ${H}:${GLUSTER_DIR}/${idx}"
  done
  CREATE_CMD="${CREATE_CMD} force"

  sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" bash -s <<EOF
set -euo pipefail
if ! sudo gluster volume info "${VOLUME_NAME_ARG}" >/dev/null 2>&1; then
  ${CREATE_CMD}
fi
# Start if not started
STATE=\$(sudo gluster volume info "${VOLUME_NAME_ARG}" | awk -F': ' '/Status:/ {print \$2; exit}')
if [ "\$STATE" != "Started" ]; then
  sudo gluster volume start "${VOLUME_NAME_ARG}"
fi
EOF

  # Align auth.allow with node IP mounts (no localhost)
  local ALLOW_LIST
  ALLOW_LIST="$(IFS=, ; echo "${DISCOVERED_IPS[*]}")"
  sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" \
    "sudo gluster volume set ${VOLUME_NAME_ARG} auth.allow ${ALLOW_LIST}"

  # Mount on each node using its own IP as primary server, with backup to master
  log_debug "Mounting ${VOLUME_NAME_ARG} on all nodes at ${FINAL_MOUNT_POINT}"
  idx=0
  for IPN in "${DISCOVERED_IPS[@]}"; do
    idx=$((idx+1))
    # Choose a backup volfile server different from the node; default to master
    local BACKUP="${MASTER_IP_ADDRESS}"
    if [[ "${IPN}" == "${BACKUP}" && ${#DISCOVERED_IPS[@]} -gt 1 ]]; then
      for CAND in "${DISCOVERED_IPS[@]}"; do
        [[ "${CAND}" != "${IPN}" ]] && BACKUP="${CAND}" && break
      done
    fi
    local MOUNTLINE="${IPN}:/${VOLUME_NAME_ARG} ${FINAL_MOUNT_POINT} glusterfs defaults,_netdev,backupvolfile-server=${BACKUP} 0 0"

    sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IPN}" bash -s <<EOF
set -euo pipefail
sudo mkdir -p "${FINAL_MOUNT_POINT}"
# Remove any previous fstab line for this mountpoint (idempotent)
sudo sed -i '\#[[:space:]]${FINAL_MOUNT_POINT}[[:space:]]#d' /etc/fstab
echo '${MOUNTLINE}' | sudo tee -a /etc/fstab >/dev/null
sudo systemctl daemon-reload
# Mount (or remount) now
if mountpoint -q "${FINAL_MOUNT_POINT}"; then
  sudo umount "${FINAL_MOUNT_POINT}" || true
fi
sudo mount -a
EOF
    sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IPN}" "mount | grep '${FINAL_MOUNT_POINT}' || (echo 'Mount failed on ${IPN}' >&2; exit 1)"
  done

  # Sanity test: write on master, read everywhere
  log_warning "Testing replication on ${VOLUME_NAME_ARG}..."
  local TS
  TS="$(date +%s)"
  sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" \
    "echo 'Hello ${VOLUME_NAME_ARG} ${TS}' | sudo tee '${FINAL_MOUNT_POINT}/test-${TS}.txt' >/dev/null"

  for IPN in "${DISCOVERED_IPS[@]}"; do
    log_warning "Checking from ${IPN}..."
    sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IPN}" \
      "sudo cat '${FINAL_MOUNT_POINT}/test-${TS}.txt' | sed -n '1p'"
  done

  log_warning "GlusterFS setup complete for volume ${VOLUME_NAME_ARG}."
}
