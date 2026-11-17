#!/bin/bash
# Dockerfile から実行する、OL8/9/10 共通の Go インストーラー。
# 公式バイナリを /usr/local/go に展開し、配布アーカイブ上限に備えてテスト類を除去する。
set -euo pipefail

GO_VERSION=1.27.4
GO_SHA256=7226736c2339719cda28fbf3a54d71aa63bcefe376e98cef00034268dab24840
GO_ARCHIVE="go${GO_VERSION}.linux-amd64.tar.gz"
GOROOT_DIR=/usr/local/go
GO_WORK_DIR="$(mktemp -d /tmp/go-install.XXXXXX)"
trap 'rm -rf "${GO_WORK_DIR}"' EXIT

if [ -f "/tmp/packages/${GO_ARCHIVE}" ]; then
    echo "=== using cached package: Go ${GO_VERSION} (/tmp/packages/${GO_ARCHIVE}) ==="
    cp "/tmp/packages/${GO_ARCHIVE}" "${GO_WORK_DIR}/${GO_ARCHIVE}"
else
    curl --fail --location --show-error --retry 3 --retry-delay 5 \
        --connect-timeout 30 --max-time 900 \
        -o "${GO_WORK_DIR}/${GO_ARCHIVE}" \
        "https://go.dev/dl/${GO_ARCHIVE}"
fi
printf '%s  %s\n' "${GO_SHA256}" "${GO_WORK_DIR}/${GO_ARCHIVE}" | sha256sum -c -

rm -rf "${GOROOT_DIR}"
tar -xzf "${GO_WORK_DIR}/${GO_ARCHIVE}" -C /usr/local --no-same-owner

# 標準ライブラリ・ツール自身のテストは利用者のビルドに不要。
# 除去により gzip 後で約 12 MiB 削減する (go test std は実行できなくなる)。
find "${GOROOT_DIR}" -type f -name '*_test.go' -delete
find "${GOROOT_DIR}" -depth -type d -name testdata -exec rm -rf {} +
rm -rf "${GOROOT_DIR}/test"

# go.mod の go / toolchain 行による別ツールチェーンの自動ダウンロードを止める。
# $GOROOT/go.env は環境変数と go env -w より優先度が低いため、利用者は上書きできる。
grep -qx 'GOTOOLCHAIN=auto' "${GOROOT_DIR}/go.env"
sed -i 's/^GOTOOLCHAIN=auto$/GOTOOLCHAIN=local/' "${GOROOT_DIR}/go.env"
grep -qx 'GOTOOLCHAIN=local' "${GOROOT_DIR}/go.env"

# /usr/local/bin は通常の PATH と sudo の secure_path の両方に含まれる。
ln -sfn "${GOROOT_DIR}/bin/go" /usr/local/bin/go
ln -sfn "${GOROOT_DIR}/bin/gofmt" /usr/local/bin/gofmt

# go install で導入したコマンド (既定 ~/go/bin) をログインシェルの PATH に追加する。
cat > /etc/profile.d/golang.sh <<'EOF'
case ":${PATH}:" in
    *":${HOME}/go/bin:"*) ;;
    *) export PATH="${PATH}:${HOME}/go/bin" ;;
esac
EOF
chmod 0644 /etc/profile.d/golang.sh

test "$(/usr/local/bin/go version)" = "go version go${GO_VERSION} linux/amd64"
test "$(/usr/local/bin/go env GOROOT)" = "${GOROOT_DIR}"
test "$(/usr/local/bin/go env GOTOOLCHAIN)" = local
