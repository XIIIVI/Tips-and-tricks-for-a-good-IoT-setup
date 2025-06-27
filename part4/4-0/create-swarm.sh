#!/bin/bash

source "../../commons/commons-cli.sh"
source "../../commons/commons-docker.sh"
source "../../commons/commons-i2c.sh"
source "../../commons/commons-log.sh"
source "../../commons/commons-net.sh"
source "../../commons/commons-ssh.sh"

#
# display_help
#
display_help() {
    log_debug "Usage: ${0} --level0 <IPs> (comma-separated list)"
    log_debug "            --level1 <IPs> (comma-separated list)"
    log_debug "            --level2 <IPs> (comma-separated list)"
    log_debug "            --login <login>"
    log_debug "            --password <password>"
    log_debug "            [--default-hostname <Hostname> (by default, set to \"undefined\")]"
    log_debug "            [--swarm-first-ip-address <IP>]"
    log_debug "            [--uctronics-rack]"
}

#
# display_settings
#
display_settings() {
    log_debug "S E T T I N G S"
    log_debug "DEFAULT_HOSTNAME: ${DEFAULT_HOSTNAME}"
    log_debug "LEVEL_0_IPS     : ${LEVEL_0_IPS}"
    log_debug "LEVEL_1_IPS     : ${LEVEL_1_IPS}"
    log_debug "LEVEL_2_IPS     : ${LEVEL_2_IPS}"
    log_debug "LOGIN           : ${LOGIN}"
    log_debug "START_IP_ADDRESS: ${START_IP_ADDRESS}"
    log_debug "UCTRONICS_RACK  : ${UCTRONICS_RACK}"
}

#
# set_hostname
#
set_hostname() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local HOSTNAME_ARG="${3}"
    local NODE_IP_ARG="${4}"

    log_warning "\t\t- Setting hostname to ${HOSTNAME_ARG} on node ${NODE_IP_ARG}"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${NODE_IP_ARG}" "sudo hostnamectl set-hostname ${HOSTNAME_ARG}"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${NODE_IP_ARG}" "sudo sed -i 's/${DEFAULT_HOSTNAME}/${HOSTNAME_ARG}/' /etc/hosts"
}

#
# create_swarm_manager
#
create_swarm_manager() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local NODE_HOSTNAME_ARG="orchestrator${3}"
    local MANAGER_IP_ARG="${4}"

    if [ -z "${JOIN_WORKER_CMD}" ]; then
        log_debug "\t- Creating the Swarm"
        set_hostname "${LOGIN_ARG}" "${PASSWORD_ARG}" "${NODE_HOSTNAME_ARG}" "${MANAGER_IP_ARG}"
        install_docker "${LOGIN_ARG}" "${PASSWORD_ARG}" "${MANAGER_IP_ARG}"

        sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MANAGER_IP_ARG}" "sudo docker swarm init --advertise-addr ${MANAGER_IP_ARG}"
        JOIN_WORKER_CMD=$(sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MANAGER_IP_ARG}" "sudo docker swarm join-token -q manager | grep -Po 'docker swarm join --token .* \d+\.\d+\.\d+\.\d+:\d+'")
        MAIN_MANAGER_IP_ADDRESS="${MANAGER_IP_ARG}"
        JOIN_MGR_CMD=$(sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" "sudo docker swarm join-token manager | grep -A 1 'docker swarm join' | tr -d '\\\\' | xargs")

        log_debug "\t- Saving the Swarm token to ${JOIN_WORKER_CMD_FILE}"
        echo "${JOIN_WORKER_CMD}" >"${JOIN_WORKER_CMD_FILE}"

        log_debug "\t- Saving the manager's IP address to ${MANAGER_IP_ADDRESS_FILE}"
        echo "${MAIN_MANAGER_IP_ADDRESS}" >"${MANAGER_IP_ADDRESS_FILE}"

        log_debug "\t- Saving the join manager command to ${JOIN_MANAGER_CMD_FILE}"
        echo "${JOIN_MGR_CMD}" >"${JOIN_MANAGER_CMD_FILE}"
    else
        log_debug "\t- Swarm already created, using existing token to add a new manager"
        install_docker "${LOGIN_ARG}" "${PASSWORD_ARG}" "${MANAGER_IP_ARG}"
        set_hostname "${LOGIN_ARG}" "${PASSWORD_ARG}" "${NODE_HOSTNAME_ARG}" "${MANAGER_IP_ARG}"

        log_warning "\t\t- Adding the manager ${NODE_HOSTNAME_ARG} to the Swarm"
        sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MANAGER_IP_ARG}" "sudo ${JOIN_MGR_CMD}"
    fi

    log_warning "\t\t- Creating the folders"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MANAGER_IP_ARG}" "sudo mkdir -p /data/alloy /data/database /data/telegraf"

    if [[ "${UCTRONICS_RACK}" == true ]]; then
        install_uctronics_pi_rack "${LOGIN_ARG}" "${PASSWORD_ARG}" "${MANAGER_IP_ARG}" "./data"
    fi

    change_ip_address "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_INDEX}"

    log_debug "\t- Rebooting the manager now"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MANAGER_IP_ARG}" "sudo shutdown -r now"

    wait_for_device "${NODE_HOSTNAME_ARG}"

    log_warning "\t\t- Adding the labels to the manager"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MANAGER_IP_ARG}" "sudo docker node update --label-add level=0 --label-add mqtt=true ${NODE_HOSTNAME_ARG}"

    log_warning "########################"
    log_warning "# Content of the Swarm #"
    log_warning "########################"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" "sudo docker node ls"
}

#
# create_swarm
#
create_swarm() {
    local LOGIN="$1"
    local PASSWORD="$2"
    local -n IPS_ARG=$3
    local INDEX_IN_ROW=0

    log_info "+++++++++++++++++++++++++++++++"
    log_info "|                             |"
    log_info "| CREATING THE SWARM MANAGERS |"
    log_info "|                             |"
    log_info "+++++++++++++++++++++++++++++++"

    for IP_INDEX in "${IPS_ARG[@]}"; do
        ((INDEX_IN_ROW++))

        # Remove the old host key
        ssh-keygen -f "/root/.ssh/known_hosts" -R "${IP_INDEX}"

        # Optionally fetch and add the new host key (safer than disabling checking)
        ssh-keyscan -H "${IP_INDEX}" >>/root/.ssh/known_hosts

        create_swarm_manager "${LOGIN}" "${PASSWORD}" "${INDEX_IN_ROW}" "${IP_INDEX}"
    done
}

#
# create_workers
#
create_workers() {
    local LOGIN_ARG="$1"
    local PASSWORD_ARG="$2"
    local LEVEL_ARG="$3"
    local -n IPS_ARG=$4
    local INDEX_IN_ROW=0

    log_info "++++++++++++++++++++++++++"
    log_info "|                        |"
    log_info "| CREATING THE WORKERS   |"
    log_info "|                        |"
    log_info "++++++++++++++++++++++++++"

    if [ -n "${JOIN_WORKER_CMD}" ]; then

        for IP_INDEX in "${IPS_ARG[@]}"; do
            local NODE_HOSTNAME

            ((INDEX_IN_ROW++))

            NODE_HOSTNAME="sat${INDEX_IN_ROW}"

            # Remove the old host key
            ssh-keygen -f "/root/.ssh/known_hosts" -R "${IP_INDEX}"

            # Optionally fetch and add the new host key (safer than disabling checking)
            ssh-keyscan -H "${IP_INDEX}" >>/root/.ssh/known_hosts

            set_hostname "${LOGIN_ARG}" "${PASSWORD_ARG}" "${NODE_HOSTNAME}" "${IP_INDEX}"
            install_docker "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_INDEX}"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_INDEX}" "sudo ${JOIN_WORKER_CMD}"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_INDEX}" "sudo mkdir -p /data/alloy /data/telegraf"

            if [[ "${UCTRONICS_RACK}" == true ]]; then
                install_uctronics_pi_rack "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_INDEX}" "./data"
            fi

            change_ip_address "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_INDEX}"

            log_debug "\t- Rebooting the worker now"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_INDEX}" "sudo shutdown -r now"

            wait_for_device "${NODE_HOSTNAME}"

            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_INDEX}" "sudo docker node update --label-add level=${LEVEL_ARG} ${NODE_HOSTNAME}"

            log_warning "########################"
            log_warning "# Content of the Swarm #"
            log_warning "########################"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" "sudo docker node ls"
        done
    fi
}

#
# wait_for_device
#
wait_for_device() {
    local REMOTE_HOST_ARG="${1}"

    # Wait for the device to go down and come back up
    log_warning "\t\t- Waiting for device ${REMOTE_HOST_ARG} to reboot..."
    while ! ping -c 1 "${REMOTE_HOST_ARG}" &>/dev/null; do
        sleep 5
    done

    # Optional: wait a bit longer to ensure services are up
    sleep 30
    log_warning "\t\t- ${REMOTE_HOST_ARG} is back online!"
}

#
# main
#
main() {
    MANDATORY_PARAMETER_LIST=("LEVEL_0_IPS" "LEVEL_1_IPS" "LEVEL_1_IPS" "LOGIN" "PASSWORD")
    JOIN_WORKER_CMD_FILE="./join_worker_cmd.swarm"
    MANAGER_IP_ADDRESS_FILE="./ip.swarm"
    JOIN_MANAGER_CMD_FILE="./join_mgr_cmd.swarm"

    # Parses the parameters
    while (("$#")); do
        case "$1" in
        --default-hostname)
            DEFAULT_HOSTNAME="${2}"
            shift # past argument
            shift # past value
            ;;
        --level0)
            IFS=',' read -r -a LEVEL_0_IPS <<<"$2"
            shift
            ;;
        --level1)
            IFS=',' read -r -a LEVEL_1_IPS <<<"$2"
            shift
            ;;
        --level2)
            IFS=',' read -r -a LEVEL_2_IPS <<<"$2"
            shift
            ;;
        --login)
            LOGIN="${2}"
            shift # past argument
            shift # past value
            ;;
        --password)
            PASSWORD="${2}"
            shift # past argument
            shift # past value
            ;;
        --swarm-first-ip-address)
            START_IP_ADDRESS="${2}"
            shift # past argument
            shift # past value
            ;;
        --uctronics-rack)
            UCTRONICS_RACK=true
            shift # past argument
            ;;
        -h | --help)
            display_help
            shift # past argument
            exit 1
            ;;
        --) # end argument parsing
            shift
            break
            ;;
        *) # preserve positional arguments
            shift
            ;;
        esac
    done

    UCTRONICS_RACK=${UCTRONICS_RACK:-false}
    DEFAULT_HOSTNAME=${DEFAULT_HOSTNAME:-"undefined"}

    # Initialize variables from values saved in files
    if [[ -s "${JOIN_WORKER_CMD_FILE}" ]]; then
        log_info "Loading the Swarm token"

        JOIN_WORKER_CMD=$(<"${JOIN_WORKER_CMD_FILE}")
    fi

    if [[ -s "${MANAGER_IP_ADDRESS_FILE}" ]]; then
        log_info "Loading the manager's IP address"

        MAIN_MANAGER_IP_ADDRESS=$(<"${MANAGER_IP_ADDRESS_FILE}")
    fi

    if [[ -s "${JOIN_MANAGER_CMD_FILE}" ]]; then
        log_info "Loading the manager's IP address"

        JOIN_MGR_CMD=$(<"${JOIN_MANAGER_CMD_FILE}")
    fi

    # Check all mandatory parameter are set
    check_all_mandatory_parameters "${MANDATORY_PARAMETER_LIST[@]}"

    display_settings

    # Installing required packages
    apt-get install -y sshpass

    create_swarm "$LOGIN" "${PASSWORD}" LEVEL_0_IPS
    create_workers "$LOGIN" "${PASSWORD}" 1 LEVEL_1_IPS
}

time main "$@"
