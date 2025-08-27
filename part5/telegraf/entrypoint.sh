#!/bin/bash
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
