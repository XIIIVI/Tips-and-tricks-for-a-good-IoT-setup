#!/bin/bash

# ============================================================
#  Project:   update-telegraf-level0.sh
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
    MANDATORY_PARAMETER_LIST=("LOCAL_REGISTRY_ADDRESS")

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
    local DIR_PART5=../../../part5/telegraf

    # Check all mandatory parameter are set
    check_all_mandatory_parameters "${MANDATORY_PARAMETER_LIST[@]}"

    display_settings

    log_info "Preparing the environment from ${DIR_PART5}"
    log_debug "\t- Copying files from ${DIR_PART5} to the current directory"
    cp "${DIR_PART5}"/build-telegraf-images.sh .
    cp "${DIR_PART5}"/*.flf .
    cp "${DIR_PART5}"/Dockerfile .
    cp "${DIR_PART5}"/entrypoint.sh .
    cp "${DIR_PART5}"/level0/telegraf.conf ./level0/telegraf.conf
    log_debug "\t- Removing the dummy output plugin"
    sed -i '/# Send metrics to nowhere at all/{N;N;d}' "${DIR_PART5}"/level0/telegraf.conf
    log_debug "\t- Adding the addon \"prometheus_remote_write\" to the telegraf configuration file"
    cat ./level0/telegraf.addon >>./level0/telegraf.conf
    chmod +x build-telegraf-images.sh

    ./build-telegraf-images.sh --local-registry-address "${LOCAL_REGISTRY_ADDRESS}" --local-registry-port "${LOCAL_REGISTRY_PORT}" --level-number 0
}

time main "$@"
