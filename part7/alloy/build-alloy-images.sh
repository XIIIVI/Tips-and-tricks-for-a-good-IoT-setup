#!/bin/bash

source "../../commons/commons-cli.sh"
source "../../commons/commons-log.sh"

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
    IMAGE_VERSION=${IMAGE_VERSION:="v1.10.2"}

    log_info "Installing the required packages"
    DEBIAN_FRONTEND=noninteractive apt-get -y -qq update
    DEBIAN_FRONTEND=noninteractive apt-get install -y dos2unix figlet jq
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y

    FIGLET_FONT="${PWD}/larry3d.flf"

    # Check all mandatory parameter are set
    check_all_mandatory_parameters "${MANDATORY_PARAMETER_LIST[@]}"

    display_settings

    log_info "Building the Alloy image ${IMAGE_VERSION}"

    log_debug "Generating the banner"
    figlet -f "${FIGLET_FONT}" "Alloy" >"level${LEVEL_NUMBER}/banner"

    # entrypoint.sh
    log_debug "Customizing the file entrypoint.sh"
    cp "./entrypoint.sh" "level${LEVEL_NUMBER}/entrypoint.sh"
    sed -i "s/#-MODULE_VERSION-#/${IMAGE_VERSION}/g" "level${LEVEL_NUMBER}/entrypoint.sh"

    # Dockerfile
    log_debug "Copying and customizing the file Dockerfile"
    sed -i "s/#-IP_ADDRESS-#:#-PORT-#/${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}/g" "./Dockerfile"
    sed -i "s/#-IMAGE_VERSION-#/${IMAGE_VERSION}/g" "./Dockerfile"
    cp "./Dockerfile" "level${LEVEL_NUMBER}/Dockerfile"

    # Build the Alloy image
    cd "level${LEVEL_NUMBER}/" || exit
    log_info "Importing image ${IMAGE_NAME}:${IMAGE_VERSION} into local registry ${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}"
    docker buildx build \
        --platform linux/arm64 \
        --tag "${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}/alloy-level${LEVEL_NUMBER}:${IMAGE_VERSION}" \
        --build-arg IMAGE_VERSION="${IMAGE_VERSION}" \
        --build-arg LOCAL_REGISTRY="${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}" \
        --push .

    cd - || exit

    log_info "Alloy image for level ${LEVEL_NUMBER} with version ${IMAGE_VERSION} has been built and pushed successfully."
}

time main "$@"
