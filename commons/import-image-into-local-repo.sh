#!/bin/bash

# ============================================================
#  Project:   import-image-into-local-repo.sh
#  Author:    Fabrice TRAN-XUAN
#  Created:   2025-08-10
#
#  License:   MIT License
#
#  Permission is hereby granted, free of charge, to any person
#  obtaining a copy of this software and associated documentation
#  files (the "Software"), to deal in the Software without
#  restriction, including without limitation the rights to use,
#  copy, modify, merge, publish, distribute, sublicense, and/or
#  sell copies of the Software, and to permit persons to whom the
#  Software is furnished to do so, subject to the following
#  conditions:
#
#  The above copyright notice and this permission notice shall be
#  included in all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
#  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
#  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
#  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
#  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
#  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
#  OTHER DEALINGS IN THE SOFTWARE.
# ============================================================

source "./commons-cli.sh"
source "./commons-log.sh"

#
# display_help
#
display_help() {
    log_debug "Usage: ${0} --local-registry-address <IP address of the local registry>"
    log_debug "            [--local-registry-port <Port of the local registry> (By default: 4443)]"
    log_debug "            --image-name <Name of the image to import>"
    log_debug "            --image-version <Version of the image to import>"
    log_debug "            [--custom-image-version <Version of the built image>"]
    log_debug "            [--ssh-ip-address <IP address of the host to run on>]"
    log_debug "            [--ssh-login <User of the host to run on>]"
    log_debug "            [--ssh-password <Password of the host to run on>]"
}

#
# display_settings
#
display_settings() {
    log_debug "S E T T I N G S"
    log_debug "CUSTOM_IMAGE_VERSION  : ${CUSTOM_IMAGE_VERSION}"
    log_debug "IMAGE_NAME            : ${IMAGE_NAME}"
    log_debug "IMAGE_VERSION         : ${IMAGE_VERSION}"
    log_debug "LOCAL_REGISTRY_ADDRESS: ${LOCAL_REGISTRY_ADDRESS}"
    log_debug "LOCAL_REGISTRY_PORT   : ${LOCAL_REGISTRY_PORT}"
    log_debug "SSH_IP_ADDRESS        : ${SSH_IP_ADDRESS}"
    log_debug "SSH_LOGIN             : ${SSH_LOGIN}"
}

#
# main
#
main() {
    MANDATORY_PARAMETER_LIST=("IMAGE_NAME" "IMAGE_VERSION" "LOCAL_REGISTRY_ADDRESS")

    docker-compose down

    # Parses the parameters
    while (("$#")); do
        case "$1" in
        --custom-image-version)
            CUSTOM_IMAGE_VERSION="${2}"
            shift # past argument
            shift # past value
            ;;
        --image-name)
            IMAGE_NAME="${2}"
            shift # past argument
            shift # past value
            ;;
        --image-version)
            IMAGE_VERSION="${2}"
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
        --ssh-ip-address)
            SSH_IP_ADDRESS="${2}"
            shift # past argument
            shift # past value
            ;;
        --ssh-login)
            SSH_LOGIN="${2}"
            shift # past argument
            shift # past value
            ;;
        --ssh-password)
            SSH_PASSWORD="${2}"
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
    CUSTOM_IMAGE_VERSION=${CUSTOM_IMAGE_VERSION:="${IMAGE_VERSION}"}

    # Check all mandatory parameter are set
    check_all_mandatory_parameters "${MANDATORY_PARAMETER_LIST[@]}"

    display_settings

    if [ -z "${SSH_IP_ADDRESS}" ]; then
         docker buildx rm mybuilder
         log_info "Importing image ${IMAGE_NAME}:${IMAGE_VERSION} into local registry ${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}"
         log_debug "Creating the builder"
         docker buildx create --name mybuilder --use --bootstrap
         log_debug "Importing the image docker.io/${IMAGE_NAME}:${IMAGE_VERSION} as $(basename ${IMAGE_NAME}):${CUSTOM_IMAGE_VERSION}"
         docker buildx imagetools create --tag="${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}/$(basename ${IMAGE_NAME}):${CUSTOM_IMAGE_VERSION}" "docker.io/${IMAGE_NAME}:${IMAGE_VERSION}"
         log_debug "Removing the builder"
         docker buildx rm mybuilder
    else
         if [ -z "${SSH_PASSWORD}" ] || [ -z "${SSH_LOGIN}" ]; then
             log_error "❌ SSH_IP_ADDRESS and SSH_PASSWORD must be set to import the image into the local registry"
         else
             log_info "Importing with SSH image ${IMAGE_NAME}:${IMAGE_VERSION} into local registry ${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}"
             log_debug "Creating the builder"
             sshpass -p "${SSH_PASSWORD}" ssh "${SSH_LOGIN}@${SSH_IP_ADDRESS}" "sudo docker buildx create --name mybuilder --use --bootstrap"             
             log_debug "Importing the image docker.io/${IMAGE_NAME}:${IMAGE_VERSION} as $(basename ${IMAGE_NAME}):${CUSTOM_IMAGE_VERSION}"
             sshpass -p "${SSH_PASSWORD}" ssh "${SSH_LOGIN}@${SSH_IP_ADDRESS}" "sudo docker buildx imagetools create --tag=\"${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}/$(basename ${IMAGE_NAME}):${CUSTOM_IMAGE_VERSION}\" \"docker.io/${IMAGE_NAME}:${IMAGE_VERSION}\""
             log_debug "Removing the builder"
             sshpass -p "${SSH_PASSWORD}" ssh "${SSH_LOGIN}@${SSH_IP_ADDRESS}" "sudo docker buildx rm mybuilder"
         fi
    fi
}

time main "$@"
