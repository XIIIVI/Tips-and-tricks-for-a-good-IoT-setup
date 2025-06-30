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
    log_debug "Usage: ${0} --configuration-file | -f <Configuration file>"
    log_debug "            [--default-hostname <Hostname> (by default, set to \"undefined\")]"
}

#
# display_settings
#
display_settings() {
    log_debug "S E T T I N G S"
    log_debug "CONFIGURATION_FILE: ${CONFIGURATION_FILE}"
    log_debug "DEFAULT_HOSTNAME  : ${DEFAULT_HOSTNAME}"
}

#
# create_single_manager
#
create_single_manager() {
    local LOGIN_ARG="$1"
    local PASSWORD_ARG="$2"
    local HOSTNAME_DEFAULT_PREFIX_ARG="$3"
    local JSON_OBJECT_ARG="$4"
    local INDEX_ARG="$5"
    local IP_ADDRESS

    IP_ADDRESS=$(echo "$JSON_OBJECT_ARG" | jq -r '.["ip-address"]')

    if ping -c 1 -W 1 "$IP_ADDRESS" >/dev/null 2>&1; then
        local FOLDER_LIST
        local HAS_DISPLAY
        local NODE_HOSTNAME
        local LABEL_STRING

        LABEL_STRING=$(echo "$JSON_OBJECT_ARG" | jq -r '[.labels[] | "--label-add \(.key)=\(.value)"] | join(" ")')
        FOLDER_LIST=$(echo "$JSON_OBJECT_ARG" | jq -r '.folders | join(" ")')
        HAS_DISPLAY=$(echo "$JSON_OBJECT_ARG" | jq -r '.["has-display"]')
        NODE_HOSTNAME=$(echo "$JSON_OBJECT_ARG" | jq -r '.hostname // empty')

        if [ -z "$NODE_HOSTNAME" ]; then
            NODE_HOSTNAME="${HOSTNAME_DEFAULT_PREFIX_ARG}${INDEX_ARG}"
        fi

        remove_ssh_host "${IP_ADDRESS}"

        if [ -z "${JOIN_MGR_CMD}" ]; then
            log_debug "\t- Creating the main Swarm manager node ${NODE_HOSTNAME} at IP address ${IP_ADDRESS}"
            install_docker "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}"

            JOIN_WORKER_CMD=$(sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" "sudo docker swarm init --advertise-addr ${IP_ADDRESS} | grep -Po 'docker swarm join --token .* \d+\.\d+\.\d+\.\d+:\d+'")
            MAIN_MANAGER_IP_ADDRESS="${IP_ADDRESS}"
            JOIN_MGR_CMD=$(sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" "sudo docker swarm join-token manager | grep -A 1 'docker swarm join' | tr -d '\\\\' | xargs")

            log_debug "\t- Saving the Swarm join command for workers to ${JOIN_WORKER_CMD_FILE}"
            echo "${JOIN_WORKER_CMD}" >"${JOIN_WORKER_CMD_FILE}"

            log_debug "\t- Saving the manager's IP address to ${MANAGER_IP_ADDRESS_FILE}"
            echo "${MAIN_MANAGER_IP_ADDRESS}" >"${MANAGER_IP_ADDRESS_FILE}"

            log_debug "\t- Saving the join manager command for managers to ${JOIN_MANAGER_CMD_FILE}"
            echo "${JOIN_MGR_CMD}" >"${JOIN_MANAGER_CMD_FILE}"
        else
            log_debug "\t- Swarm already created, using existing token to add a new manager node ${NODE_HOSTNAME} at IP address ${IP_ADDRESS}"
            install_docker "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}"

            log_debug "\t- Adding the manager ${NODE_HOSTNAME} to the Swarm"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" "sudo ${JOIN_MGR_CMD}"
        fi

        if [ "$HAS_DISPLAY" == "true" ]; then
            install_uctronics_pi_rack "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}" "./data"
        fi

        log_debug "\t- Creating the folders"
        sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" "sudo mkdir -p ${FOLDER_LIST}"

        set_hostname "${LOGIN_ARG}" "${PASSWORD_ARG}" "${NODE_HOSTNAME}" "${IP_ADDRESS}"
        reboot "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}" "${NODE_HOSTNAME}"

        log_debug "\t- Adding the labels to the manager"
        sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" "sudo docker node update ${LABEL_STRING} ${NODE_HOSTNAME}"

        log_warning "########################"
        log_warning "# Content of the Swarm #"
        log_warning "########################"
        sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" "sudo docker node ls"
    else
        log_error "$IP_ADDRESS is unreachable"
    fi
}

#
# create_managers
#
create_managers() {
    local LOGIN_ARG="$1"
    local PASSWORD_ARG="$2"
    local JSON_ARG="$3"
    local HOSTNAME_DEFAULT_PREFIX

    log_info "+++++++++++++++++++++++++++++++"
    log_info "|                             |"
    log_info "| CREATING THE SWARM MANAGERS |"
    log_info "|                             |"
    log_info "+++++++++++++++++++++++++++++++"

    HOSTNAME_DEFAULT_PREFIX=$(echo "$JSON_ARG" | jq -r '.swarm.managers["hostname-default-prefix"]')

    log_info "Creating the Swarm managers by using the default prefix: ${HOSTNAME_DEFAULT_PREFIX}"
    mapfile -t MANAGER_ARRAY < <(echo "$JSON_ARG" | jq -c '.swarm.managers.members[]')

    for index in "${!MANAGER_ARRAY[@]}"; do
        log_info "Creating the manager #$((index + 1))"
        create_single_manager "$LOGIN_ARG" "$PASSWORD_ARG" "$HOSTNAME_DEFAULT_PREFIX" "${MANAGER_ARRAY[$index]}" "${index}" || log_error "Manager #$((index + 1)) failed, continuing..."
    done
}

#
# create_single_worker
#
create_single_worker() {
    local LOGIN_ARG="$1"
    local PASSWORD_ARG="$2"
    local JSON_OBJECT_ARG="$3"
    local INDEX_ARG="$4"
    local IP_ADDRESS

    IP_ADDRESS=$(echo "$JSON_OBJECT_ARG" | jq -r '.["ip-address"]')

    if ping -c 1 -W 1 "$IP_ADDRESS" >/dev/null 2>&1; then
        local FOLDER_LIST
        local HAS_DISPLAY
        local NODE_HOSTNAME
        local LABEL_STRING

        LABEL_STRING=$(echo "$JSON_OBJECT_ARG" | jq -r '[.labels[] | "--label-add \(.key)=\(.value)"] | join(" ")')
        IP_ADDRESS=$(echo "$JSON_OBJECT_ARG" | jq -r '.["ip-address"]')
        NODE_HOSTNAME=$(echo "$JSON_OBJECT_ARG" | jq -r '.hostname')

        if [ -z "$IP_ADDRESS" ] || [ -z "$NODE_HOSTNAME" ]; then
            log_error "Worker at index $INDEX_ARG is missing required fields." >&2
            return 1
        fi

        remove_ssh_host "${IP_ADDRESS}"

        FOLDER_LIST=$(echo "$JSON_OBJECT_ARG" | jq -r '.folders | join(" ")')
        HAS_DISPLAY=$(echo "$JSON_OBJECT_ARG" | jq -r '.["has-display"]')

        if [ "$HAS_DISPLAY" == "true" ]; then
            install_uctronics_pi_rack "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}" "./data"
        fi

        install_docker "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}"

        log_debug "\t- Adding the worker ${NODE_HOSTNAME} to the Swarm"
        sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" "sudo ${JOIN_WORKER_CMD}"

        log_debug "\t- Creating the folders on worker ${NODE_HOSTNAME} at IP address ${IP_ADDRESS}"
        sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" "sudo mkdir -p ${FOLDER_LIST}"

        set_hostname "${LOGIN_ARG}" "${PASSWORD_ARG}" "${NODE_HOSTNAME}" "${IP_ADDRESS}"
        reboot "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}" "${NODE_HOSTNAME}"

        log_debug "\t- Adding the labels to the worker"
        sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" "sudo docker node update ${LABEL_STRING} ${NODE_HOSTNAME}"

        log_warning "########################"
        log_warning "# Content of the Swarm #"
        log_warning "########################"
        sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" "sudo docker node ls"
    else
        log_error "$IP_ADDRESS is unreachable"
    fi
}

#
# create_workers
#
create_workers() {
    local LOGIN_ARG="$1"
    local PASSWORD_ARG="$2"
    local JSON_ARG="$3"

    log_info "++++++++++++++++++++++++++"
    log_info "|                        |"
    log_info "| CREATING THE WORKERS   |"
    log_info "|                        |"
    log_info "++++++++++++++++++++++++++"

    log_info "Creating the Swarm workers"
    mapfile -t WORKER_ARRAY < <(echo "$JSON_ARG" | jq -c '.swarm.workers[]')

    for index in "${!WORKER_ARRAY[@]}"; do
        log_info "Creating the worker #${index}"
        create_single_worker "$LOGIN_ARG" "$PASSWORD_ARG" "${WORKER_ARRAY[$index]}" "${index}" || log_error "Worker #${index} failed, continuing..."
    done
}

#
# main
#
main() {
    MANDATORY_PARAMETER_LIST=("CONFIGURATION_FILE")
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
        --configuration-file | -f)
            CONFIGURATION_FILE="${2}"
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
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sshpass

    # Check if the file exists and is not empty
    if [ ! -s "$CONFIGURATION_FILE" ]; then
        log_error "Error: Configuration file '$CONFIGURATION_FILE' is missing or empty." >&2
        exit 1
    fi

    local JSON_CONTENT
    JSON_CONTENT=$(cat "$CONFIGURATION_FILE")

    DEVICE_DEFAULT_LOGIN=$(echo "$JSON_CONTENT" | jq -r '.swarm["device-default-credentials"].username')
    DEVICE_DEFAULT_PASSWORD=$(echo "$JSON_CONTENT" | jq -r '.swarm["device-default-credentials"].password')

    create_managers "$DEVICE_DEFAULT_LOGIN" "$DEVICE_DEFAULT_PASSWORD" "$JSON_CONTENT"
    create_workers "$DEVICE_DEFAULT_LOGIN" "$DEVICE_DEFAULT_PASSWORD" "$JSON_CONTENT"

    log_info "The swarm has been successfully created"
    log_warning "DO NOT FORGET TO CHANGE THE PASSWORD OF THE ROOT USER ON ALL NODES !!!"
}

time main "$@"
