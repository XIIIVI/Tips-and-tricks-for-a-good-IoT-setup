#!/bin/bash
set -e

cat /banner
echo "Version #-MODULE_VERSION-#"
echo

# Get the current hostname
HOSTNAME=$(cat /etc/hostname)

# Creates the folder hierarchy for logs and data
mkdir -p /alloy/logs/
mkdir -p /alloy/data/

printenv | sort

exec /bin/alloy "$@"
