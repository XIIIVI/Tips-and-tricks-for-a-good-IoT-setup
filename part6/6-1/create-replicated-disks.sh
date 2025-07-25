#!/bin/bash

source "../../commons/commons-cli.sh"
source "../../commons/commons-log.sh"
source "../../commons/commons-net.sh"
source "../../commons/commons-ssh.sh"

# === Usage function ===
display_help() {
    log_debug "Usage: $0 --login=<LOGIN>"
    log_debug "          --password=<PASSWORD>"
    log_debug "          --subnet=<xxx.xxx.xxx>"
    log_debug "         [--manager-hostname-prefix=<PREFIX> (orchestrator by default)]"
    log_debug "         [--volume-name=<VOLUME_NAME> (gfs by default)"]
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
    log_debug "MANAGER_HOSTNAME_PREFIX: ${MANAGER_HOSTNAME_PREFIX}"
    log_debug "SUBNET                 : ${SUBNET}"
    log_debug "VOLUME_NAME            : ${VOLUME_NAME}"
}

#
# main
#
main() {
    MANDATORY_PARAMETER_LIST=("LOGIN" "PASSWORD" "SUBNET")

    for ARG in "$@"; do
        case $ARG in
        --manager-hostname-prefix=*)
            MANAGER_HOSTNAME_PREFIX="${ARG#*=}"
            shift
            ;;
        --login=*)
            LOGIN="${ARG#*=}"
            shift
            ;;
        --password=*)
            PASSWORD="${ARG#*=}"
            shift
            ;;
        --subnet=*)
            SUBNET="${ARG#*=}"
            if [[ ! "$SUBNET" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                log_error "❌ Invalid subnet format. Use xxx.xxx.xxx."
                exit 1
            fi
            shift
            ;;
        --volume-name=*)
            VOLUME_NAME="${ARG#*=}"
            shift
            ;;
        *)
            echo "Unknown argument: $ARG"
            usage
            ;;
        esac
    done

    local MANAGER_HOSTNAME_PREFIX="${MANAGER_HOSTNAME_PREFIX:-orchestrator}"
    local VOLUME_NAME="${VOLUME_NAME:-gfs}"
    DISCOVERED_IPS=()
    ETC_HOSTS_FILE=/tmp/etc_hosts.addon
    ETC_FSTAB_FILE=/tmp/etc_fstab.addon
    GLUSTER_DIR="/gluster/bricks"
    COUNTER=1
    VOLUME_CREATION_SCRIPT=/tmp/glusterfs_volume_creation_script.sh

    # Clean up temp files
    rm -Rf "${ETC_HOSTS_FILE}" "${ETC_FSTAB_FILE}" "${VOLUME_CREATION_SCRIPT}"
    touch "${ETC_HOSTS_FILE}" "${ETC_FSTAB_FILE}" "${VOLUME_CREATION_SCRIPT}"

    check_all_mandatory_parameters "${MANDATORY_PARAMETER_LIST[@]}"
    display_settings

    # Initializing the script glusterfs_volume_creation_script.sh
    cat << SCRIPT_EOF >> "${VOLUME_CREATION_SCRIPT}"
#!/bin/bash

gluster volume create ${VOLUME_NAME} replica 3 \\
SCRIPT_EOF

    log_info "Installing required packages"
    apt-get install -qq -y dnsutils

    log_info "Looking for managers with prefix ${MANAGER_HOSTNAME_PREFIX} in the subnet ${SUBNET} ..."
    COUNTER=1

    for i in {1..254}; do
        IP="${SUBNET}.${i}"

        # Print current IP being checked (overwrites the same line)
        log_progress_bar "🔍 Testing ${IP} ..." "$((i + 1))" 254

        if ping -c 1 -W 1 "$IP" &>/dev/null; then
            HOSTNAME=$(dig +short -x "$IP" | sed 's/\.$//')

            if [[ "$HOSTNAME" =~ ${MANAGER_HOSTNAME_PREFIX} ]]; then
                log_progress_bar "🔍 Testing ${IP} ..." "$((i + 1))" 254 " => Found the candidate ${HOSTNAME} (${IP})"

                DISCOVERED_IPS+=("${IP}")
            
                echo "${IP} ${HOSTNAME}" >>"${ETC_HOSTS_FILE}"
                echo "${HOSTNAME}:/$VOLUME_NAME  ${GLUSTER_DIR}/${COUNTER}  glusterfs  defaults,_netdev  0  0" >> "${ETC_FSTAB_FILE}"
                printf "%s" "${HOSTNAME}:${GLUSTER_DIR}/${COUNTER}/brick " >> "${VOLUME_CREATION_SCRIPT}"
                
                COUNTER=$((COUNTER + 1))
            fi
        fi
    done

    printf "%s" " force" >> "${VOLUME_CREATION_SCRIPT}"

    unset COUNTER

    if [ ${#DISCOVERED_IPS[@]} -eq 0 ]; then
        log_error "⚠️ No orchestrator nodes found. Aborting setup."
    else
        log_info "\n\nSetting up GlusterFS on discovered hosts: ${DISCOVERED_IPS[*]}"
        COUNTER=1

        for IP_INDEX in "${DISCOVERED_IPS[@]}"; do
            remove_ssh_host "${IP_INDEX}"

            log_warning "\t\t- Declaring the GlusterFS member to /etc/hosts"
            copy_file_to_host "${LOGIN}" "${PASSWORD}" "${IP_INDEX}" "${ETC_HOSTS_FILE}" "/tmp"
            sshpass -p "${PASSWORD}" ssh -o StrictHostKeyChecking=no "${LOGIN}@${IP_INDEX}" "sudo tee -a /etc/hosts < /tmp/$(basename ${ETC_HOSTS_FILE})"

            log_warning "\t\t- Declaring the GlusterFS member to /etc/fstab"
            copy_file_to_host "${LOGIN}" "${PASSWORD}" "${IP_INDEX}" "${ETC_FSTAB_FILE}" "/tmp"
            sshpass -p "${PASSWORD}" ssh -o StrictHostKeyChecking=no "${LOGIN}@${IP_INDEX}" "sudo tee -a /etc/fstab < /tmp/$(basename ${ETC_FSTAB_FILE})"

            log_warning "\t\t- Installing GlusterFS on ${IP_INDEX}"
            sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$LOGIN@$IP_INDEX" <<EOF_GLUSTERFS
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
        for ((INDEX = 1; INDEX < ${#DISCOVERED_IPS[@]}; INDEX++)); do
            IP_INDEX="${DISCOVERED_IPS[$INDEX]}"
            log_debug "\t\t- Probing host ${IP_INDEX} ..."
            sshpass -p "${PASSWORD}" ssh "${LOGIN}@${DISCOVERED_IPS[0]}" "sudo gluster peer probe ${IP_INDEX}"
            sleep 5
        done

        # Waiting for the ppers
        log_info "⏳ Waiting for peers to join trusted pool..."
        sleep 5
        sshpass -p "${PASSWORD}" ssh "${LOGIN}@${DISCOVERED_IPS[0]}" "sudo gluster peer status"        

        # Creating the volume
        log_debug "\t\t- Setting up th GlusterFS volume with the following script: ${VOLUME_CREATION_SCRIPT}"
        log_warning "\t\t\t- Creating the volume ${VOLUME_NAME}"
        copy_file_to_host "${LOGIN}" "${PASSWORD}" "${DISCOVERED_IPS[0]}" "${VOLUME_CREATION_SCRIPT}" "/tmp"
        sshpass -p "${PASSWORD}" ssh -o StrictHostKeyChecking=no "${LOGIN}@${DISCOVERED_IPS[0]}" "sudo bash /tmp/$(basename ${VOLUME_CREATION_SCRIPT})"
        log_warning "\t\t\t- Starting the volume ${VOLUME_NAME}"
        sshpass -p "${PASSWORD}" ssh "${LOGIN}@${DISCOVERED_IPS[0]}" "sudo gluster volume start ${VOLUME_NAME}"
        log_warning "\t\t\t- Status of the volume ${VOLUME_NAME}"
        sshpass -p "${PASSWORD}" ssh "${LOGIN}@${DISCOVERED_IPS[0]}" "sudo gluster volume status ${VOLUME_NAME}"
        log_warning "\t\t\t- Info of the volume ${VOLUME_NAME}"
        sshpass -p "${PASSWORD}" ssh "${LOGIN}@${DISCOVERED_IPS[0]}" "sudo gluster volume info ${VOLUME_NAME}"
        log_warning "\t\t\t- Setup security and authentication for the volume ${VOLUME_NAME}"
        sshpass -p "${PASSWORD}" ssh "${LOGIN}@${DISCOVERED_IPS[0]}" "sudo gluster volume set ${VOLUME_NAME} auth.allow $(IFS=, ; echo "${DISCOVERED_IPS[*]}")"

        # Mount the glusterFS volume where applications can access the files
        log_info "Mounting the GlusterFS volume ${VOLUME_NAME} on all nodes" 
        for IP_INDEX in "${DISCOVERED_IPS[@]}"; do
            log_debug "\t\t- Mounting the GlusterFS volume ${VOLUME_NAME} on ${IP_INDEX}"
            sshpass -p "${PASSWORD}" ssh -o StrictHostKeyChecking=no "${LOGIN}@${IP_INDEX}" \
                    "echo \"localhost:/${VOLUME_NAME} /mnt glusterfs defaults,_netdev,backupvolfile-server=localhost 0 0\" | sudo tee -a /etc/fstab > /dev/null"
            sshpass -p "${PASSWORD}" ssh -o StrictHostKeyChecking=no "${LOGIN}@${IP_INDEX}" "sudo mount.glusterfs localhost:/${VOLUME_NAME} /mnt"
            sshpass -p "${PASSWORD}" ssh -o StrictHostKeyChecking=no "${LOGIN}@${IP_INDEX}" "df -Th"
        done

        # Testing
        log_info "\t\t- Testing the GlusterFS volume ${VOLUME_NAME} on all nodes"
        sshpass -p "${PASSWORD}" ssh -o StrictHostKeyChecking=no "${LOGIN}@${DISCOVERED_IPS[0]}" "echo 'Hello World!' | sudo tee /mnt/test.txt"

        for IP_INDEX in "${DISCOVERED_IPS[@]}"; do
            log_info "\t\t- Checking test file on host ${IP_INDEX} ..."
            sshpass -p "${PASSWORD}" ssh "${LOGIN}@${IP_INDEX}" "cat /mnt/test.txt"
            sleep 5
        done
    fi
}

# === Track and report duration ===
time main "$@"
