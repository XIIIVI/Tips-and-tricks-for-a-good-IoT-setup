#!/bin/bash

source "../../commons-cli.sh"
source "../../commons-log.sh"
source "../../commons-docker.sh"

#
# display_help
#
display_help() {
    log_debug "Usage: ${0} --level0 <IPs> (comma-separated list)"
    log_debug "            --level1 <IPs> (comma-separated list)"
    log_debug "            --level2 <IPs> (comma-separated list)"
    log_debug "            --login <login>"
    log_debug "            --password <password>"
    log_debug "            --swarm-first-ip-address <IP>"
}

#
# display_settings
#
display_settings() {
    log_debug "S E T T I N G S"
    log_debug "LEVEL_0_IPS           : ${LEVEL_0_IPS}"
    log_debug "LEVEL_1_IPS           : ${LEVEL_1_IPS}"
    log_debug "LEVEL_2_IPS           : ${LEVEL_2_IPS}"
    log_debug "LOGIN                 : ${LOGIN}"
    log_debug "SWARM_FIRST_MANAGER_IP_ADDRESS: ${SWARM_FIRST_MANAGER_IP_ADDRESS}"
}

#
# set_hostname
#
set_hostname() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local HOSTNAME_ARG="${3}"
    local NODE_IP_ARG="${4}"

    log_debug "\t\t- Setting hostname to ${HOSTNAME_ARG} on node ${NODE_IP_ARG}"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${NODE_IP_ARG}" "hostnamectl set-hostname ${HOSTNAME_ARG}"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${NODE_IP_ARG}" "sed -i 's/undefined/${HOSTNAME_ARG}/' /etc/hosts"
}

#
# create_swarm_manager
#
create_swarm_manager() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local NODE_HOSTNAME_ARG="orchestrator${3}"
    local MANAGER_IP_ARG="${4}"

    install_docker "${MANAGER_IP_ARG}" "${LOGIN_ARG}" "${PASSWORD_ARG}"

    if [ -z "${SWARM_TOKEN}" ]; then
        log_debug "\t- Creating the Swarm"
        set_hostname "${LOGIN_ARG}" "${PASSWORD_ARG}" "${NODE_HOSTNAME_ARG}" "${MANAGER_IP_ARG}"
        sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${FIRST_MANAGER_IP_ARG}" "docker swarm init --advertise-addr ${FIRST_MANAGER_IP_ARG}"
        SWARM_TOKEN=$(sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${FIRST_MANAGER_IP_ARG}" "docker swarm join-token -q manager")
        MANAGER_IP_ADDRESS="${MANAGER_IP_ARG}"
    else
        log_debug "\t- Swarm already created, using existing token to add a new manager"
        set_hostname "${LOGIN_ARG}" "${PASSWORD_ARG}" "${NODE_HOSTNAME_ARG}" "${MANAGER_IP_ARG}"
        sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${FIRST_MANAGER_IP_ARG}" "docker swarm join --token ${SWARM_TOKEN} manager"
    fi

    log_debug "\t\t- Adding the labels to the manager"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${FIRST_MANAGER_IP_ARG}" "docker node update --label-add level=0 --label-add mqtt=true ${NODE_HOSTNAME_ARG}"

    log_debug "\t\t- Creating the folders"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${FIRST_MANAGER_IP_ARG}" "mkdir -p /data/telegraf /data/database"
}

#
# create_workers
#
create_workers() {
    local LOGIN_ARG="$1"
    local PASSWORD_ARG="$2"
    local -n IPS_ARG=$3
    local INDEX_IN_ROW=0

    log_info "++++++++++++++++++++++++++"
    log_info "|                        |"
    log_info "| CREATING THE WORKERS   |"
    log_info "|                        |"
    log_info "++++++++++++++++++++++++++"

    for IP_INDEX in "${IPS_ARG[@]}"; do
        ((INDEX_IN_ROW++))

        local NODE_HOSTNAME="sat${INDEX_IN_ROW}"

        install_docker "${IP_INDEX}" "${LOGIN_ARG}" "${PASSWORD_ARG}"
        set_hostname "${LOGIN_ARG}" "${PASSWORD_ARG}" "${NODE_HOSTNAME}" "${IP_INDEX}"
        sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_INDEX}" "docker swarm join --token ${SWARM_TOKEN} ${MANAGER_IP_ADDRESS}"
        sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_INDEX}" "docker node update --label-add level=${LEVEL_ARG} ${NODE_HOSTNAME}"
        sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_INDEX}" "mkdir -p /data/telegraf"
    done
}

#
# create_swarm
#
create_swarm() {
    local LOGIN="$1"
    local PASSWORD="$2"
    local -n IPS_ARG=$3
    local INDEX_IN_ROW=0

    log_info "++++++++++++++++++++++"
    log_info "|                    |"
    log_info "| CREATING THE SWARM |"
    log_info "|                    |"
    log_info "++++++++++++++++++++++"

    for IP_INDEX in "${IPS_ARG[@]}"; do
        ((INDEX_IN_ROW++))

        create_swarm_manager "${LOGIN}" "${PASSWORD}" "${INDEX_IN_ROW}" "${IP_INDEX}"
    done
}

#
# main
#
main() {
    MANDATORY_PARAMETER_LIST=("LEVEL_0_IPS" "LEVEL_1_IPS" "LEVEL_1_IPS" "LOGIN" "PASSWORD")

    # Parses the parameters
    while (("$#")); do
        case "$1" in
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
            SWARM_FIRST_MANAGER_IP_ADDRESS="${2}"
            shift # past argument
            shift # past value
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

    # Check all mandatory parameter are set
    check_all_mandatory_parameters "${MANDATORY_PARAMETER_LIST[@]}"

    display_settings

    create_swarm "$LOGIN" "${PASSWORD}" "${LEVEL_0_IPS[@]}"
    create_workers "$LOGIN" "${PASSWORD}" "${LEVEL_1_IPS[@]}"
}

time main "$@"
