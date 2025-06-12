#!/bin/bash

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

# Ensure a hostname is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <registry_hostname>"
  exit 1
fi

REGISTRY_HOSTNAME=$1

# Define the current directory
REGISTRY_DIR="$(pwd)/docker-registry"

rm -Rf "${REGISTRY_DIR}"

# Create necessary directories
mkdir -p "$REGISTRY_DIR/certs" "$REGISTRY_DIR/data"

openssl req -newkey rsa:4096 -nodes -sha256 -keyout "$REGISTRY_DIR/certs/registry.key" \
  -addext "subjectAltName = IP:192.168.2.90" \
  -x509 -days 3650 -out "$REGISTRY_DIR/certs/registry.crt" \
  -subj "/C=FR/ST=IDF/L=Paris/O=MyOrg/CN=$REGISTRY_HOSTNAME"

openssl x509 -in "$REGISTRY_DIR/certs/registry.crt" -text -noout | grep -A1 "Subject Alternative Name"


# Create docker-compose file
cat <<EOF >"$REGISTRY_DIR/docker-compose.yml"
version: '3.8'

services:
  registry:
    image: registry:2.8.2
    container_name: docker_registry
    restart: always
    ports:
      - "4443:443"
    environment:
      REGISTRY_HTTP_ADDR: "0.0.0.0:443"
      REGISTRY_HTTP_TLS_CERTIFICATE: "/certs/registry.crt"
      REGISTRY_HTTP_TLS_KEY: "/certs/registry.key"
      REGISTRY_HTTP_HEADERS_Access-Control-Allow-Origin: '[http://$REGISTRY_HOSTNAME:8888]'
      REGISTRY_HTTP_HEADERS_Access-Control-Allow-Methods: '[HEAD,GET,OPTIONS,DELETE]'
      REGISTRY_HTTP_HEADERS_Access-Control-Allow-Credentials: '[true]'
      REGISTRY_HTTP_HEADERS_Access-Control-Allow-Headers: '[Authorization,Accept,Cache-Control]'
      REGISTRY_HTTP_HEADERS_Access-Control-Expose-Headers: '[Docker-Content-Digest]'
      REGISTRY_STORAGE_DELETE_ENABLED: 'true'
    volumes:
      - ./data:/var/lib/registry
      - ./certs:/certs

  registry-ui:
    image: joxit/docker-registry-ui:latest
    container_name: registry_ui
    restart: always
    ports:
      - "8888:80"
    environment:
      - SINGLE_REGISTRY=true
      - REGISTRY_TITLE=Docker Registry UI
      - DELETE_IMAGES=true
      - SHOW_CONTENT_DIGEST=true
      - NGINX_PROXY_PASS_URL=https://docker_registry:443
      - SHOW_CATALOG_NB_TAGS=true
      - CATALOG_MIN_BRANCHES=1
      - CATALOG_MAX_BRANCHES=1
      - TAGLIST_PAGE_SIZE=100
      - REGISTRY_SECURED=false
      - CATALOG_ELEMENTS_LIMIT=1000
    depends_on:
      - registry
EOF

# Start the services
cd "$REGISTRY_DIR" || exit
docker-compose up -d

log_info "Docker registry with UI is set up for $REGISTRY_HOSTNAME!"

log_debug "/!\ ON ALL THE CLIENTS, copy $REGISTRY_DIR/certs/registry.crt into /usr/local/share/ca-certificates/registry.crt"
log_debug "Then run 'sudo update-ca-certificates' to trust the self-signed certificate."
log_debug "Finally, restart the Docker service with 'sudo systemctl restart docker'."
