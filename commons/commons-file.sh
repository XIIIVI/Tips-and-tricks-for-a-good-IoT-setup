#!/bin/bash

#
# setup_replicated_volumes
#
# This function sets up replicated disks using GlusterFS on a list of hosts.
# It requires the login credentials and a list of hostnames to operate.
# Arguments:
#   1. LOGIN_ARG: The username for SSH login.
#   2. PASSWORD_ARG: The password for SSH login.
#   3. VOLUME_NAME_ARG: The name of the GlusterFS volume to create.
#   4. MOUNT_SUBFOLDER_ARG: An optional subfolder under /mnt where the GlusterFS volume will be mounted.
#   5. HOSTNAME_LIST_ARG: An array of hostnames where the GlusterFS volume will be set up.
#
setup_replicated_volumes() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local VOLUME_NAME_ARG="${3}"
    local MOUNT_SUBFOLDER_ARG="${4}"
    shift 4
    local HOSTNAME_LIST_ARG=("$@")
    local FINAL_MOUNT_POINT="/mnt"

    # Default to just /mnt if not specified
    if [[ -n "${MOUNT_SUBFOLDER_ARG}" ]]; then
         FINAL_MOUNT_POINT="${FINAL_MOUNT_POINT}/${MOUNT_SUBFOLDER_ARG}"
    fi

    if [ ${#HOSTNAME_LIST_ARG[@]} -eq 0 ]; then
        log_error "\t⚠️ The list of hosts is empty."
    else
         local ETC_HOSTS_FILE=/tmp/etc_hosts.addon
         local ETC_FSTAB_FILE=/tmp/etc_fstab.addon
         local GLUSTER_DIR="/gluster/bricks"
         local COUNTER=1
         local VOLUME_CREATION_SCRIPT=/tmp/glusterfs_volume_creation_script.sh
         local MASTER_IP_ADDRESS

         MASTER_IP_ADDRESS=$(host "${HOSTNAME_LIST_ARG[0]}" | awk '/has address/ { print $4 }')

         log_debug "\t- Setting up replicated disks with GlusterFS"

         # Clean up temp files
         rm -Rf "${ETC_HOSTS_FILE}" "${ETC_FSTAB_FILE}" "${VOLUME_CREATION_SCRIPT}"
         touch "${ETC_HOSTS_FILE}" "${ETC_FSTAB_FILE}" "${VOLUME_CREATION_SCRIPT}"

         # Initializing the script glusterfs_volume_creation_script.sh
         cat << SCRIPT_EOF >> "${VOLUME_CREATION_SCRIPT}"
#!/bin/bash

gluster volume create ${VOLUME_NAME_ARG} replica ${#HOSTNAME_LIST_ARG[@]} \\
SCRIPT_EOF

         log_warning "\t\t- Installing required packages"
         apt-get install -qq -y dnsutils

         log_warning "\t\t- Setting up /etc/hosts and /etc/fstab files for GlusterFS volume ${VOLUME_NAME_ARG}"
         COUNTER=1

         for HOSTNAME in "${HOSTNAME_LIST_ARG[@]}"; do
             local IP_INDEX

             IP_INDEX=$(host "${HOSTNAME}" | awk '/has address/ { print $4 }')

             echo "${IP_INDEX} ${HOSTNAME}" >>"${ETC_HOSTS_FILE}"
             echo "${HOSTNAME}:/$VOLUME_NAME_ARG  ${GLUSTER_DIR}/${COUNTER}  glusterfs  defaults,_netdev  0  0" >> "${ETC_FSTAB_FILE}"
             printf "%s" "${HOSTNAME}:${GLUSTER_DIR}/${COUNTER}/brick " >> "${VOLUME_CREATION_SCRIPT}"
                
             COUNTER=$((COUNTER + 1))
         done

         printf "%s" " force" >> "${VOLUME_CREATION_SCRIPT}"

         unset COUNTER

         log_warning "\t\t- Setting up GlusterFS on discovered hosts: ${DISCOVERED_IPS[*]}"
         COUNTER=1

         for HOSTNAME in "${HOSTNAME_LIST_ARG[@]}"; do
             local IP_INDEX

             IP_INDEX=$(host "${HOSTNAME}" | awk '/has address/ { print $4 }')

             remove_ssh_host "${IP_INDEX}"

             log_warning "\t\t\t- Declaring the GlusterFS member to /etc/hosts"
             copy_file_to_host "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_INDEX}" "${ETC_HOSTS_FILE}" "/tmp"
             sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_INDEX}" "sudo tee -a /etc/hosts < /tmp/$(basename ${ETC_HOSTS_FILE})"

             log_warning "\t\t\t- Declaring the GlusterFS member to /etc/fstab"
             copy_file_to_host "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_INDEX}" "${ETC_FSTAB_FILE}" "/tmp"
             sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_INDEX}" "sudo tee -a /etc/fstab < /tmp/$(basename ${ETC_FSTAB_FILE})"

             log_warning "\t\t\t- Installing GlusterFS on ${IP_INDEX}"
             sshpass -p "$PASSWORD_ARG" ssh -o StrictHostKeyChecking=no "$LOGIN_ARG@$IP_INDEX" <<EOF_GLUSTERFS
    export DEBIAN_FRONTEND=noninteractive
    export DEBCONF_NOWARNINGS=yes 

    sudo mkdir -p "${GLUSTER_DIR}/${COUNTER}"

    sudo -E apt update -qq
    sudo -E apt install glusterfs-server -y -qq \
         -o Dpkg::Progress-Fancy="0" \
         -o Dpkg::Use-Pty="0"
    sudo systemctl enable glusterd
    sudo systemctl start glusterd

    sudo mount -a
    sudo mkdir -p "${GLUSTER_DIR}/${COUNTER}/brick"
EOF_GLUSTERFS

             COUNTER=$((COUNTER + 1))
         done

         unset COUNTER

         # Probing the peers
         for ((INDEX = 1; INDEX < ${#HOSTNAME_LIST_ARG[@]}; INDEX++)); do
             local IP_INDEX

             IP_INDEX=$(host "${HOSTNAME_LIST_ARG[INDEX]}" | awk '/has address/ { print $4 }')
             log_warning "\t\t- Probing host ${IP_INDEX} ..."
             sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "sudo gluster peer probe ${IP_INDEX}"
             sleep 5
         done

         # Waiting for the ppers
         log_debug "\t⏳ Waiting for peers to join trusted pool..."
         sleep 5
         sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "sudo gluster peer status"        

         # Creating the volume
         log_warning "\t\t- Setting up th GlusterFS volume with the following script: ${VOLUME_CREATION_SCRIPT}"
         log_warning "\t\t\t- Creating the volume ${VOLUME_NAME_ARG}"
         copy_file_to_host "${LOGIN_ARG}" "${PASSWORD_ARG}" "${MASTER_IP_ADDRESS}" "${VOLUME_CREATION_SCRIPT}" "/tmp"
         sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "sudo bash /tmp/$(basename ${VOLUME_CREATION_SCRIPT})"
         log_warning "\t\t\t- Starting the volume ${VOLUME_NAME_ARG}"
         sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "sudo gluster volume start ${VOLUME_NAME_ARG}"
         log_warning "\t\t\t- Status of the volume ${VOLUME_NAME_ARG}"
         sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "sudo gluster volume status ${VOLUME_NAME_ARG}"
         log_warning "\t\t\t- Info of the volume ${VOLUME_NAME_ARG}"
         sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "sudo gluster volume info ${VOLUME_NAME_ARG}"
         log_warning "\t\t\t- Setup security and authentication for the volume ${VOLUME_NAME_ARG}"
         sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "sudo gluster volume set ${VOLUME_NAME_ARG} auth.allow $(IFS=, ; echo "${DISCOVERED_IPS[*]}")"

         # Mount the glusterFS volume where applications can access the files
         log_debug "\t- Mounting the GlusterFS volume ${VOLUME_NAME_ARG} on all nodes" 
         for HOSTNAME in "${HOSTNAME_LIST_ARG[@]}"; do
             local IP_INDEX

             IP_INDEX=$(host "${HOSTNAME}" | awk '/has address/ { print $4 }')
            log_warning "\t\t- Mounting the GlusterFS volume ${VOLUME_NAME_ARG} on ${IP_INDEX}"
            sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_INDEX}" \
                    "echo \"localhost:/${VOLUME_NAME_ARG} ${FINAL_MOUNT_POINT} glusterfs defaults,_netdev,backupvolfile-server=localhost 0 0\" | sudo tee -a /etc/fstab > /dev/null"
            sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_INDEX}" "sudo mount.glusterfs localhost:/${VOLUME_NAME_ARG} ${FINAL_MOUNT_POINT}"
            sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_INDEX}" "df -Th"
         done

         # Testing
         log_warning "\t\t- Testing the GlusterFS volume ${VOLUME_NAME_ARG} on all nodes"
         sshpass -p "${PASSWORD_ARG}" ssh -o StrictHostKeyChecking=no "${LOGIN_ARG}@${MASTER_IP_ADDRESS}" "echo 'Hello World!' | sudo tee ${FINAL_MOUNT_POINT}/test.txt"

         for IP_INDEX in "${HOSTNAME_LIST_ARG[@]}"; do
             local IP_INDEX

             IP_INDEX=$(host "${HOSTNAME_LIST_ARG[INDEX]}" | awk '/has address/ { print $4 }')

             log_warning "\t\t- Checking test file on host ${IP_INDEX} ..."
             sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_INDEX}" "cat ${FINAL_MOUNT_POINT}/test.txt"
             sleep 5
         done
     fi
}