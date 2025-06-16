#!/bin/bash
set -e

cat /banner
echo "Version #-MODULE_VERSION-#"
echo

# Get the current hostname
HOSTNAME=$(cat /etc/hostname)

# Remove "-123"-style numeric suffix from the hostname
PARENT_HOSTNAME="${HOSTNAME%-[0-9]*}"

# If result is same as original, we are at the top level
if [[ "$PARENT_HOSTNAME" == "$HOSTNAME" ]]; then
  PARENT_HOSTNAME="orchestrator"
fi

export PARENT_HOSTNAME

# Create the state file for the plugin
PLUGIN_STATE_FILE="/data/telegraf/plugin_state"

echo "Creating the plugin state file"

if [[ ! -s "${PLUGIN_STATE_FILE}" ]]; then
    # File does not exist, create it with content {}
    echo "{}" >"${PLUGIN_STATE_FILE}"
    echo "File '${PLUGIN_STATE_FILE}' created with content {}."
else
    echo "File '{$PLUGIN_STATE_FILE}' already exists."
fi

printenv | sort

if [ "${1:0:1}" = '-' ]; then
    set -- telegraf "$@"
fi

exec "$@"
