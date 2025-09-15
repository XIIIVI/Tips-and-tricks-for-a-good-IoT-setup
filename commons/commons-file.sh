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
setup_replicated_volumes() {
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
         local GLUSTERFS_CREATE_CMD="sudo /usr/sbin/gluster volume create replicated-data replica ${#HOSTNAME_LIST_ARG[@]} transport tcp"

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
             echo "${HOSTNAME}:/$VOLUME_NAME_ARG  ${GLUSTER_DIR}/${COUNTER}  glusterfs  defaults,_netdev  0  0" >> "${ETC_FSTAB_FILE}"

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

         # Mount the glusterFS volume where applications can access the files
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