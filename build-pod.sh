#!/bin/bash

# rootless podman-compose では UID のマッピングを正常に処理できない (userns が利用できない) ため、
# podman を直接実行します。

source "$(dirname "$0")/version-config.sh" "${1:-8}" "${2:-1}"

# src/keys ディレクトリが存在しない場合は作成します。
if [ ! -d ./src/keys ]; then
    echo "Creating ./src/keys directory..."
    mkdir -p ./src/keys
fi

# src/packages ディレクトリが存在しない場合は作成します。
if [ ! -d ./src/packages ]; then
    echo "Creating ./src/packages directory..."
    mkdir -p ./src/packages
fi

# src/fonts ディレクトリが存在しない場合は作成します。
if [ ! -d ./src/fonts ]; then
    echo "Creating ./src/fonts directory..."
    mkdir -p ./src/fonts
fi

# container-release ファイルの生成
{
    echo "# Container Build Information"
    printf "%-18s = %s\n" "BUILD_TYPE" "local"
    printf "%-18s = %s\n" "BUILD_DATE" "$(date +%Y-%m-%dT%H:%M:%S%z)"
    printf "%-18s = %s\n" "BUILD_HOST" "$(uname -n 2>/dev/null || echo 'unknown')"

    # Git コミットハッシュおよび変更状態の取得
    GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo 'unknown')
    if [ "${GIT_COMMIT}" != "unknown" ]; then
        # 未コミットの変更が存在する場合は + を付与します。
        git diff-index --quiet HEAD 2>/dev/null || GIT_COMMIT="${GIT_COMMIT}+"
    fi
    printf "%-18s = %s\n" "GIT_COMMIT" "${GIT_COMMIT}"

    printf "%-18s = %s\n" "GIT_BRANCH" "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"

    # タグの取得
    GIT_TAG=$(git describe --exact-match --tags 2>/dev/null || echo '(none)')
    printf "%-18s = %s\n" "GIT_TAG" "${GIT_TAG}"

    # バージョンの抽出 (タグから v プレフィックスを除去)
    if [ "${GIT_TAG}" != "(none)" ]; then
        VERSION=${GIT_TAG#v}
    else
        VERSION="dev"
    fi
    printf "%-18s = %s\n" "VERSION" "${VERSION}"

    printf "%-18s = %s\n" "BUILDER" "${USER}"
} > ./src/container-release

# GitHub リポジトリ URL を git remote から取得し、リンク変換用に使用します。
GITHUB_REPOSITORY=$(git remote get-url origin 2>/dev/null \
    | sed 's|.*github\.com[:/]\(.*\)\.git$|\1|;s|.*github\.com[:/]\(.*\)$|\1|' || echo "")
BASE_BLOB="https://github.com/${GITHUB_REPOSITORY}/blob/main"
BASE_TREE="https://github.com/${GITHUB_REPOSITORY}/tree/main"

# README の相対リンクを GitHub の絶対 URL に変換し、src/ へ配置します。
sed \
    -e "s|](\./\([^)]*\)/)|](${BASE_TREE}/\1/)|g" \
    -e "s|](\./\([^)]*\))|](${BASE_BLOB}/\1)|g" \
    -e "s|](docs-src/\([^)]*\)/)|](${BASE_TREE}/docs-src/\1/)|g" \
    -e "s|](docs-src/)|](${BASE_TREE}/docs-src/)|g" \
    -e "s|](docs-src/\([^)]*\))|](${BASE_BLOB}/docs-src/\1)|g" \
    -e "s|](examples/\([^)]*\)/)|](${BASE_TREE}/examples/\1/)|g" \
    -e "s|](examples/\([^)]*\))|](${BASE_BLOB}/examples/\1)|g" \
    -e "s|](CLAUDE\.md)|](${BASE_BLOB}/CLAUDE.md)|g" \
    README.md > ./src/README.md

# LICENSE をビルドコンテキストへコピーします。
cp LICENSE ./src/LICENSE

echo "Building container image: ${CONTAINER_NAME} (OL${OL_VERSION})..."

# 既存のコンテナを停止します。
source ./stop-pod.sh

# 既存の古いイメージを削除します。
podman rmi ${CONTAINER_NAME} 1>/dev/null 2>/dev/null || true
echo "Clean old container successfully."

# イメージのビルドを実行します。
echo "Building image..."
podman build --build-arg OL_VERSION=${OL_VERSION} -t ${CONTAINER_NAME} ./src/

if [ $? -ne 0 ]; then
    echo "Error: Failed to build container."
    exit 1
fi

# 登録されたイメージの表示
podman images ${CONTAINER_NAME}

echo "Container built successfully."
