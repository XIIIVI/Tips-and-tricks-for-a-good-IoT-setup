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

# Creates the folder hierarchy for logs and data
mkdir -p /alloy/logs/
mkdir -p /alloy/data/

printenv | sort

exec /bin/alloy "$@"
