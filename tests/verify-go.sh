#!/bin/bash
# 一時コンテナ内で root として実行する Go の統合テスト。外部ネットワークに依存しない。
set -euo pipefail
GO_VERSION=1.27.4
test "$(go version)" = "go version go${GO_VERSION} linux/amd64"
test "$(command -v go)" = /usr/local/bin/go
test "$(command -v gofmt)" = /usr/local/bin/gofmt
test "$(go env GOROOT)" = /usr/local/go
grep -qx 'GOTOOLCHAIN=local' /usr/local/go/go.env
test "$(go env GOTOOLCHAIN)" = local
# 利用者は環境変数で既定値を上書きできる。
test "$(GOTOOLCHAIN=auto go env GOTOOLCHAIN)" = auto

# テスト類の除去を確認する。
test ! -e /usr/local/go/test
test -z "$(find /usr/local/go -name '*_test.go' -print -quit)"
test -z "$(find /usr/local/go -type d -name testdata -print -quit)"

GO_TEST_DIR="$(mktemp -d /tmp/go-test.XXXXXX)"
trap 'rm -rf "${GO_TEST_DIR}"' EXIT
export GOCACHE="${GO_TEST_DIR}/cache" GOPATH="${GO_TEST_DIR}/gopath"
export GOPROXY=off GOFLAGS=-mod=mod

# 除去したファイルを go:embed などで参照するパッケージがないことを確認する。
LOAD_ERRORS="$(go list -e -deps -f '{{if .Error}}{{.ImportPath}}: {{.Error}}{{end}}' std cmd)"
test -z "${LOAD_ERRORS}" || { echo "${LOAD_ERRORS}" >&2; exit 1; }

mkdir -p "${GO_TEST_DIR}/hello"
cd "${GO_TEST_DIR}/hello"
go mod init example.invalid/hello
cat > main.go <<'EOF'
package main

import (
	"fmt"
	"os/user"
)

func Greeting() string { return "hello" }

func main() {
	u, err := user.Current()
	if err != nil {
		panic(err)
	}
	fmt.Println(Greeting(), u.Uid)
}
EOF
cat > main_test.go <<'EOF'
package main

import "testing"

func TestGreeting(t *testing.T) {
	done := make(chan string)
	go func() { done <- Greeting() }()
	if got := <-done; got != "hello" {
		t.Fatalf("Greeting() = %q", got)
	}
}
EOF
test -z "$(gofmt -l .)"
go vet ./...
# cgo (os/user) と静的ビルドの両方を確認する。
CGO_ENABLED=1 go build -o hello-cgo .
test "$(./hello-cgo)" = "hello $(id -u)"
CGO_ENABLED=0 go build -o hello-static .
test "$(./hello-static)" = "hello $(id -u)"
go test ./...
go test -race ./...

# 新しい Go を要求する go.mod でも、ツールチェーンを自動取得せずに失敗する。
mkdir -p "${GO_TEST_DIR}/future"
cd "${GO_TEST_DIR}/future"
printf '%s\n' 'module example.invalid/future' '' 'go 1.99' > go.mod
printf '%s\n' 'package main' '' 'func main() {}' > main.go
if go build ./... > "${GO_TEST_DIR}/future.log" 2>&1; then
    echo 'go.mod requiring Go 1.99 unexpectedly built' >&2
    exit 1
fi
grep -F 'GOTOOLCHAIN=local' "${GO_TEST_DIR}/future.log"
test ! -e "${GOPATH}/pkg/mod/golang.org/toolchain"

# 一般ユーザーのログインシェルで go と ~/go/bin を確認する。
GO_TEST_USER="goprobe$$"
useradd -m "${GO_TEST_USER}"
cp -r "${GO_TEST_DIR}/hello" "/home/${GO_TEST_USER}/hello"
rm -f "/home/${GO_TEST_USER}/hello/hello-cgo" "/home/${GO_TEST_USER}/hello/hello-static"
chown -R "${GO_TEST_USER}:" "/home/${GO_TEST_USER}/hello"
su - "${GO_TEST_USER}" -s /bin/bash -c '
    set -eu
    test "$(command -v go)" = /usr/local/bin/go
    test "$(go env GOTOOLCHAIN)" = local
    case ":${PATH}:" in *":${HOME}/go/bin:"*) ;; *) exit 1 ;; esac
    cd ~/hello
    GOPROXY=off go install .
    test "$(command -v hello)" = "${HOME}/go/bin/hello"
    test "$(hello)" = "hello $(id -u)"
'
userdel -r "${GO_TEST_USER}"
echo "Go ${GO_VERSION} integration checks passed"
