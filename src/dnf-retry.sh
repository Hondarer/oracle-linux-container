#!/bin/bash
# dnf を一時的な失敗に対してリトライする。Dockerfile から bind mount で実行する。
#
# ミラーの同期途中に古い repomd.xml を受け取ると、参照先のメタデータが全ミラーで 404 になり
# dnf が失敗する (例: RPM Fusion EL8 updates)。失敗時はメタデータのキャッシュを破棄し、
# 間隔を空けて repomd.xml の取得からやり直す。
#
# 使い方: dnf-retry.sh <dnf の引数...>
# 環境変数: DNF_RETRY_MAX_ATTEMPTS (既定値: 4)、DNF_RETRY_INTERVAL_SEC (既定値: 30、試行ごとに倍数で増加)
set -u

max_attempts="${DNF_RETRY_MAX_ATTEMPTS:-4}"
interval_sec="${DNF_RETRY_INTERVAL_SEC:-30}"
attempt=1

while :; do
    dnf "$@" && exit 0
    status=$?
    if [ "${attempt}" -ge "${max_attempts}" ]; then
        echo "ERROR: dnf $* failed after ${attempt} attempts (exit ${status})" >&2
        exit "${status}"
    fi
    sleep_sec=$((attempt * interval_sec))
    echo "Warning: dnf $* failed (exit ${status}, attempt ${attempt}/${max_attempts}); clearing metadata and retrying in ${sleep_sec}s..." >&2
    dnf clean metadata >/dev/null 2>&1 || true
    sleep "${sleep_sec}"
    attempt=$((attempt + 1))
done
