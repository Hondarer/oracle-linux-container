#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SRC_DIR="${REPO_ROOT}/src"
CONTAINERFILE_WSL="${SRC_DIR}/Containerfile.wsl"
PREPARE_WSL_SCRIPT="${SRC_DIR}/wsl/prepare-wsl-rootfs.sh"

IMAGE_REF=""
OUTPUT_PATH="./wsl-rootfs.tar.gz"
SKIP_PULL=0

TEMP_SUFFIX="$(date +%s)-$$"
TEMP_IMAGE_TAG="localhost/oracle-linux-wsl-export:${TEMP_SUFFIX}"
TEMP_CONTAINER_ID=""
TEMP_IMAGE_BUILT=0

usage() {
    cat <<'EOF'
Usage:
  ./export-wsl.sh --image-ref <image-ref> [--output <path>] [--skip-pull]

Options:
  --image-ref <ref>   Export source container image reference.
                      Examples:
                        ghcr.io/hondarer/oracle-linux-container/oracle-linux-8-dev:latest
                        hondarer/oracle-linux-10-dev:latest
                        registry.example.com/team/oracle-linux-8-dev:v1.2.3
  --output <path>     Output path for the WSL rootfs tar.gz.
                      Default: ./wsl-rootfs.tar.gz
  --skip-pull         Skip `podman pull` and use the local image as-is.
  --help              Show this help.
EOF
}

cleanup() {
    if [ -n "${TEMP_CONTAINER_ID}" ]; then
        podman rm "${TEMP_CONTAINER_ID}" >/dev/null 2>&1 || true
    fi

    if [ "${TEMP_IMAGE_BUILT}" -eq 1 ]; then
        podman rmi "${TEMP_IMAGE_TAG}" >/dev/null 2>&1 || true
    fi
}

require_command() {
    local command_name="$1"

    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Error: required command not found: ${command_name}" >&2
        exit 1
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --image-ref)
            if [ "$#" -lt 2 ]; then
                echo "Error: --image-ref requires a value." >&2
                usage
                exit 1
            fi
            IMAGE_REF="$2"
            shift 2
            ;;
        --output)
            if [ "$#" -lt 2 ]; then
                echo "Error: --output requires a value." >&2
                usage
                exit 1
            fi
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --skip-pull)
            SKIP_PULL=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [ -z "${IMAGE_REF}" ]; then
    echo "Error: --image-ref is required." >&2
    usage
    exit 1
fi

require_command podman
require_command gzip

if [ ! -f "${CONTAINERFILE_WSL}" ]; then
    echo "Error: not found: ${CONTAINERFILE_WSL}" >&2
    exit 1
fi

if [ ! -f "${PREPARE_WSL_SCRIPT}" ]; then
    echo "Error: not found: ${PREPARE_WSL_SCRIPT}" >&2
    exit 1
fi

OUTPUT_DIR="$(dirname "${OUTPUT_PATH}")"
mkdir -p "${OUTPUT_DIR}"

trap cleanup EXIT

echo "==> Source image: ${IMAGE_REF}"
echo "==> Output path : ${OUTPUT_PATH}"

if [ "${SKIP_PULL}" -eq 0 ]; then
    echo "==> Pulling source image..."
    podman pull "${IMAGE_REF}"
else
    echo "==> Skipping pull and using local image..."
fi

echo "==> Building WSL derivative image..."
podman build \
    --build-arg "BASE_IMAGE=${IMAGE_REF}" \
    -f "${CONTAINERFILE_WSL}" \
    -t "${TEMP_IMAGE_TAG}" \
    "${SRC_DIR}"
TEMP_IMAGE_BUILT=1

echo "==> Creating temporary container..."
TEMP_CONTAINER_ID="$(podman create "${TEMP_IMAGE_TAG}")"

echo "==> Exporting WSL rootfs..."
podman export "${TEMP_CONTAINER_ID}" | gzip -c > "${OUTPUT_PATH}"

echo "==> WSL rootfs exported successfully"
ls -lh "${OUTPUT_PATH}"
echo
echo "Next step on Windows:"
echo "  Copy the tar.gz to Windows, then run:"
echo "  .\\import-wsl.ps1 -RootFsPath \"D:\\staging\\$(basename "${OUTPUT_PATH}")\" -WslDistroName \"OracleLinux8-Dev\""
