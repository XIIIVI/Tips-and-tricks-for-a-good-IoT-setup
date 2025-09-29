#!/usr/bin/env bash

# ============================================================
#  Project:   create-custom-grafana-image.sh
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

set -eo pipefail
# Disable history expansion so '!!' in passwords stays literal
set +o histexpand

source "../../commons/commons-grafana.sh"
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
  --version-number        Grafana image version tag (e.g., 12.2.0)
  --admin-passwd          Desired admin password for Grafana
  --grafana-url           URL of the Grafana instance running in the swarm
  --sa-token              Service account token to use to export the Grafan's resources
  --local-registry-address
                          Hostname or IP of the local registry (e.g., registry.local)

Optional:
  --local-registry-port   Registry port (default: 4443)
  --image-version         Version tag to use for the exported image (default: --version-number)
  --arch                  Target architecture (default: arm64). Typical values: arm64, amd64
  -h | --help             Show this help

Examples:
  $0 --version-number 11.1.0 --admin-passwd 'S3cure!' --grafana-url http://192.168.2.191:8080 \\
     --local-registry-address registry.local --local-registry-port 5000 --image-version 11.1.0-custom --arch amd64
EOF
  exit 1
}

ADMIN_PASSWD=""
VERSION_NUMBER=""
GRAFANA_URL=""
IMAGE_VERSION=""
LOCAL_REGISTRY_ADDRESS=""
SA_TOKEN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --admin-passwd) ADMIN_PASSWD="$2"; shift 2 ;;
    --arch) TARGET_ARCH="$2"; shift 2 ;;
    --grafana-url) GRAFANA_URL="$2"; shift 2 ;;
    --image-version) IMAGE_VERSION="$2"; shift 2 ;;
    --local-registry-address) LOCAL_REGISTRY_ADDRESS="$2"; shift 2 ;;
    --local-registry-port) LOCAL_REGISTRY_PORT="$2"; shift 2 ;;
    --sa-token) SA_TOKEN="$2"; shift 2 ;;
    --version-number) VERSION_NUMBER="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) log_error "❌ Unknown argument: $1"; usage ;;
  esac
done

# Mandatory checks
[[ -z "${VERSION_NUMBER}" ]] && echo "Missing --version-number" && usage
[[ -z "${ADMIN_PASSWD}" ]] && echo "Missing --admin-passwd" && usage
[[ -z "${GRAFANA_URL}" ]] && echo "Missing --grafana-url" && usage
[[ -z "${LOCAL_REGISTRY_ADDRESS}" ]] && echo "Missing --local-registry-address" && usage
[[ -z "${SA_TOKEN}" ]] && echo "Missing --sa-token" && usage

if [[ -z "${IMAGE_VERSION}" ]]; then
  IMAGE_VERSION="${VERSION_NUMBER}"
fi

# --------------------------------------
# Environment + prerequisites
# --------------------------------------
REQUIRED_BINS=(docker curl jq tree)
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

# Install Grizzly if missing
install_grizzly "${HOST_ARCH}"

if ! command -v grr >/dev/null 2>&1; then
  log_error "❌ grr command not found even after installation."
  exit 1
fi

# Enable binfmt for cross-arch containers if needed
if [[ "${HOST_ARCH}" != "${TARGET_ARCH}" ]]; then
  log_info "Host arch is ${HOST_ARCH}; target image arch is ${TARGET_ARCH}. Enabling binfmt..."
  # Requires privileged helper (Docker Desktop usually has this already)
  docker run --rm --privileged tonistiigi/binfmt --install "${TARGET_ARCH}" >/dev/null 2>&1 || true
fi

# Exporting the Grafana resources
GRIZZLY_BASEDIR="$(mktemp -d)/grizzly"

export_grafana_resources "${GRAFANA_URL}" "${SA_TOKEN}" "${GRIZZLY_BASEDIR}"

# Install the Grafana builder
install_and_configure_grafana_builder "${TARGET_ARCH}" "${VERSION_NUMBER}" "127.0.0.1" "3000" "${ADMIN_PASSWD}"

# Import the Grizzly's exported resources
import_grafana_resources "http://127.0.0.1:3000" "${SA_TOKEN}" "${GRIZZLY_BASEDIR}"

# Use loopback to avoid docker-for-mac/iptables oddities
TARGET_IMAGE="${LOCAL_REGISTRY_ADDRESS}:${LOCAL_REGISTRY_PORT}/grafana:${IMAGE_VERSION}"
GRAFANA_CONTAINER="grafana_builder"

# --------------------------------------
# Copy grafana.db out of the container
# --------------------------------------
log_info "📤 Extracting grafana.db from the running container..."
CUSTOM_DB="grafana.db"
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

# Clean up any existing local image with the same tag
if docker image inspect "${TARGET_IMAGE}" >/dev/null 2>&1; then
    log_debug "\t- Removing existing local image ${TARGET_IMAGE}"
    docker rmi -f "${TARGET_IMAGE}" || true
fi

# Build and push fresh image
log_debug "\t- RBuild and push the image ${TARGET_IMAGE}"
docker buildx build \
  --platform "linux/${TARGET_ARCH}" \
  --tag "${TARGET_IMAGE}" \
  --push \
  "${BUILD_CTX}"

# Cleanup build context + local DB copy
log_info "🧼 Cleaning up temporary files..."
rm -rf "${BUILD_CTX}" "./${CUSTOM_DB}" "${GRIZZLY_BASEDIR}"

log_info "✅ Custom Grafana image built and pushed successfully: ${TARGET_IMAGE}"