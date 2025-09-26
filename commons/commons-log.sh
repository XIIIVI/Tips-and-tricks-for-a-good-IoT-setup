#!/bin/bash

# ============================================================
#  Project:   commons-log.sh
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

#
# log_progress_bar
# It overwrites the previous message on the same line.
# This function displays a progress bar in the terminal.
# Arguments:
#   1. MESSAGE_ARG: The main message to display.
#   2. CURRENT_VALUE_ARG: The current value of the progress.
#   3. TOTAL_VALUE_ARG: The total value of the progress.
#   4. SUBMESSAGE_ARG: An optional sub-message to display (at the end of the line).
#
log_progress_bar() {
    local MESSAGE_ARG="${1}"
    local CURRENT_VALUE_ARG="${2}"
    local TOTAL_VALUE_ARG="${3}"
    local SUBMESSAGE_ARG="${4}"
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

    BAR=$(printf "%-${BAR_WIDTH}s" "${BAR}")

    printf "\r[%s] %3d%% - %s %s" "${BAR}" "${PERCENT}" "${MESSAGE_ARG}" "${SUBMESSAGE_ARG}"
}

#
# log_error
# This function logs an error message in red color.
# Arguments:
#   - param: message
#
log_error() {
    echo -e "\e[91m${1}\e[97m"
}

#
# log_warning
# This function logs a warning message in yellow color.
# Arguments:
#   - param: message
#
log_warning() {
    echo -e "\e[33m${1}\e[97m"
}

#
# log_info
# This function logs an informational message in green color.
# Arguments:
#   - param: message
#
log_info() {
    echo -e "\e[92m${1}\e[97m"
}

#
# log_debug
# This function logs a debug message in magenta color.
# Arguments:
#  - param: message
#
log_debug() {
    echo -e "\e[95m${1}\e[97m"
}
