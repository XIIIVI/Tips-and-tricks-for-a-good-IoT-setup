#!/bin/bash

# ============================================================
#  Project:   commons-cli.sh
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

MISSING_PARAMETER_COUNT=0

#
# check_mandatory_parameter
# Arguments:
#   - param: The name of the parameter to check
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
# Arguments:
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
