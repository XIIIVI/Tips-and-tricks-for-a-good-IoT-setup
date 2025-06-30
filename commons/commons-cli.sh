#!/bin/bash

MISSING_PARAMETER_COUNT=0

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
