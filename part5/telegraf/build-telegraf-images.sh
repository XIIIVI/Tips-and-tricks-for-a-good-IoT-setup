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
    log_debug "            --level-number <Number>"
}

#
# display_settings
#
display_settings() {
    log_debug "S E T T I N G S"
    log_debug "LEVEL_NUMBER : ${LEVEL_NUMBER}"
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
    MANDATORY_PARAMETER_LIST=("LEVEL_NUMBER" "LOCAL_REGISTRY_ADDRESS")

    # Parses the parameters
    while (("$#")); do
        case "$1" in
        --level-number)
            LEVEL_NUMBER="${2}"
            shift # past argument
            shift # past value
            ;;
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
    IMAGE_VERSION=${IMAGE_VERSION:="1.34.4-alpine"}

    log_info "Installing the required packages"
    apt-get -y -qq update
    apt-get install -y dos2unix figlet jq
    apt autoremove -y

    FIGLET_FONT="${PWD}/larry3d.flf"

    # Check all mandatory parameter are set
    check_all_mandatory_parameters "${MANDATORY_PARAMETER_LIST[@]}"

    display_settings

    log_info "Building the Telegraf image for level ${LEVEL_NUMBER} with version ${IMAGE_VERSION}"

    log_debug "Generating the banner"
    figlet -f "${FIGLET_FONT}" "Level #${LEVEL_NUMBER}" >"level${LEVEL_NUMBER}/banner"

    # entrypoint.sh
    log_debug "Customizing and copying the file entrypoint.sh"
    cp "./entrypoint.sh" "level${LEVEL_NUMBER}/entrypoint.sh"
    sed -i "s/#-MODULE_VERSION-#/${IMAGE_VERSION}/g" "level${LEVEL_NUMBER}/entrypoint.sh"

    # Dockerfile
    log_debug "Copying the file Dockerfile"
    cp "./Dockerfile" "level${LEVEL_NUMBER}/Dockerfile"

    # commons_telegraf.conf
    log_debug "Copying and customizing the file commons_telegraf.conf"
    mv "level${LEVEL_NUMBER}/telegraf.conf" "level${LEVEL_NUMBER}/telegraf.tmp"
    cp "./commons_telegraf.conf" "level${LEVEL_NUMBER}/telegraf.conf"
    cat "level${LEVEL_NUMBER}/telegraf.tmp" >> "level${LEVEL_NUMBER}/telegraf.conf"

    log_info "Importing image ${IMAGE_NAME}:${IMAGE_VERSION} into local registry ${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}"
    log_debug "Importing the image"

    # Build the Telegraf image
    cd "level${LEVEL_NUMBER}/" || exit
    docker buildx build \
           --platform linux/arm64v8 \
           --tag "${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}/telegraf-level${LEVEL_NUMBER}:${IMAGE_VERSION}" \
           --build-arg IMAGE_VERSION="${IMAGE_VERSION}" \
           --build-arg LOCAL_REGISTRY="${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}" \
           --push .
    
    cd - || exit

    log_info "Telegraf image for level ${LEVEL_NUMBER} with version ${IMAGE_VERSION} has been built and pushed successfully."
}

time main "$@"
