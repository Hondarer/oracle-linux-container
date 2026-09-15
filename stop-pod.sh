#!/bin/bash

# rootless podman-compose では UID のマッピングを正常に処理できない (userns が利用できない) ため、
# podman を直接実行します。

# 他のスクリプトから source される場合は設定済みのためスキップします。
if [ -z "${CONTAINER_INSTANCE}" ]; then
    source "$(dirname "$0")/version-config.sh" "${1:-8}" "${2:-1}"
fi

# 既存のコンテナを停止および削除します。
podman stop ${CONTAINER_INSTANCE} 1>/dev/null 2>/dev/null || true
podman rm ${CONTAINER_INSTANCE} 1>/dev/null 2>/dev/null || true

echo "Container ${CONTAINER_INSTANCE} stopped successfully."
