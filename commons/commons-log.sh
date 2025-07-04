#!/bin/bash

#
# log_progress
#   - param: message
#
log_progress() {
    printf "\r%s" "${1}"
}

#
# log_progress_bar
#
log_progress_bar() {
    local MESSAGE_ARG="${1}"
    local CURRENT_VALUE_ARG="${2}"
    local TOTAL_VALUE_ARG="${3}"
    local BAR_WIDTH=50

    # Cap values to avoid division by zero or negative cut ranges
    if [[ "$TOTAL_VALUE_ARG" -eq 0 ]]; then
        TOTAL_VALUE_ARG=1
    fi

    local PROGRESS=$((CURRENT_VALUE_ARG * BAR_WIDTH / TOTAL_VALUE_ARG))
    local PERCENT=$((CURRENT_VALUE_ARG * 100 / TOTAL_VALUE_ARG))

    local BAR=""
    if ((PROGRESS > 0)); then
        BAR=$(printf "%${PROGRESS}s" | tr ' ' '#')
    fi
    BAR=$(printf "%-${BAR_WIDTH}s" "$BAR")

    printf "\r[%s] %3d%% - %s" "$BAR" "$PERCENT" "${MESSAGE_ARG}"
}

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
