#!/usr/bin/env bash
set -euo pipefail

source "../../commons/commons-log.sh"

# ------------------------------------------------------------------------------
# Grafana + Grizzly one-shot bootstrapper
# - Pulls a specific Grafana version into Docker
# - Sets admin password
# - Creates a 1-day service account token (SA_TOKEN)
# - Installs Grafana/grizzly and configures it
# - Pushes resources from a Grizzly base directory
# - Commits the container to an image, tars it, then imports/pushes to a local registry
#
# Requirements:
# - docker, curl, jq
# - grr (Grizzly) or Go toolchain to install it (go >= 1.20 recommended)
# ------------------------------------------------------------------------------

# --------------------------------------
# Defaults
# --------------------------------------
ARCH="arm64"
LOCAL_REGISTRY_PORT="4443"

# --------------------------------------
# Args
# --------------------------------------
usage() {
  cat <<EOF
Usage: $0 --version-number <grafana_version> --admin-passwd <password> --grizzly-basedir <dir> --local-registry-address <addr> [options]

Mandatory:
  --version-number        Grafana image version tag (e.g., 11.2.0)
  --admin-passwd          Desired admin password for Grafana
  --grizzly-basedir       Directory containing Grizzly resources to import
  --local-registry-address
                          Hostname or IP of the local registry (e.g., registry.local)

Optional:
  --local-registry-port   Registry port (default: 4443)
  --image-version         Version tag to use for the exported image (default: --version-number)
  --arch                  Target architecture (default: arm64). Typical values: arm64, amd64
  -h | --help             Show this help

Examples:
  $0 --version-number 11.1.0 --admin-passwd 'S3cure!' --grizzly-basedir ./dashboards \\
     --local-registry-address registry.local --local-registry-port 5000 --image-version 11.1.0-custom --arch amd64
EOF
  exit 1
}

VERSION_NUMBER=""
ADMIN_PASSWD=""
GRIZZLY_BASEDIR=""
LOCAL_REGISTRY_ADDRESS=""
IMAGE_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version-number) VERSION_NUMBER="$2"; shift 2 ;;
    --admin-passwd) ADMIN_PASSWD="$2"; shift 2 ;;
    --grizzly-basedir) GRIZZLY_BASEDIR="$2"; shift 2 ;;
    --local-registry-address) LOCAL_REGISTRY_ADDRESS="$2"; shift 2 ;;
    --local-registry-port) LOCAL_REGISTRY_PORT="$2"; shift 2 ;;
    --image-version) IMAGE_VERSION="$2"; shift 2 ;;
    --arch) ARCH="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) log_error "Unknown argument: $1"; usage ;;
  esac
done

# Mandatory checks
[[ -z "${VERSION_NUMBER}" ]] && echo "Missing --version-number" && usage
[[ -z "${ADMIN_PASSWD}" ]] && echo "Missing --admin-passwd" && usage
[[ -z "${GRIZZLY_BASEDIR}" ]] && echo "Missing --grizzly-basedir" && usage
[[ -z "${LOCAL_REGISTRY_ADDRESS}" ]] && echo "Missing --local-registry-address" && usage

if [[ -z "${IMAGE_VERSION}" ]]; then
  IMAGE_VERSION="${VERSION_NUMBER}"
fi

# --------------------------------------
# Environment + prerequisites
# --------------------------------------
REQUIRED_BINS=(docker curl jq)
for b in "${REQUIRED_BINS[@]}"; do
  command -v "$b" >/dev/null 2>&1 || { log_error "Required binary not found: $b"; exit 1; }
done

# Use loopback to avoid docker-for-mac/iptables oddities
GRAFANA_HOST="127.0.0.1"
GRAFANA_PORT="3000"
GRAFANA_URL="http://${GRAFANA_HOST}:${GRAFANA_PORT}"

# Names & tags
GRAFANA_IMAGE="grafana/grafana:${VERSION_NUMBER}"
GRAFANA_CONTAINER="grafana_${VERSION_NUMBER//[^a-zA-Z0-9]/_}_${ARCH}"
CUSTOM_IMAGE_LOCAL="grafana-custom:${IMAGE_VERSION}-${ARCH}"
TAR_FILE="grafana-${IMAGE_VERSION}-${ARCH}.tar"
TARGET_IMAGE="${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}/grafana:${IMAGE_VERSION}"

# --------------------------------------
# Pull and run Grafana
# --------------------------------------
log_info "Pulling Grafana image ${GRAFANA_IMAGE} for linux/${ARCH}..."
DOCKER_DEFAULT_PLATFORM="linux/${ARCH}" docker pull --platform "linux/${ARCH}" "${GRAFANA_IMAGE}"

# Stop/remove if exists
if docker ps -a --format '{{.Names}}' | grep -q "^${GRAFANA_CONTAINER}\$"; then
  log_warning "\t- Container ${GRAFANA_CONTAINER} exists. Removing..."
  docker rm -f "${GRAFANA_CONTAINER}" >/dev/null 2>&1 || true
fi

log_debug "\t- Starting Grafana container ${GRAFANA_CONTAINER}..."
docker run -d --name "${GRAFANA_CONTAINER}" \
  -p "${GRAFANA_PORT}:3000" \
  -e "GF_SECURITY_ADMIN_PASSWORD=${ADMIN_PASSWD}" \
  --platform "linux/${ARCH}" \
  "${GRAFANA_IMAGE}" >/dev/null

# Wait for Grafana readiness
log_debug "\t- Waiting for Grafana to be ready at ${GRAFANA_URL}..."
for i in {1..60}; do
  if curl -fsS "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
    break
  fi
  sleep 2
  if [[ $i -eq 60 ]]; then
    echo "Grafana did not become ready in time."
    exit 1
  fi
done

# --------------------------------------
# Ensure admin password (explicit API change)
# --------------------------------------
# Even though GF_SECURITY_ADMIN_PASSWORD initialized it, explicitly set via API to be sure.
log_debug "\t- Setting admin password via API..."
curl -fsS -X PUT "${GRAFANA_URL}/api/admin/users/1/password" \
  -u "admin:${ADMIN_PASSWD}" \
  -H 'Content-Type: application/json' \
  -d "{\"password\":\"${ADMIN_PASSWD}\"}" >/dev/null

# --------------------------------------
# Create 1-day service account and token
# --------------------------------------
log_debug "\t- Creating service account and token valid for 1 day..."
SA_NAME="grizzly-sa-$(date +%s)"
# Create Service Account
SA_ID=$(
  curl -fsS -X POST "${GRAFANA_URL}/api/service-accounts" \
    -u "admin:${ADMIN_PASSWD}" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"${SA_NAME}\",\"role\":\"Admin\"}" | jq -r '.id'
)
if [[ -z "${SA_ID}" || "${SA_ID}" == "null" ]]; then
  log_error "Failed to create service account."
  exit 1
fi

# Create Service Account token (1 day = 86400 seconds)
SA_TOKEN=$(
  curl -fsS -X POST "${GRAFANA_URL}/api/service-accounts/${SA_ID}/tokens" \
    -u "admin:${ADMIN_PASSWD}" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"${SA_NAME}-token\",\"role\":\"Admin\",\"secondsToLive\":86400}" | jq -r '.key'
)
if [[ -z "${SA_TOKEN}" || "${SA_TOKEN}" == "null" ]]; then
  log_error "Failed to create service account token."
  exit 1
fi

# Export for later steps within this shell
export SA_TOKEN

# --------------------------------------
# Install grizzly (grr) if missing
# --------------------------------------
log_info "Installing Grizzly"

if ! command -v grr >/dev/null 2>&1; then
  log_warning "\t grr not found. Attempting installation via 'go install'..."
  if ! command -v go >/dev/null 2>&1; then
    log_error "Go is not installed. Please install Go or pre-install grr, then re-run."
    exit 1
  fi
  # Respect GOBIN; otherwise use GOPATH/bin or default ~/go/bin
  GOBIN_DIR="${GOBIN:-}"
  if [[ -z "${GOBIN_DIR}" ]]; then
    GOPATH_DIR="${GOPATH:-$HOME/go}"
    GOBIN_DIR="${GOPATH_DIR}/bin"
  fi
  mkdir -p "${GOBIN_DIR}"
  # Install latest grr
  GO111MODULE=on GOBIN="${GOBIN_DIR}" go install github.com/grafana/grizzly/cmd/grr@latest
  export PATH="${GOBIN_DIR}:${PATH}"
  if ! command -v grr >/dev/null 2>&1; then
    log_error "Failed to install grr."
    exit 1
  fi
fi

# --------------------------------------
# Configure grizzly with token and Grafana URL
# --------------------------------------
log_debug "\t- Configuring Grizzly context..."
GRIZZLY_DIR="${HOME}/.grizzly"
mkdir -p "${GRIZZLY_DIR}"
GRIZZLY_CONFIG="${GRIZZLY_DIR}/config.yaml"

cat > "${GRIZZLY_CONFIG}" <<YAML
contexts:
  default:
    providers:
      grafana:
        url: ${GRAFANA_URL}
        auth:
          token: ${SA_TOKEN}
YAML

log_debug "\t- Grizzly configured at ${GRIZZLY_CONFIG}"

# --------------------------------------
# Run grr push
# --------------------------------------
if [[ ! -d "${GRIZZLY_BASEDIR}" ]]; then
  log_error "Grizzly base directory not found: ${GRIZZLY_BASEDIR}"
  exit 1
fi

log_debug "\t- Pushing resources from ${GRIZZLY_BASEDIR} with grr..."
grr push "${GRIZZLY_BASEDIR}" --context default

# --------------------------------------
# Commit container to image and save as tar
# --------------------------------------
log_info "Generating the customized image of Grafana"

log_debug "\t- Committing container ${GRAFANA_CONTAINER} to image ${CUSTOM_IMAGE_LOCAL}..."
docker commit "${GRAFANA_CONTAINER}" "${CUSTOM_IMAGE_LOCAL}" >/dev/null

log_debug "\t- Saving image to tar: ${TAR_FILE}..."
docker save -o "${TAR_FILE}" "${CUSTOM_IMAGE_LOCAL}"

# --------------------------------------
# Import and push to local registry
# --------------------------------------
log_debug "\t- Loading tar into Docker..."
docker load -i "${TAR_FILE}" >/dev/null

log_debug "\t- Tagging for registry ${TARGET_IMAGE}..."
docker tag "${CUSTOM_IMAGE_LOCAL}" "${TARGET_IMAGE}"

log_debug "\t- Pushing to ${TARGET_IMAGE}..."
docker push "${TARGET_IMAGE}"

cat <<EOF

Done.

Details:
- Grafana container: ${GRAFANA_CONTAINER} (${GRAFANA_IMAGE}, linux/${ARCH})
- Admin password set via env and API.
- Service account token exported as SA_TOKEN (expires in ~24h).
- Grizzly configured at: ${GRIZZLY_CONFIG}
- Grizzly push sources: ${GRIZZLY_BASEDIR}
- Committed image: ${CUSTOM_IMAGE_LOCAL}
- Tar archive: ${TAR_FILE}
- Pushed image: ${TARGET_IMAGE}

Notes:
- Architecture used: ${ARCH}. For a different arch, pass --arch amd64 (or other).
- Multi-platform: this script prepares a single-arch image (default arm64). To publish multiple architectures,
  run the full pipeline per architecture and create a manifest list afterwards, e.g.:
    docker buildx imagetools create \
      --tag ${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}/grafana:${IMAGE_VERSION} \
      ${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}/grafana:${IMAGE_VERSION}-arm64 \
      ${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}/grafana:${IMAGE_VERSION}-amd64

EOF
