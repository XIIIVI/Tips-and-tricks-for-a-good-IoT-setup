#!/bin/bash

# ============================================================
#  Project:   build-telegraf-images.sh
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

source "../../commons/commons-cli.sh"
source "../../commons/commons-log.sh"

#
# display_help
#
display_help() {
    log_debug "Usage: ${0} --local-registry-address <IP address of the local registry>"
    log_debug "            [--local-registry-port <Port of the local registry> (By default: 4443)]"
    log_debug "            --level-number <Number>"
    log_debug "            [--custom-image-version <Version>]"
    log_debug "            --image-version <Version>"
}

#
# display_settings
#
display_settings() {
    log_debug "S E T T I N G S"
    log_debug "CUSTOM_IMAGE_VERSION  : ${CUSTOM_IMAGE_VERSION}"
    log_debug "IMAGE_VERSION         : ${IMAGE_VERSION}"
    log_debug "LEVEL_NUMBER          : ${LEVEL_NUMBER}"
    log_debug "LOCAL_REGISTRY_ADDRESS: ${LOCAL_REGISTRY_ADDRESS}"
    log_debug "LOCAL_REGISTRY_PORT   : ${LOCAL_REGISTRY_PORT}"
}

#
# main
#
main() {
    MANDATORY_PARAMETER_LIST=("IMAGE_VERSION" "LEVEL_NUMBER" "LOCAL_REGISTRY_ADDRESS")

    # Parses the parameters
    while (("$#")); do
        case "$1" in
        --custom-image-version)
            CUSTOM_IMAGE_VERSION="${2}"
            shift # past argument
            shift # past value
            ;;
        --image-version)
            IMAGE_VERSION="${2}"
            shift # past argument
            shift # past value
            ;;
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
    CUSTOM_IMAGE_VERSION=${CUSTOM_IMAGE_VERSION:="${IMAGE_VERSION}"}

    log_info "Installing the required packages"
    DEBIAN_FRONTEND=noninteractive apt-get -y -qq update
    DEBIAN_FRONTEND=noninteractive apt-get install -y dos2unix figlet jq
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y

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
    log_debug "Copying and customizing the file Dockerfile"
    sed -i "s/#-IP_ADDRESS-#:#-PORT-#/${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}/g" "./Dockerfile"
    sed -i "s/#-IMAGE_VERSION-#/${IMAGE_VERSION}/g" "./Dockerfile"
    cp "./Dockerfile" "level${LEVEL_NUMBER}/Dockerfile"

    # Build the Telegraf image
    cd "level${LEVEL_NUMBER}/" || exit
    log_debug "Importing the image from the folder ${PWD}"
    docker buildx build \
           --platform linux/arm64 \
           --tag "${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}/telegraf-level${LEVEL_NUMBER}:${IMAGE_VERSION}" \
           --build-arg IMAGE_VERSION="${CUSTOM_IMAGE_VERSION}" \
           --build-arg LOCAL_REGISTRY="${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}" \
           --push .
    
    cd - || exit

    log_info "Custom Telegraf image v${CUSTOM_IMAGE_VERSION} for level ${LEVEL_NUMBER} with original version ${IMAGE_VERSION} has been built and pushed successfully."
}

time main "$@"
