#!/bin/bash

# ============================================================
#  Project:   create-swarm.sh
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

source "../../commons/commons-cli.sh"
source "../../commons/commons-docker.sh"
source "../../commons/commons-file.sh"
source "../../commons/commons-i2c.sh"
source "../../commons/commons-log.sh"
source "../../commons/commons-net.sh"
source "../../commons/commons-ssh.sh"
source "../../commons/commons-time.sh"
source "../../commons/commons-uart.sh"

declare -A HOST_IP_MAP

#
# display_help
# Displays the help message for the script.
#
display_help() {
    log_debug "Usage: ${0} --configuration-file | -f <Configuration file>"
    log_debug "            --login <login>"
    log_debug "            --password <password>"
    log_debug "            [--default-hostname <Hostname> (by default, set to \"undefined\")]"
}

#
# display_settings
# Displays the current settings of the script.
#
display_settings() {
    log_debug "S E T T I N G S"
    log_debug "CONFIGURATION_FILE: ${CONFIGURATION_FILE}"
    log_debug "DEFAULT_HOSTNAME  : ${DEFAULT_HOSTNAME}"
    log_debug "LOGIN             : ${LOGIN}"
}

#
# create_single_manager
# This function creates and adds a single manager to the Swarm cluster.
# Arguments:
#   1. LOGIN_ARG: The login to the host.
#   2. PASSWORD_ARG: The password to the host.
#   3. JSON_CONTENT_ARG: The JSON content containing the manager's configuration.
#   4. HOSTNAME_DEFAULT_PREFIX_ARG: The default prefix for the hostname.
#   5. JSON_OBJECT_ARG: The JSON object containing the manager's configuration.
#   6. INDEX_ARG: The index of the manager in the list.
#   7. REGISTRY_IP_ADDRESS_ARG: The IP address of the Docker registry.
#   8. REGISTRY_PORT_ARG: The port of the Docker registry.
#   9. REGISTRY_CERTIFICATE_FILE_ARG: The path to the Docker registry certificate file.
#
create_single_manager() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local JSON_CONTENT_ARG="${3}"
    local HOSTNAME_DEFAULT_PREFIX_ARG="${4}"
    local JSON_OBJECT_ARG="${5}"
    local INDEX_ARG="${6}"
    local REGISTRY_IP_ADDRESS_ARG="${7}"
    local REGISTRY_PORT_ARG="${8}"
    local REGISTRY_CERTIFICATE_FILE_ARG="${9}"
    local IP_ADDRESS

    IP_ADDRESS=$(echo "$JSON_OBJECT_ARG" | jq -r '.["ip-address"]')

    if ping -c 1 -W 1 "$IP_ADDRESS" >/dev/null 2>&1; then
        local FOLDER_LIST
        local HAS_DISPLAY
        local NODE_HOSTNAME
        local LABEL_STRING

        LABEL_STRING=$(echo "$JSON_OBJECT_ARG" | jq -r '[.labels[] | "--label-add \(.key)=\(.value)"] | join(" ")')
        FOLDER_LIST=$(echo "$JSON_OBJECT_ARG" | jq -r '.folders | join(" ")')
        HAS_DISPLAY=$(echo "$JSON_OBJECT_ARG" | jq -r '.["has-display"]')
        NODE_HOSTNAME=$(echo "$JSON_OBJECT_ARG" | jq -r '.hostname // empty')

        if [ -z "$NODE_HOSTNAME" ]; then
            NODE_HOSTNAME="${HOSTNAME_DEFAULT_PREFIX_ARG}${INDEX_ARG}"
        fi

        check_hostname_conflict "${NODE_HOSTNAME}"
        STATUS=$?

        if [[ $STATUS -ge 3 ]]; then
            log_error "\t 🚫 Abort: Hostname ${NODE_HOSTNAME} is already used by another host."
        else
            remove_ssh_host "${IP_ADDRESS}"
            HOST_IP_MAP["${NODE_HOSTNAME}"]="${IP_ADDRESS}"

            if [ -z "${JOIN_MGR_CMD}" ]; then
                log_debug "\t- Creating the main Swarm manager node ${NODE_HOSTNAME} at IP address ${IP_ADDRESS}"
                install_docker "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}" "${REGISTRY_IP_ADDRESS_ARG}" "${REGISTRY_PORT_ARG}" "${REGISTRY_CERTIFICATE_FILE_ARG}"

                JOIN_WORKER_CMD=$(sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" "sudo docker swarm init --advertise-addr ${IP_ADDRESS} | grep -Po 'docker swarm join --token .* \d+\.\d+\.\d+\.\d+:\d+'")
                MAIN_MANAGER_IP_ADDRESS="${IP_ADDRESS}"
                JOIN_MGR_CMD=$(sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" "sudo docker swarm join-token manager | grep -A 1 'docker swarm join' | tr -d '\\\\' | xargs")

                log_debug "\t- Saving the Swarm join command for workers to ${JOIN_WORKER_CMD_FILE}"
                echo "${JOIN_WORKER_CMD}" >"${JOIN_WORKER_CMD_FILE}"

                log_debug "\t- Saving the manager's IP address to ${MANAGER_IP_ADDRESS_FILE}"
                echo "${MAIN_MANAGER_IP_ADDRESS}" >"${MANAGER_IP_ADDRESS_FILE}"

                log_debug "\t- Saving the join manager command for managers to ${JOIN_MANAGER_CMD_FILE}"
                echo "${JOIN_MGR_CMD}" >"${JOIN_MANAGER_CMD_FILE}"

               create_credentials "${LOGIN}" "${PASSWORD}" "${IP_ADDRESS}" "${JSON_CONTENT_ARG}"
               create_certificates "${LOGIN}" "${PASSWORD}" "${IP_ADDRESS}" "${JSON_CONTENT_ARG}"
               create_configurations "${LOGIN}" "${PASSWORD}" "${IP_ADDRESS}" "${JSON_CONTENT_ARG}"
               create_overlay_networks "${LOGIN}" "${PASSWORD}" "${IP_ADDRESS}" "${JSON_CONTENT_ARG}"
            else
                local ATTEMPT_COUNT
                local MAX_ATTEMPTS
                local SUCCESS

                ATTEMPT_COUNT=0
                MAX_ATTEMPTS=5
                SUCCESS=0

                log_debug "\t- Swarm already created, using the existing token to add a new manager node ${NODE_HOSTNAME} at IP address ${IP_ADDRESS}"
                install_docker "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}" "${REGISTRY_IP_ADDRESS_ARG}" "${REGISTRY_PORT_ARG}" "${REGISTRY_CERTIFICATE_FILE_ARG}"
                
                while [ "$ATTEMPT_COUNT" -lt "$MAX_ATTEMPTS" ]; do
                     ATTEMPT_COUNT=$((ATTEMPT_COUNT + 1))
                     log_debug "\t- Adding the manager ${NODE_HOSTNAME} to the Swarm (attempt #$ATTEMPT_COUNT / $MAX_ATTEMPTS)"

                     sshpass -p "${PASSWORD_ARG}" ssh -tt -o StrictHostKeyChecking=no "${LOGIN_ARG}@${IP_ADDRESS}" "sudo ${JOIN_MGR_CMD}"
                    
                     if [ $? -eq 0 ]; then
                         echo "✅ Manager join successful on attempt #$ATTEMPT_COUNT."
                         SUCCESS=1
                         break
                     else
                         echo "❌ Attempt #$ATTEMPT_COUNT failed. Retrying in 5 seconds..."
                         sleep 5
                     fi
                 done

                 # ✔️ Continue with script if successful
                 if [ "$SUCCESS" -eq 0 ]; then
                     log_error "🚨 All $MAX_ATTEMPTS attempts failed. Exiting script."
                     exit 1
                 fi
            fi

            if [ "$HAS_DISPLAY" == "true" ]; then
                install_uctronics_pi_rack "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}" "./data"
            fi

            activate_uart "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}"
            install_vcgencmd "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}"
            install_chrony_ntp "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}"

            log_debug "\t- Creating the folders"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" "sudo mkdir -p ${FOLDER_LIST}"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" "sudo chmod -R 777 ${FOLDER_LIST}"

            set_hostname "${LOGIN_ARG}" "${PASSWORD_ARG}" "${NODE_HOSTNAME}" "${IP_ADDRESS}"
            reboot "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}" "${NODE_HOSTNAME}"

            # Labels
            log_debug "\t- Adding the labels to the manager"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" "sudo docker node update ${LABEL_STRING} ${NODE_HOSTNAME}"
            log_debug "\t- Generating the configuration with env variables from the label definition => ${CONFIG_DIR}/${NODE_HOSTNAME}_env.config"

            touch "${CONFIG_DIR}/${NODE_HOSTNAME}_env.config"

            for LABEL in $(echo "$JSON_OBJECT_ARG" | jq -c '.labels[]'); do
                 local KEY
                 local VALUE

                 KEY=$(echo "$LABEL" | jq -r '.key' | tr '[:lower:]' '[:upper:]')
                 VALUE=$(echo "$LABEL" | jq -r '.value')

                 echo "${KEY}=${VALUE}" >> "${CONFIG_DIR}/${NODE_HOSTNAME}_env.config"
            done

            create_single_configuration "${LOGIN_ARG}" "${PASSWORD_ARG}" "${MAIN_MANAGER_IP_ADDRESS}" "${NODE_HOSTNAME}_env.config" "${CONFIG_DIR}/${NODE_HOSTNAME}_env.config"

            log_warning "########################"
            log_warning "# Content of the Swarm #"
            log_warning "########################"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" "sudo docker node ls"
        fi
    else
        log_error "❌ $IP_ADDRESS is unreachable"
    fi
}

#
# create_managers
# This function creates the Swarm managers based on the provided JSON configuration.
# Arguments:
#   1. LOGIN_ARG: The login to the host.
#   2. PASSWORD_ARG: The password to the host.
#   3. JSON_ARG: The JSON object containing the managers' configuration.
#   4. REGISTRY_IP_ADDRESS_ARG: The IP address of the Docker registry.
#   5. REGISTRY_PORT_ARG: The port of the Docker registry.
#   6. REGISTRY_CERTIFICATE_FILE_ARG: The path to the Docker registry certificate file.
#
create_managers() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local JSON_ARG="${3}"
    local REGISTRY_IP_ADDRESS_ARG="${4}"
    local REGISTRY_PORT_ARG="${5}"
    local REGISTRY_CERTIFICATE_FILE_ARG="${6}"
    local HOSTNAME_DEFAULT_PREFIX

    log_info "+++++++++++++++++++++++++++++++"
    log_info "|                             |"
    log_info "| CREATING THE SWARM MANAGERS |"
    log_info "|                             |"
    log_info "+++++++++++++++++++++++++++++++"

    HOSTNAME_DEFAULT_PREFIX=$(echo "${JSON_ARG}" | jq -r '.swarm.managers["hostname-default-prefix"]')

    log_info "Creating the Swarm managers using the default prefix: ${HOSTNAME_DEFAULT_PREFIX}"
    mapfile -t MANAGER_ARRAY < <(echo "${JSON_ARG}" | jq -c '.swarm.managers.members[]')

    for index in "${!MANAGER_ARRAY[@]}"; do
        log_info "Creating the manager #$((index + 1))"
        create_single_manager "${LOGIN_ARG}" "${PASSWORD_ARG}" "${JSON_ARG}" "$HOSTNAME_DEFAULT_PREFIX" "${MANAGER_ARRAY[$index]}" "$((index + 1))" "${REGISTRY_IP_ADDRESS_ARG}" "${REGISTRY_PORT_ARG}" "${REGISTRY_CERTIFICATE_FILE_ARG}" || log_error "❌ Manager #$((index + 1)) failed, continuing..."
    done

    log_info "Swarm configurations"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" "sudo docker config ls"
    log_info "Swarm secrets"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" "sudo docker secret ls"
}

#
# create_single_worker
# This function creates and adds a single worker to the Swarm cluster.
# Arguments:
#   1. LOGIN_ARG: The login to the host.
#   2. PASSWORD_ARG: The password to the host.
#   3. JSON_OBJECT_ARG: The JSON object containing the worker's configuration.
#   4. INDEX_ARG: The index of the worker in the list.
#   5. REGISTRY_IP_ADDRESS_ARG: The IP address of the Docker registry.
#   6. REGISTRY_PORT_ARG: The port of the Docker registry.
#   7. REGISTRY_CERTIFICATE_FILE_ARG: The path to the Docker registry certificate file.
#
create_single_worker() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local JSON_OBJECT_ARG="${3}"
    local INDEX_ARG="${4}"
    local REGISTRY_IP_ADDRESS_ARG="${5}"
    local REGISTRY_PORT_ARG="${6}"
    local REGISTRY_CERTIFICATE_FILE_ARG="${7}"
    local IP_ADDRESS

    IP_ADDRESS=$(echo "$JSON_OBJECT_ARG" | jq -r '.["ip-address"]')

    if ping -c 1 -W 1 "$IP_ADDRESS" >/dev/null 2>&1; then
        local FOLDER_LIST
        local HAS_DISPLAY
        local NODE_HOSTNAME
        local LABEL_STRING

        LABEL_STRING=$(echo "$JSON_OBJECT_ARG" | jq -r '[.labels[] | "--label-add \(.key)=\(.value)"] | join(" ")')
        IP_ADDRESS=$(echo "$JSON_OBJECT_ARG" | jq -r '.["ip-address"]')
        NODE_HOSTNAME=$(echo "$JSON_OBJECT_ARG" | jq -r '.hostname')

        if [ -z "$IP_ADDRESS" ] || [ -z "$NODE_HOSTNAME" ]; then
            log_error "❌ Worker at index $INDEX_ARG is missing required fields." >&2
            return 1
        fi

        check_hostname_conflict "${NODE_HOSTNAME}"
        STATUS=$?

        if [[ $STATUS -ge 3 ]]; then
            log_error "\t 🚫 Abort: Hostname ${NODE_HOSTNAME} is already used by another host."
        else
            remove_ssh_host "${IP_ADDRESS}"
            HOST_IP_MAP["${NODE_HOSTNAME}"]="${IP_ADDRESS}"

            FOLDER_LIST=$(echo "$JSON_OBJECT_ARG" | jq -r '.folders | join(" ")')
            HAS_DISPLAY=$(echo "$JSON_OBJECT_ARG" | jq -r '.["has-display"]')

            if [ "$HAS_DISPLAY" == "true" ]; then
                install_uctronics_pi_rack "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}" "./data"
            fi

            activate_uart "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}"
            install_vcgencmd "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}"
            install_chrony_ntp "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}"
            install_docker "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}" "${REGISTRY_IP_ADDRESS_ARG}" "${REGISTRY_PORT_ARG}" "${REGISTRY_CERTIFICATE_FILE_ARG}"

            log_debug "\t- Adding the worker ${NODE_HOSTNAME} to the Swarm"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" "sudo ${JOIN_WORKER_CMD}"

            log_debug "\t- Creating the folders on worker ${NODE_HOSTNAME} at IP address ${IP_ADDRESS}"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" "sudo mkdir -p ${FOLDER_LIST}"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" "sudo chmod -R 777 ${FOLDER_LIST}"

            set_hostname "${LOGIN_ARG}" "${PASSWORD_ARG}" "${NODE_HOSTNAME}" "${IP_ADDRESS}"
            reboot "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS}" "${NODE_HOSTNAME}"

            log_debug "\t- Adding the labels to the worker"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" "sudo docker node update ${LABEL_STRING} ${NODE_HOSTNAME}"

            # Configuration files            
            log_debug "\t- Creating the configuration files"
            log_warning "\t\t- Generating from the Swarm definition"
while IFS= read -r entry; do
    hostname=$(jq -r '.hostname' <<<"$entry")

    # Write config key=value pairs
    jq -r '.config[] | "\(.key)=\(.value)"' <<<"$entry" \
        > "${CONFIG_DIR}/${hostname}.config"

    create_single_configuration \
        "${LOGIN_ARG}" \
        "${PASSWORD_ARG}" \
        "${MAIN_MANAGER_IP_ADDRESS}" \
        "${hostname}.config" \
        "${CONFIG_DIR}/${hostname}.config"

    log_warning "\t\t- Generating from the label definition => ${hostname}_env.config"

    : > "${CONFIG_DIR}/${hostname}_env.config"  # truncate/create

    # Loop over labels safely
    while IFS= read -r label; do
        local KEY VALUE
        KEY=$(jq -r '.key' <<<"$label" | tr '[:lower:]' '[:upper:]')
        VALUE=$(jq -r '.value' <<<"$label")
        echo "${KEY}=${VALUE}" >> "${CONFIG_DIR}/${hostname}_env.config"
    done < <(jq -c '.labels[]' <<<"$JSON_OBJECT_ARG")

    create_single_configuration \
        "${LOGIN_ARG}" \
        "${PASSWORD_ARG}" \
        "${MAIN_MANAGER_IP_ADDRESS}" \
        "${hostname}_env.config" \
        "${CONFIG_DIR}/${hostname}_env.config" < /dev/null

done 0< <(jq -c 'select(.config != null) | {hostname, config}' <<<"$JSON_OBJECT_ARG")

            # Summary
            log_warning "########################"
            log_warning "# Content of the Swarm #"
            log_warning "########################"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" "sudo docker node ls"
        fi
    else
        log_error "❌ $IP_ADDRESS is unreachable"
    fi
}

#
# create_workers
# This function creates the Swarm workers based on the provided JSON configuration.
# Arguments:
#   1. LOGIN_ARG: The login to the host.
#   2. PASSWORD_ARG: The password to the host.
#   3. JSON_ARG: The JSON object containing the workers' configuration.
#   4. REGISTRY_IP_ADDRESS_ARG: The IP address of the Docker registry.
#   5. REGISTRY_PORT_ARG: The port of the Docker registry.
#   6. REGISTRY_CERTIFICATE_FILE_ARG: The path to the Docker registry certificate file.
#
create_workers() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local JSON_ARG="${3}"
    local REGISTRY_IP_ADDRESS_ARG="${4}"
    local REGISTRY_PORT_ARG="${5}"
    local REGISTRY_CERTIFICATE_FILE_ARG="${6}"

    log_info "++++++++++++++++++++++++++"
    log_info "|                        |"
    log_info "| CREATING THE WORKERS   |"
    log_info "|                        |"
    log_info "++++++++++++++++++++++++++"

    log_info "Creating the Swarm workers"
    mapfile -t WORKER_ARRAY < <(echo "${JSON_ARG}" | jq -c '.swarm.workers[]')

    for index in "${!WORKER_ARRAY[@]}"; do
        log_info "Creating the worker #$((index + 1))"
        create_single_worker "${LOGIN_ARG}" "${PASSWORD_ARG}" "${WORKER_ARRAY[$index]}" "$((index + 1))" "${REGISTRY_IP_ADDRESS_ARG}" "${REGISTRY_PORT_ARG}" "${REGISTRY_CERTIFICATE_FILE_ARG}" || log_error "❌ Worker #$((index + 1)) failed, continuing..."
    done
}

#
# create_credentials
# This function creates and adds credentials as Docker secrets to the Swarm cluster.
# Arguments:
#   1. LOGIN_ARG: The login to the host.
#   2. PASSWORD_ARG: The password to the host.
#   3. IP_ADDRESS_ARG: The IP address of the host.
#   4. JSON_ARG: The JSON object containing the credentials configuration.
#
create_credentials() {
    local LOGIN_ARG="$1"
    local PASSWORD_ARG="$2"
    local IP_ADDRESS_ARG="$3"
    local JSON_ARG="$4"

    log_debug "\t- Creating the secrets for credentials on ${IP_ADDRESS_ARG}"

    # Iterate over each credential object safely
while IFS= read -r cred_json; do
    # Extract fields safely
    local name login GENERATED_PASSWORD HASH PASSWORD_FILENAME
    name=$(jq -r '.name' <<<"$cred_json")
    login=$(jq -r '.login' <<<"$cred_json")

    log_warning "\t\t- Creating the secret ${name} for user ${login}"

    PASSWORD_FILENAME="${name}.credentials"
    GENERATED_PASSWORD=$(openssl rand -base64 16)
    HASH=$(htpasswd -bnB "${login}" "${GENERATED_PASSWORD}" | cut -d ':' -f2)

    # Create local password file
    echo "${login}:${HASH}" > "./${PASSWORD_FILENAME}"

    log_warning "\t\t- Importing the secret ${name} for user ${login} on ${IP_ADDRESS_ARG}"

    # Copy to host
    copy_file_to_host "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS_ARG}" "./${PASSWORD_FILENAME}" "/tmp/" < /dev/null

    # Remove local password file
    rm -f "./${PASSWORD_FILENAME}"

    # Create Docker secrets on remote host
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" \
        "sudo docker secret create ${name}.passwd /tmp/${PASSWORD_FILENAME}" < /dev/null
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" \
        "echo -n \"${name}\" | sudo docker secret create ${name}.user -" < /dev/null

    # Remove temp files on remote host
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" \
        "rm -f /tmp/${PASSWORD_FILENAME}*" < /dev/null

    # Append to secret template
    cat <<EOF >>"${SECRET_TEMPLATE}"
    ${name}.passwd:
      external: true
    ${name}.user:
      external: true
EOF

done 0< <(jq -c '.swarm.secrets.credentials[]' <<<"$JSON_ARG")

    log_warning "########################"
    log_warning "# Secrets of the Swarm #"
    log_warning "########################"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" \
        "sudo docker secret ls"
}

#
# create_certificates
# This function creates and adds certificates as Docker secrets to the Swarm cluster.
# Arguments:
#   1. LOGIN_ARG: The login to the host.
#   2. PASSWORD_ARG: The password to the host.
#   3. IP_ADDRESS_ARG: The IP address of the host.
#   4. JSON_ARG: The JSON object containing the certificates configuration.
#
create_certificates() {
    local LOGIN_ARG="$1"
    local PASSWORD_ARG="$2"
    local IP_ADDRESS_ARG="$3"
    local JSON_ARG="$4"
    # Extract CA parameters
    local CA_NAME
    CA_NAME=$(jq -r '.swarm.secrets.certificates.name' "${JSON_ARG}")
    local DAYS_VALID
    DAYS_VALID=$(jq -r '.swarm.secrets.certificates["days-valid"]' "${JSON_ARG}")
    local COUNTRY
    COUNTRY=$(jq -r '.swarm.secrets.certificates.country' "${JSON_ARG}")
    local STATE
    STATE=$(jq -r '.swarm.secrets.certificates.state' "${JSON_ARG}")
    local LOCALITY
    LOCALITY=$(jq -r '.swarm.secrets.certificates.locality' "${JSON_ARG}")

    log_debug "\t- Creating the secrets for certificates on ${IP_ADDRESS_ARG}"

    # Step 1: Generate root CA key and cert
    log_warning "\t\t-🌳 Creating the root CA ${CA_NAME}"
    openssl genrsa -out "${CA_NAME}.key" 4096
    openssl req -x509 -new -nodes \
      -key "${CA_NAME}.key" \
      -sha256 \
      -days "${DAYS_VALID}" \
      -subj "/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/CN=${CA_NAME}" \
      -out "${CA_NAME}.crt"

    # Import root CA as a Swarm secret
    log_warning "\t\t- Importing the root CA ${CA_NAME} on ${IP_ADDRESS_ARG}"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" \
      "docker secret rm ${CA_NAME}_ca 2>/dev/null || true && \
       docker secret create ${CA_NAME}_ca - < ${CA_NAME}.crt"

     # Append to secret template
     cat <<EOF >>"${SECRET_TEMPLATE}"
    ${CA_NAME}.ca:
      external: true
EOF

    # Prepare a base server.ext for global extensions
    cat > server.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
EOF

    # Step 2: Loop through each 'key-and-csr' entry
    jq -r '.swarm.secrets.certificates["key-and-csr"][]' "${JSON_ARG}" | while read -r NAME; do
      local EXT_FILE="${NAME}.ext"

     log_debug "\t-🎫 Processing certificate for ${NAME}"
      # Build per-service extension file
      cp server.ext "${EXT_FILE}"
      printf "extendedKeyUsage = clientAuth,serverAuth\nsubjectAltName = DNS:%s\n" "${NAME}" \
        >> "${EXT_FILE}"

      # Generate private key and CSR
      log_warning "\t\t- Creating the certificate for ${NAME}"
      openssl genrsa -out "${NAME}.key" 2048
      openssl req -new \
        -key "${NAME}.key" \
        -subj "/CN=${NAME}" \
        -out "${NAME}.csr" \
        -config <(printf "[req]\ndistinguished_name=req_distinguished_name\nreq_extensions=v3_req\n[req_distinguished_name]\n[ v3_req ]\n%s\n" "$(cat "${EXT_FILE}")")

      # Sign CSR to produce certificate
      log_warning "\t\t- Signing the certificate for ${NAME} with CA ${CA_NAME}"
      openssl x509 -req \
        -in "${NAME}.csr" \
        -CA "${CA_NAME}.crt" \
        -CAkey "${CA_NAME}.key" \
        -CAcreateserial \
        -out "${NAME}.crt" \
        -days "${DAYS_VALID}" \
        -sha256 \
        -extfile "${EXT_FILE}"

      # Verify the certificate chains to the CA
      log_warning "\t\t- Verifying the certificate for ${NAME} with CA ${CA_NAME}"
      openssl verify -CAfile "${CA_NAME}.crt" "${NAME}.crt"

      # Import key and cert into Swarm as secrets
      log_warning "\t\t- Importing the certificate and key for ${NAME} on ${IP_ADDRESS_ARG}"
      sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" \
        "docker secret rm ${NAME}_key 2>/dev/null || true && \
         docker secret create ${NAME}_key - < ${NAME}.key"
      sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" \
        "docker secret rm ${NAME}_cert 2>/dev/null || true && \
         docker secret create ${NAME}_cert - < ${NAME}.crt"

     # Append to secret template
     cat <<EOF >>"${SECRET_TEMPLATE}"
    ${NAME}.crt:
      external: true
    ${NAME}.key:
      external: true
EOF

     # Local cleanup
     rm -f "${NAME}.ca" "${NAME}.crt" "${NAME}.key" "${NAME}.csr" ca.key ca.srl
    done

    log_warning "########################"
    log_warning "# Secrets of the Swarm #"
    log_warning "########################"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" \
        "sudo docker secret ls"
}

#
# create_single_configuration
# This function creates a single configuration as a Docker config in the Swarm cluster.
# Arguments:
#   1. LOGIN_ARG: The login to the host.
#   2. PASSWORD_ARG: The password to the host.
#   3. IP_ADDRESS_ARG: The IP address of the host.
#   4. NAME_ARG: The name of the configuration.
#   5. FILE_ARG: The path to the configuration file.
#
create_single_configuration() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local IP_ADDRESS_ARG="${3}"
    local NAME_ARG="${4}"
    local FILE_ARG="${5}"

    log_warning "\t\t- Creating the configuration ${NAME_ARG} on ${IP_ADDRESS_ARG}"
    copy_file_to_host "${LOGIN_ARG}" "${PASSWORD_ARG}" "${IP_ADDRESS_ARG}" "${FILE_ARG}" "/tmp/"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "sudo docker config create ${NAME_ARG} /tmp/${NAME_ARG}"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "rm -f /tmp/${NAME_ARG}"
    cat <<EOF >>"${CONFIG_TEMPLATE}"
  ${NAME_ARG}:
    external: true
EOF
}

#
# create_configurations
# This function creates configurations as Docker configs in the Swarm cluster.
# Arguments:
#   1. LOGIN_ARG: The login to the host.
#   2. PASSWORD_ARG: The password to the host.
#   3. IP_ADDRESS_ARG: The IP address of the host.
#   4. JSON_ARG: The JSON object containing the configurations.
#
create_configurations() {
    local LOGIN_ARG="$1"
    local PASSWORD_ARG="$2"
    local IP_ADDRESS_ARG="$3"
    local JSON_ARG="$4"

    log_debug "\t- Creating the configurations on ${IP_ADDRESS_ARG}"

    # Append header to config template
    cat <<EOF >>"${CONFIG_TEMPLATE}"

config:    
EOF

    # Iterate over each configuration object safely
    while IFS= read -r config_json; do
        local name file
        name=$(jq -r '.name' <<<"$config_json")
        file=$(jq -r '.file' <<<"$config_json")

        create_single_configuration \
            "${LOGIN_ARG}" \
            "${PASSWORD_ARG}" \
            "${IP_ADDRESS_ARG}" \
            "${name}" \
            "${file}" < /dev/null

    done 0< <(jq -c '.swarm.configurations[]' <<<"$JSON_ARG")

    log_warning "###############################"
    log_warning "# Configurations of the Swarm #"
    log_warning "###############################"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" \
        "sudo docker config ls"
}

#
# create_overlay_network
# This function creates a single overlay network in the Swarm cluster.
# Arguments:
#   1. LOGIN_ARG: The login to the host.
#   2. PASSWORD_ARG: The password to the host.
#   3. IP_ADDRESS_ARG: The IP address of the host.
#   4. NAME_ARG: The name of the overlay network.
#   5. ENCRYPTED_ARG: Whether the overlay network is encrypted (true/false).
#   6. ATTACHABLE_ARG: Whether the overlay network is attachable (true/false).
#   7. INTERNAL_ARG: Whether the overlay network is internal (true/false).
#
create_overlay_network() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local IP_ADDRESS_ARG="${3}"
    local NAME_ARG="${4}"
    local ENCRYPTED_ARG="${5}"
    local ATTACHABLE_ARG="${6}"
    local INTERNAL_ARG="${7}"

    log_warning "\t\t- Creating the overlay network ${NAME_ARG} on ${IP_ADDRESS_ARG} (encrypted: ${ENCRYPTED_ARG}, attachable: ${ATTACHABLE_ARG}, internal: ${INTERNAL_ARG})"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS_ARG}" "sudo docker network create --driver overlay --attachable=${ATTACHABLE_ARG} --internal=${INTERNAL_ARG} --opt encrypted=${ENCRYPTED_ARG} ${NAME_ARG}"
}

#
# create_overlay_networks
# - param1: LOGIN_ARG, the login to the host
# - param2: PASSWORD_ARG, the password to the host
# - param3: IP_ADDRESS_ARG, the IP address of the host
# - param4: JSON_ARG, the JSON content containing the overlay networks configuration
#
create_overlay_networks() {
    local LOGIN_ARG="$1"
    local PASSWORD_ARG="$2"
    local IP_ADDRESS_ARG="$3"
    local JSON_ARG="$4"

    log_debug "\t- Creating the overlay networks on ${IP_ADDRESS_ARG}"

    # Iterate over each overlay network safely
    while IFS= read -r overlay_json; do
        local NAME ENCRYPTED ATTACHABLE INTERNAL

        NAME=$(jq -r '.name' <<<"$overlay_json")
        ENCRYPTED=$(jq -r '.encrypted // false' <<<"$overlay_json")
        ATTACHABLE=$(jq -r '.attachable // false' <<<"$overlay_json")
        INTERNAL=$(jq -r '.internal // false' <<<"$overlay_json")

        create_overlay_network \
            "${LOGIN_ARG}" \
            "${PASSWORD_ARG}" \
            "${IP_ADDRESS_ARG}" \
            "${NAME}" \
            "${ENCRYPTED}" \
            "${ATTACHABLE}" \
            "${INTERNAL}" < /dev/null

        cat <<EOF >>"${NETWORK_TEMPLATE}"
  ${NAME}:
     driver: overlay
     internal: true   # isolates backend traffic
EOF

    done 0< <(jq -c '.swarm.networks[].overlays[]' <<<"$JSON_ARG")

    log_warning "#################################"
    log_warning "# Overlay networks of the Swarm #"
    log_warning "#################################"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" \
        "sudo docker network ls"
}

#
# create_replicated_volumes_native
# - param1: LOGIN_ARG, the login to the host
# - param2: PASSWORD_ARG, the password to the host
# - param3: SWARM_JSON_ARG, the JSON content containing the replicated volumes configuration
#
create_replicated_volumes_native() {
    local LOGIN_ARG="$1"
    local PASSWORD_ARG="$2"
    local SWARM_JSON_ARG="$3"
    local REPLICATED_JSON

    REPLICATED_JSON=$(echo "${SWARM_JSON_ARG}" | jq -c '.swarm.volumes[] | select(.replicated) | .replicated')

    
    if [ -n "${REPLICATED_JSON}" ]; then
    log_debug "\t- Creating the replicated volumes"

    # Iterate over each volume object safely
    while IFS= read -r volume_json; do
        local VOLUME_NAME OWNERSHIP PERMISSIONS MOUNTPOINT_DIR
        local HOSTNAME_LIST FOLDER_LIST

        VOLUME_NAME=$(jq -r '.name' <<<"$volume_json")
        OWNERSHIP=$(jq -r '.ownership // empty' <<<"$volume_json")
        PERMISSIONS=$(jq -r '.permissions // empty' <<<"$volume_json")
        MOUNTPOINT_DIR="/mnt/${VOLUME_NAME}"

        # Parse 'hosts' and 'folders' arrays as Bash arrays
        readarray -t HOSTNAME_LIST < <(jq -r '.hosts[]' <<<"$volume_json")
        readarray -t FOLDER_LIST < <(jq -r '.folders[]' <<<"$volume_json")

        # Setup replicated volumes across hosts
        setup_replicated_volumes "${LOGIN_ARG}" "${PASSWORD_ARG}" "${VOLUME_NAME}" "${SWARM_JSON_ARG}" "${HOSTNAME_LIST[@]}" < /dev/null

        log_warning "\t\t- Creating the folders on the volume ${VOLUME_NAME}"
        for FOLDER in "${FOLDER_LIST[@]}"; do
            local IP_ADDRESS
            IP_ADDRESS=$(host "${HOSTNAME_LIST[0]}" | awk '/has address/ { print $4 }')

            log_debug "\t\t\t- Creating the folder ${MOUNTPOINT_DIR}/${FOLDER} on ${HOSTNAME_LIST[0]} at IP address ${IP_ADDRESS}"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" \
                "sudo mkdir -p ${MOUNTPOINT_DIR}/${FOLDER}  /var/lib/${FOLDER} && sudo chown -R 10001:10001 /var/lib/${FOLDER} && sudo chmod -R 755 /var/lib/${FOLDER}" < /dev/null

            cat <<EOF >>"${VOLUME_TEMPLATE}"
  ${VOLUME_NAME}-${FOLDER}:
    driver: local
    driver_opts:
      type: "none"
      o: "bind"
      device: "${MOUNTPOINT_DIR}/${FOLDER}"
EOF

            if [ -n "${OWNERSHIP}" ]; then
                log_debug "\t\t\t- Setting ownership ${OWNERSHIP} on ${MOUNTPOINT_DIR}/${FOLDER} on ${HOSTNAME_LIST[0]} at IP address ${IP_ADDRESS}"
                sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" \
                    "sudo chown -R ${OWNERSHIP} ${MOUNTPOINT_DIR}/${FOLDER}" < /dev/null
            else
                log_debug "\t\t\t - Skipping ownership due to missing value (ownership: '${OWNERSHIP}')"
            fi

            if [ -n "${PERMISSIONS}" ]; then
                log_debug "\t\t\t- Setting permissions ${PERMISSIONS} on ${MOUNTPOINT_DIR}/${FOLDER} on ${HOSTNAME_LIST[0]} at IP address ${IP_ADDRESS}"
                sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" \
                    "sudo chmod -R ${PERMISSIONS} ${MOUNTPOINT_DIR}/${FOLDER}" < /dev/null
            else
                log_debug "\t\t\t - Skipping permissions setting due to missing values (permissions: '${PERMISSIONS}')"
            fi
        done

        # Folder replication check
        log_warning "\t\t- Checking the folder replication on the volume ${VOLUME_NAME}"
        for IP_ADDRESS_INDEX in "${!HOSTNAME_LIST[@]}"; do
            local IP_ADDRESS
            IP_ADDRESS=$(host "${HOSTNAME_LIST[$IP_ADDRESS_INDEX]}" | awk '/has address/ { print $4 }')

            log_debug "\t\t\t- Checking the folder replication on ${HOSTNAME_LIST[$IP_ADDRESS_INDEX]} at IP address ${IP_ADDRESS}"
            sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP_ADDRESS}" \
                "sudo tree -D ${MOUNTPOINT_DIR}" < /dev/null
        done
    done 0< <(jq -c '.[]' <<<"$REPLICATED_JSON")
    else
        log_debug "\t -No replicated volumes found in the configuration."    
    fi
}


#
# create_replicated_volumes_with_plugin
# - param1: LOGIN_ARG, the login to the host
# - param2: PASSWORD_ARG, the password to the host
# - param3: REPLICATED_JSON, the JSON content containing the replicated volumes configuration
#
create_replicated_volumes_with_plugin() {
    local LOGIN_ARG="$1"
    local PASSWORD_ARG="$2"
    local REPLICATED_JSON="$3"

    # Iterate over each volume object safely
    while IFS= read -r volume_json; do
         local VOLUME_NAME OWNERSHIP PERMISSIONS MOUNTPOINT_DIR
         local HOSTNAME_LIST FOLDER_LIST
         local MAIN_MANAGER_IP_ADDRESS
         local MOUNTED_GLUSTER_VOLUME
         local VOLUME_NAME
         local FIRST_HOSTNAME

         OWNERSHIP=$(jq -r '.ownership // empty' <<<"$volume_json")
         PERMISSIONS=$(jq -r '.permissions // empty' <<<"$volume_json")
         VOLUME_NAME="vol1"
         MOUNTED_GLUSTER_VOLUME="/mnt/${VOLUME_NAME}"

         # Parse 'hosts' and 'folders' arrays as Bash arrays
         readarray -t HOSTNAME_LIST < <(jq -r '.hosts[]' <<<"$volume_json")
         readarray -t FOLDER_LIST < <(jq -r '.folders[]' <<<"$volume_json")

         FIRST_HOSTNAME=$(printf "%s\n" "${!HOST_IP_MAP[@]}" | head -n1)
         MAIN_MANAGER_IP_ADDRESS="${HOST_IP_MAP[$FIRST_HOSTNAME]}"

         # Build comma-separated IP string
         IP_LIST=""
        
         for HOST in ${HOSTNAME_LIST[@]}; do
             IP="${HOST_IP_MAP[$HOST]}"
             
             if [[ -n "$IP" ]]; then
                 IP_LIST+="$IP,"
             fi
         done

         # Remove trailing comma
         IP_LIST="${IP_LIST%,}"

         log_debug "\t- Configuring the folder hierarchy on the main node \"${HOSTNAME_LIST[0]}\" (${MAIN_MANAGER_IP_ADDRESS})"
         log_warning "\t\t- Creating the mount folder ${MOUNTED_GLUSTER_VOLUME}"
         sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" "sudo mkdir -p ${MOUNTED_GLUSTER_VOLUME}" < /dev/null

         if [ -n "${OWNERSHIP}" ]; then
             log_debug "\t\t\t- Setting ownership ${OWNERSHIP} on ${MOUNTED_GLUSTER_VOLUME} on \"${HOSTNAME_LIST[0]}\" (${MAIN_MANAGER_IP_ADDRESS})"
             sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" \
                    "sudo chown -R ${OWNERSHIP} ${MOUNTED_GLUSTER_VOLUME}" < /dev/null
         else
             log_debug "\t\t\t - Skipping ownership due to missing value (ownership: '${OWNERSHIP}')"
         fi

         if [ -n "${PERMISSIONS}" ]; then
             log_debug "\t\t\t- Setting permissions ${PERMISSIONS} on ${MOUNTED_GLUSTER_VOLUME} on \"${HOSTNAME_LIST[0]}\" (${MAIN_MANAGER_IP_ADDRESS})"
             sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" "sudo chmod -R ${PERMISSIONS} ${MOUNTED_GLUSTER_VOLUME}" < /dev/null
         else
             log_debug "\t\t\t - Skipping permissions setting due to missing values (permissions: '${PERMISSIONS}')"
         fi

         cat <<EOF >>"${VOLUME_TEMPLATE}"
     ${VOLUME_NAME}:
       driver: glusterfs
       name: "gfs/${VOLUME_NAME}"
EOF

         # Configuring the Docker plugin on each host
         for HOST in ${HOSTNAME_LIST[@]}; do
             IP="${HOST_IP_MAP[$HOST]}"
             
             if [[ -n "$IP" ]]; then
                 log_debug "\t- Configuring the replicated volume plugin on host ${HOST} at IP address ${IP}"

                 log_warning "\t\t- Installing the GlusterFS Docker volume plugin on ${HOST} at IP address ${IP}"
                 sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP}" \
                     "sudo docker plugin install --alias glusterfs trajano/glusterfs-volume-plugin --grant-all-permissions --disable" < /dev/null
                 log_warning "\t\t- Configuring the GlusterFS Docker volume plugin"    
                 sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP}" \
                     "sudo docker plugin set glusterfs SERVERS=${IP_LIST}" < /dev/null
                 log_warning "\t\t- Enabling the GlusterFS Docker volume plugin"    
                 sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${IP}" \
                     "sudo docker plugin enable glusterfs" < /dev/null
             else
                 log_error "❌ Host ${HOST} not found in HOST_IP_MAP"
             fi
         done
    done 0< <(jq -c '.[]' <<<"$REPLICATED_JSON")
}

#
# create_volumes
# - param1: LOGIN_ARG, the login to the host
# - param2: PASSWORD_ARG, the password to the host
# - param3: SWARM_JSON_ARG, the JSON content containing the volume configuration
#
create_volumes() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local SWARM_JSON_ARG="${3}"

cat <<EOF >>"${VOLUME_TEMPLATE}"

volumes:
EOF

    create_replicated_volumes_native "${LOGIN_ARG}" "${PASSWORD_ARG}" "${SWARM_JSON_ARG}"

    log_warning "########################"
    log_warning "# Volumes of the Swarm #"
    log_warning "########################"
    sshpass -p "${PASSWORD_ARG}" ssh "${LOGIN_ARG}@${MAIN_MANAGER_IP_ADDRESS}" \
        "sudo docker volume ls"
}

#
# create_swarm
# This function creates a Swarm cluster based on the provided configuration.
# Arguments:
#   1. LOGIN_ARG: The login to the host.
#   2. PASSWORD_ARG: The password to the host.
#   3. JSON_CONTENT_ARG: The JSON content containing the Swarm configuration.
create_swarm() {
    local LOGIN_ARG="${1}"
    local PASSWORD_ARG="${2}"
    local JSON_CONTENT_ARG="${3}"
    local REGISTRY_IP_ADDRESS
    local REGISTRY_PORT
    local REGISTRY_CERTIFICATE_FILE

    REGISTRY_IP_ADDRESS=$(jq -r '.registry["ip-address"]' <<< "${JSON_CONTENT_ARG}")
    REGISTRY_PORT=$(jq -r '.registry.port' <<< "${JSON_CONTENT_ARG}")
    REGISTRY_CERTIFICATE_FILE=$(jq -r '.registry["certificate-file"]' <<< "${JSON_CONTENT_ARG}")

    # Check that the value is not empty
    if [[ -n "$REGISTRY_IP_ADDRESS" && -n "$REGISTRY_PORT" && -n "${REGISTRY_CERTIFICATE_FILE}" ]]; then
        # Check that the file exists
        if [[ -f "${REGISTRY_CERTIFICATE_FILE}" && -s "${REGISTRY_CERTIFICATE_FILE}" ]]; then
            if ! grep -q "BEGIN CERTIFICATE" "${REGISTRY_CERTIFICATE_FILE}"; then
                log_error "❌ File exists but does not appear to be a valid certificate. Aborting ..."
                exit 1
            fi
        else
            log_error "Error: Certificate file does not exist at path '${REGISTRY_CERTIFICATE_FILE}'."
            exit 1
        fi

        log_info "Using local registry at ${REGISTRY_IP_ADDRESS}:${REGISTRY_PORT} with certificate file ${REGISTRY_CERTIFICATE_FILE}"        
    elif [[ -z "$REGISTRY_IP_ADDRESS" && -z "$REGISTRY_PORT" && -z "${REGISTRY_CERTIFICATE_FILE}" ]]; then
        log_info "Local registry is not used"
    else
        log_error "❌ Partial configuration detected—some variables are missing while others are present."
        [[ -z "$REGISTRY_IP_ADDRESS" ]] && log_error "\tMissing: REGISTRY_IP_ADDRESS"
        [[ -z "$REGISTRY_PORT" ]] && log_error "\tMissing: REGISTRY_PORT"
        [[ -z "${REGISTRY_CERTIFICATE_FILE}" ]] && log_error "\tMissing: REGISTRY_CERTIFICATE_FILE"
        exit 1
    fi     

    log_info "Creating the Swarm cluster"
    
    create_managers "${LOGIN_ARG}" "${PASSWORD_ARG}" "${JSON_CONTENT_ARG}" "${REGISTRY_IP_ADDRESS}" "${REGISTRY_PORT}" "${REGISTRY_CERTIFICATE_FILE}"
    create_workers "${LOGIN_ARG}" "${PASSWORD_ARG}" "${JSON_CONTENT_ARG}" "${REGISTRY_IP_ADDRESS}" "${REGISTRY_PORT}" "${REGISTRY_CERTIFICATE_FILE}"
    create_volumes "${LOGIN_ARG}" "${PASSWORD_ARG}" "${JSON_CONTENT_ARG}"

    log_info "✅ Swarm cluster created successfully."    
}

#
# main
# The main function that orchestrates the creation of the Swarm cluster.
#
main() {
    local DOCKER_COMPOSE_TEMPLATE="./docker-compose-template.yml"
    local JSON_CONTENT
    local TMP_DIR

    MANDATORY_PARAMETER_LIST=("CONFIGURATION_FILE" "LOGIN" "PASSWORD")
    JOIN_WORKER_CMD_FILE="./join_worker_cmd.swarm"
    MANAGER_IP_ADDRESS_FILE="./ip.swarm"
    JOIN_MANAGER_CMD_FILE="./join_mgr_cmd.swarm"
    CONFIG_DIR=$(mktemp -d)

    # Parses the parameters
    while (("$#")); do
        case "${1}" in
        --default-hostname)
            DEFAULT_HOSTNAME="${2}"
            shift # past argument
            shift # past value
            ;;
        --configuration-file | -f)
            CONFIGURATION_FILE="${2}"
            shift # past argument
            shift # past value
            ;;
        --login)
            LOGIN="${2}"
            shift # past argument
            shift # past value
            ;;
        --password)
            PASSWORD="${2}"
            shift # past argument
            shift # past value
            ;;
        -h | --help)
            display_help
            shift # past argument
            exit 1
            ;;
        --) # end argument parsing
            shift
            break
            ;;
        *) # preserve positional arguments
            shift
            ;;
        esac
    done

    DEFAULT_HOSTNAME=${DEFAULT_HOSTNAME:-"undefined"}

    # Initialize variables from values saved in files
    if [[ -s "${JOIN_WORKER_CMD_FILE}" ]]; then
        log_info "Loading the Swarm token"

        JOIN_WORKER_CMD=$(<"${JOIN_WORKER_CMD_FILE}")
    fi

    if [[ -s "${MANAGER_IP_ADDRESS_FILE}" ]]; then
        log_info "Loading the manager's IP address"

        MAIN_MANAGER_IP_ADDRESS=$(<"${MANAGER_IP_ADDRESS_FILE}")
    fi

    if [[ -s "${JOIN_MANAGER_CMD_FILE}" ]]; then
        log_info "Loading the manager's IP address"

        JOIN_MGR_CMD=$(<"${JOIN_MANAGER_CMD_FILE}")
    fi

    # Check all mandatory parameter are set
    check_all_mandatory_parameters "${MANDATORY_PARAMETER_LIST[@]}"

    display_settings

    # Installing required packages
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apache2-utils sshpass

    # Check if the file exists and is not empty
    if [ ! -s "${CONFIGURATION_FILE}" ]; then
        log_error "❌ Error: Configuration file '${CONFIGURATION_FILE}' is missing or empty." >&2
        exit 1
    fi

    TMP_DIR=$(mktemp -d)
    JSON_CONTENT=$(cat "${CONFIGURATION_FILE}")
    CONFIG_TEMPLATE="${TMP_DIR}/config-template.yml"
    NETWORK_TEMPLATE="${TMP_DIR}/network-template.yml"
    SECRET_TEMPLATE="${TMP_DIR}/secret-template.yml"
    VOLUME_TEMPLATE="${TMP_DIR}/volume-template.yml"

    # Initializing the template files  
    cat <<EOF >>"${SECRET_TEMPLATE}"

secrets:
EOF

cat <<EOF >>"${NETWORK_TEMPLATE}"

networks:
EOF

    # Creates the Swarm 
    create_swarm "${LOGIN}" "${PASSWORD}" "${JSON_CONTENT}"
    
    log_info "Creating the Docker compose template file at ${DOCKER_COMPOSE_TEMPLATE}"
    cat <<EOF_TEMPLATE >"${DOCKER_COMPOSE_TEMPLATE}"
version: '3.8'

services:

$(cat ${CONFIG_TEMPLATE})

$(cat ${NETWORK_TEMPLATE})

$(cat ${SECRET_TEMPLATE})

$(cat ${VOLUME_TEMPLATE})
EOF_TEMPLATE

    log_warning "⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️"
    log_warning "⚠️                                                                       ️⚠️"
    log_warning "⚠️ DO NOT FORGET TO CHANGE THE PASSWORD OF THE ROOT USER ON ALL NODES !!! ⚠️"
    log_warning "⚠️                                                                       ️⚠️"
    log_warning "⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️"
    log_info "A template of a Docker compose file is available at ${DOCKER_COMPOSE_TEMPLATE}."
    log_info "It declares all the resources we've just created."
}

time main "$@"
