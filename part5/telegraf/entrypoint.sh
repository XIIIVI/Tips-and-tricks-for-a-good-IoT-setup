#!/bin/bash

# ============================================================
#  Project:   entrypoint.sh
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

set -e

cat /banner
echo "Version #-MODULE_VERSION-#"
echo

# Get the current hostname
HOSTNAME=$(cat /etc/hostname)

export HOSTNAME

# Create the log directory if it does not exist
mkdir -p /telegraf/logs

# Create the state file for the plugin
PLUGIN_STATE_FILE="/telegraf/plugin_state"

echo "Creating the plugin state file ${PLUGIN_STATE_FILE} if it does not exist..."

mkdir -p "$(dirname "${PLUGIN_STATE_FILE}")"

if [[ ! -s "${PLUGIN_STATE_FILE}" ]]; then
    # File does not exist, create it with content {}
    echo "{}" >"${PLUGIN_STATE_FILE}"
    echo "File '${PLUGIN_STATE_FILE}' created with content {}."
else
    echo "File '${PLUGIN_STATE_FILE}' already exists."
fi

printenv | sort

if [ "${1:0:1}" = '-' ]; then
    set -- telegraf "$@"
fi

exec "$@"
