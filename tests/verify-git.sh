#!/bin/bash
# 一時コンテナ内で root として実行する Git の統合テスト。
set -euo pipefail
test "$(git --version)" = 'git version 2.56.0'
test "$(command -v git)" = /usr/local/bin/git
test "$(git --exec-path)" = /usr/local/libexec/git-core
test -x "$(git --exec-path)/git-remote-https"
test -x "$(git --exec-path)/git-http-push"
test "$(LC_ALL=C man -w git)" = /usr/local/share/man/man1/git.1
test "$(man -w git)" = /usr/local/share/man/man1/git.1
grep -F 'Git 2.56.0' /usr/local/share/man/man1/git.1
visudo -c
grep -Fx '%wheel ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/wheel
# PAM に依存せず、sudoers に設定した Git 優先の secure_path を検証する。
grep -Fx 'Defaults secure_path = /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
    /etc/sudoers.d/local-tools

GIT_TEST_DIR="$(mktemp -d /tmp/git-test.XXXXXX)"
GIT_HTTP_PID=
cleanup() {
    if [ -n "${GIT_HTTP_PID}" ]; then
        kill "${GIT_HTTP_PID}" 2>/dev/null || true
        wait "${GIT_HTTP_PID}" 2>/dev/null || true
    fi
    rm -rf "${GIT_TEST_DIR}"
}
trap cleanup EXIT
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
git init -b main "${GIT_TEST_DIR}/work"
git -C "${GIT_TEST_DIR}/work" config user.name 'Git verification'
git -C "${GIT_TEST_DIR}/work" config user.email git-verification@example.invalid
printf '%s\n' 'example 123' > "${GIT_TEST_DIR}/work/example.txt"
git -C "${GIT_TEST_DIR}/work" add example.txt
git -C "${GIT_TEST_DIR}/work" commit -m initial
# -P が機能することを確認し、RPM 版で利用できた PCRE2 対応を維持する。
git -C "${GIT_TEST_DIR}/work" grep -P '\d{3}'
git clone --bare "${GIT_TEST_DIR}/work" "${GIT_TEST_DIR}/remote.git"
git clone "${GIT_TEST_DIR}/remote.git" "${GIT_TEST_DIR}/clone"
git -C "${GIT_TEST_DIR}/clone" config user.name 'Git verification'
git -C "${GIT_TEST_DIR}/clone" config user.email git-verification@example.invalid
printf '%s\n' second >> "${GIT_TEST_DIR}/clone/example.txt"
git -C "${GIT_TEST_DIR}/clone" commit -am second
git -C "${GIT_TEST_DIR}/clone" push origin main
git -C "${GIT_TEST_DIR}/work" fetch "${GIT_TEST_DIR}/remote.git" main
test "$(git -C "${GIT_TEST_DIR}/work" log -1 --format=%s FETCH_HEAD)" = second
git -C "${GIT_TEST_DIR}/clone" fsck --full

# ネットワークを外部に依存させず、HTTP 用ヘルパーの実動作を確認する。
git -C "${GIT_TEST_DIR}/remote.git" update-server-info
python3 -m http.server 48156 --bind 127.0.0.1 --directory "${GIT_TEST_DIR}" \
    > "${GIT_TEST_DIR}/http.log" 2>&1 &
GIT_HTTP_PID=$!
curl --fail --silent --show-error --retry 5 --retry-connrefused --retry-delay 1 \
    --max-time 5 http://127.0.0.1:48156/remote.git/HEAD > /dev/null
git clone http://127.0.0.1:48156/remote.git "${GIT_TEST_DIR}/http-clone"
test "$(git -C "${GIT_TEST_DIR}/http-clone" log -1 --format=%s)" = second
git -C "${GIT_TEST_DIR}/http-clone" fsck --full

# 一般ユーザーの Git と Bash 補完も検証する。
GIT_TEST_USER="gitprobe$$"
useradd -m -G wheel "${GIT_TEST_USER}"
echo "${GIT_TEST_USER}:${GIT_TEST_USER}_passwd" | chpasswd
id -nG "${GIT_TEST_USER}" | grep -qw wheel
su - "${GIT_TEST_USER}" -s /bin/bash -c '
    set -eu
    test "$(command -v git)" = /usr/local/bin/git
    test "$(git --version)" = "git version 2.56.0"
    # bash-completion 2.7 (OL8) の初期化は通常の対話シェルと同じ設定で行う。
    set +eu
    source /usr/share/bash-completion/bash_completion
    set -eu
    _completion_loader git || test "$?" = 124
    complete -p git
    shopt -s extdebug
    test "$(declare -F __git_main | awk "{print \$3}")" = /usr/local/share/bash-completion/completions/git
'
unset GIT_CONFIG_NOSYSTEM
git config --file /etc/gitconfig verification.git256 true
test "$(git config --system --show-origin --get verification.git256)" = $'file:/etc/gitconfig\ttrue'
git config --file /etc/gitconfig --unset verification.git256
echo 'Git 2.56.0 integration checks passed'
