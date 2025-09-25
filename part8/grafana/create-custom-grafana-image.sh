#!/usr/bin/env bash
set -eo pipefail
# Disable history expansion so '!!' in passwords stays literal
set +o histexpand

source "../../commons/commons-log.sh"

# ------------------------------------------------------------------------------
# Grafana + Grizzly bootstrapper with cross-arch support
# - Pulls/starts Grafana for TARGET_ARCH (default arm64) even on an amd64 host
# - Sets admin password, creates SA token (1 day)
# - Installs Go (HOST_ARCH) if missing, installs grr
# - Configures grr and pushes resources
# - Commits container, saves to tar, loads and pushes to local registry
# - Optional: create a multi-arch manifest if you have other arch images pushed
#
# Requirements: docker, curl, jq
# Optional: buildx available for multi-arch manifest creation
# ------------------------------------------------------------------------------

# --------------------------------------
# Defaults
# --------------------------------------
TARGET_ARCH="arm64"
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
    --admin-passwd) ADMIN_PASSWD="$2"; shift 2 ;;
    --arch) TARGET_ARCH="$2"; shift 2 ;;
    --grizzly-basedir) GRIZZLY_BASEDIR="$2"; shift 2 ;;
    --image-version) IMAGE_VERSION="$2"; shift 2 ;;
    --local-registry-address) LOCAL_REGISTRY_ADDRESS="$2"; shift 2 ;;
    --local-registry-port) LOCAL_REGISTRY_PORT="$2"; shift 2 ;;
    --version-number) VERSION_NUMBER="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) log_error "❌ Unknown argument: $1"; usage ;;
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
  command -v "$b" >/dev/null 2>&1 || { log_error "❌ Required binary not found: $b"; exit 1; }
done

# Normalize HOST_ARCH to Go/Docker naming
uname_m="$(uname -m)"
case "$uname_m" in
  x86_64) HOST_ARCH="amd64" ;;
  aarch64) HOST_ARCH="arm64" ;;
  armv7l) HOST_ARCH="armv7" ;;
  *) log_error "❌ Unsupported host arch: $uname_m"; exit 1 ;;
esac

# Enable binfmt for cross-arch containers if needed
if [[ "${HOST_ARCH}" != "${TARGET_ARCH}" ]]; then
  log_info "Host arch is ${HOST_ARCH}; target image arch is ${TARGET_ARCH}. Enabling binfmt..."
  # Requires privileged helper (Docker Desktop usually has this already)
  docker run --rm --privileged tonistiigi/binfmt --install "${TARGET_ARCH}" >/dev/null 2>&1 || true
fi

# Use loopback to avoid docker-for-mac/iptables oddities
GRAFANA_HOST="127.0.0.1"
GRAFANA_PORT="3000"
GRAFANA_URL="http://${GRAFANA_HOST}:${GRAFANA_PORT}"

# Names & tags
GRAFANA_IMAGE="grafana/grafana:${VERSION_NUMBER}"
GRAFANA_CONTAINER="grafana_builder"
CUSTOM_DB="grafana.db"
TARGET_IMAGE="${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}/grafana:${IMAGE_VERSION}"

# --------------------------------------
# Pull and run Grafana
# --------------------------------------
log_info "⤵️ Pulling Grafana image ${GRAFANA_IMAGE} for linux/${TARGET_ARCH}..."
docker pull --platform "linux/${TARGET_ARCH}" "${GRAFANA_IMAGE}"

# Stop/remove if exists
if docker ps -a --format '{{.Names}}' | grep -q "^${GRAFANA_CONTAINER}\$"; then
  log_warning "\t- 🚮 Container ${GRAFANA_CONTAINER} exists. Removing..."
  docker rm -f "${GRAFANA_CONTAINER}" >/dev/null 2>&1 || true
fi

log_debug "\t- ▶️ Starting Grafana container ${GRAFANA_CONTAINER}..."
docker run -d --name "${GRAFANA_CONTAINER}" \
  -p "${GRAFANA_PORT}:3000" \
  -e "GF_SECURITY_ADMIN_PASSWORD=${ADMIN_PASSWD}" \
  --platform "linux/${TARGET_ARCH}" \
  "${GRAFANA_IMAGE}" >/dev/null

# Wait for Grafana readiness
log_debug "\t- 🕗 Waiting for Grafana to be ready at ${GRAFANA_URL}..."
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
  curl -fsS -X POST "${GRAFANA_URL}/api/serviceaccounts" \
    -u "admin:${ADMIN_PASSWD}" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"${SA_NAME}\",\"role\":\"Admin\"}" | jq -r '.id'
)
if [[ -z "${SA_ID}" || "${SA_ID}" == "null" ]]; then
  log_error "❌ Failed to create service account."
  exit 1
fi

# Create Service Account token (1 day = 86400 seconds)
SA_TOKEN=$(
  curl -fsS -X POST "${GRAFANA_URL}/api/serviceaccounts/${SA_ID}/tokens" \
    -u "admin:${ADMIN_PASSWD}" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"${SA_NAME}-token\",\"role\":\"Admin\",\"secondsToLive\":86400}" | jq -r '.key'
)
if [[ -z "${SA_TOKEN}" || "${SA_TOKEN}" == "null" ]]; then
  log_error "❌ Failed to create service account token."
  exit 1
fi

# Export for later steps within this shell
export SA_TOKEN

# --------------------------------------
# Install grizzly (grr) if missing
# --------------------------------------
log_info "📦 Installing Grizzly"

if ! command -v grr >/dev/null 2>&1; then
  log_warning "\t grr not found. Attempting installation via 'go install'..."
  if ! command -v go >/dev/null 2>&1; then
    echo "Go not found. Installing for host arch ${HOST_ARCH}..."
    GO_VERSION="1.22.7"
    case "${HOST_ARCH}" in
      amd64|arm64) GO_TARBALL="go${GO_VERSION}.linux-${HOST_ARCH}.tar.gz" ;;
      armv7)       GO_TARBALL="go${GO_VERSION}.linux-armv6l.tar.gz" ;; # closest available; adjust if needed
      *) echo "Unsupported host arch for Go: ${HOST_ARCH}"; exit 1 ;;
    esac
    GO_URL="https://go.dev/dl/${GO_TARBALL}"
    TMP_DIR="$(mktemp -d)"
    pushd "${TMP_DIR}" >/dev/null
    curl -fsSLO "${GO_URL}"
    sudo tar -C /usr/local -xzf "${GO_TARBALL}"
    popd >/dev/null
    rm -rf "${TMP_DIR}"
    export PATH="/usr/local/go/bin:${PATH}"
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
    log_error "❌ Failed to install grr."
    exit 1
  fi
fi

# --------------------------------------
# Configure grizzly with token and Grafana URL
# --------------------------------------
log_debug "\t- Configuring Grizzly context..."
grr config set grafana.url "http://127.0.0.1:3000/"
grr config set grafana.token "${SA_TOKEN}"
grr config set targets Datasource,DashboardFolder,LibraryElement,Dashboard,AlertRuleGroup,AlertNotificationPolicy,AlertContactPoint,AlertNotificationTemplate
grr config set output-format json

# --------------------------------------
# Run grr push
# --------------------------------------
if [[ ! -d "${GRIZZLY_BASEDIR}" ]]; then
  log_error "❌ Grizzly base directory not found: ${GRIZZLY_BASEDIR}"
  exit 1
fi

log_debug "\t-⤴️ Pushing resources from ${GRIZZLY_BASEDIR} with grr..."
grr push "${GRIZZLY_BASEDIR}"

# --------------------------------------
# Copy grafana.db out of the container
# --------------------------------------
log_info "📤 Extracting grafana.db from the running container..."
docker cp "${GRAFANA_CONTAINER}:/var/lib/grafana/grafana.db" "./${CUSTOM_DB}"

# Stop and remove the container
log_info "🚮 Removing the running container..."
docker rm -f "${GRAFANA_CONTAINER}" >/dev/null 2>&1 || true

# --------------------------------------
# Build TARGET arch image by injecting grafana.db and push
# --------------------------------------
log_info "🔧 Preparing build context for target arch ${TARGET_ARCH}..."
BUILD_CTX="$(mktemp -d)"
cp "./${CUSTOM_DB}" "${BUILD_CTX}/grafana.db"

# Minimal Dockerfile that injects the DB into the official image for TARGET_ARCH
cat > "${BUILD_CTX}/Dockerfile" <<EOF
# Use the official image for the desired version; buildx will pull the ${TARGET_ARCH} variant
FROM grafana/grafana:${VERSION_NUMBER}
# Replace SQLite database with customized one
COPY --chown=472:472 grafana.db /var/lib/grafana/grafana.db
EOF

# Ensure buildx exists and a builder is selected
if ! docker buildx version >/dev/null 2>&1; then
  log_error "❌ docker buildx is required. Please install/enable Docker Buildx."
  exit 1
fi
# Create a throwaway builder if none is active
if ! docker buildx inspect >/dev/null 2>&1; then
  docker buildx create --use >/dev/null
fi

log_info "⚙️ Building and pushing ${TARGET_IMAGE} for linux/${TARGET_ARCH}..."
docker buildx build \
  --platform "linux/${TARGET_ARCH}" \
  -t "${TARGET_IMAGE}" \
  --push \
  "${BUILD_CTX}"

# Cleanup build context + local DB copy
rm -rf "${BUILD_CTX}" "./${CUSTOM_DB}"

log_info "✅ Custom Grafana image built and pushed successfully: ${TARGET_IMAGE}"