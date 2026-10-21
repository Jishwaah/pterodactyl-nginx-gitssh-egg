#!/bin/bash
set -euo pipefail

cd /home/container

# Pull the newest installed PHP package builds from Sury on every container start.
/usr/local/bin/update-php-packages

# Make internal Docker IP address available to processes.
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Replace Startup Variables
MODIFIED_STARTUP=$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo -e ":/home/container$ ${MODIFIED_STARTUP}"

# Run the Server
eval "${MODIFIED_STARTUP}"
