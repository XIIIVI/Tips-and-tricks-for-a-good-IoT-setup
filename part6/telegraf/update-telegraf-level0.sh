#!/bin/bash

MISSING_PARAMETER_COUNT=0

#
# log_error
#   - param: message
#
log_error() {
    echo -e "\e[91m${1}\e[97m"
}

#
# log_warning
#   - param: message
#
log_warning() {
    echo -e "\e[33m${1}\e[97m"
}

#
# log_info
#   - param: message
#
log_info() {
    echo -e "\e[92m${1}\e[97m"
}

#
# log_debug
#  - param: message
#
log_debug() {
    echo -e "\e[95m${1}\e[97m"
}

#
# display_help
#
display_help() {
    log_debug "Usage: ${0} --local-registry-address <IP address of the local registry>"
    log_debug "            [--local-registry-port <Port of the local registry> (By default: 4443)]"
}

#
# display_settings
#
display_settings() {
    log_debug "S E T T I N G S"
    log_debug "LOCAL_REGISTRY_ADDRESS: ${LOCAL_REGISTRY_ADDRESS}"
    log_debug "LOCAL_REGISTRY_PORT   : ${LOCAL_REGISTRY_PORT}"
}

#
# check_mandatory_parameter
# - param1: the variable to check
#
check_mandatory_parameter() {
    local VARIABLE_NAME="${1}"

    if [[ -z "${!VARIABLE_NAME}" ]]; then
        MISSING_PARAMETER_COUNT=$((MISSING_PARAMETER_COUNT + 1))
        log_error "[MISSING] ${1}"
    fi
}

#
# check_all_mandatory_parameters
#   - param*: All the parameters to check
#
check_all_mandatory_parameters() {
    log_info "Checking all the mandatory parameters"
    local MANDATORY_PARAMETER_LIST_ARG=("$@")

    for index in "${MANDATORY_PARAMETER_LIST_ARG[@]}"; do
        check_mandatory_parameter "${index}"
    done

    if [ ${MISSING_PARAMETER_COUNT} -gt 0 ]; then
        display_help
        exit 1
    else
        log_info "All the required parameters have been defined"
    fi
}

#
# main
#
main() {
    MANDATORY_PARAMETER_LIST=( "LOCAL_REGISTRY_ADDRESS")

    # Parses the parameters
    while (("$#")); do
        case "$1" in
        --local-registry-address)
            LOCAL_REGISTRY_ADDRESS="${2}"
            shift # past argument
            shift # past value
            ;;
        --local-registry-port)
            LOCAL_REGISTRY_PORT="${2}"
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

    LOCAL_REGISTRY_PORT=${LOCAL_REGISTRY_PORT:="4443"}
    local DIR_PART5=../../part5

    # Check all mandatory parameter are set
    check_all_mandatory_parameters "${MANDATORY_PARAMETER_LIST[@]}"

    display_settings

    log_info "Preparing the environment"
    cp "${DIR_PART5}"/build-telegraf-images.sh .
    cp "${DIR_PART5}"/Dockerfile.sh .
    cp "${DIR_PART5}"/entrypoint.sh .
    cat "${DIR_PART5}"/level0/telegraf.conf ./level0/telegraf.addon > ./level0/telegraf.conf
    chmod +x build-telegraf-images.sh

    ./build-telegraf-images.sh --local-registry-address "${LOCAL_REGISTRY_ADDRESS}" --local-registry-port "${LOCAL_REGISTRY_PORT}" --level-number 0
}

time main "$@"
