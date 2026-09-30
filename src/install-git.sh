#!/bin/bash
# Dockerfile から実行する、OL8/9/10 共通の Git インストーラー。
set -euo pipefail

OL_VERSION="${1:?Oracle Linux version is required}"
case "${OL_VERSION}" in
    8|9|10) ;;
    *) echo "Unsupported Oracle Linux version: ${OL_VERSION}" >&2; exit 1 ;;
esac

GIT_VERSION=2.56.0
GIT_SHA256=26c56c296b38c0695b26fa95f475f1d01704d2d38e73465ca30b0b2f5dc789d3
GIT_MAN_SHA256=1f62a7fabaa36a0469c4d51fe247d12e7e246b890d2b8b49aec91df610f417c7
GIT_BUILD_DIR="$(mktemp -d /tmp/git-build.XXXXXX)"
trap 'rm -rf "${GIT_BUILD_DIR}"' EXIT

download_archive() {
    local archive="$1" checksum="$2"
    if [ -f "/tmp/packages/${archive}" ]; then
        cp "/tmp/packages/${archive}" "${GIT_BUILD_DIR}/${archive}"
    else
        curl --fail --location --show-error --retry 3 --retry-delay 5 \
            --connect-timeout 30 --max-time 600 \
            -o "${GIT_BUILD_DIR}/${archive}" \
            "https://www.kernel.org/pub/software/scm/git/${archive}"
    fi
    printf '%s  %s\n' "${checksum}" "${GIT_BUILD_DIR}/${archive}" | sha256sum -c -
}

# OL10 の zlib-devel は zlib-ng-compat-devel により提供される。
# --enablerepo はこのコマンドだけに適用し、既定のリポジトリ設定を維持する。
dnf --enablerepo="ol${OL_VERSION}_codeready_builder" install -y \
    bash-completion expat-devel gettext-devel libcurl-devel openssl-devel \
    pcre2-devel zlib-devel
download_archive "git-${GIT_VERSION}.tar.xz" "${GIT_SHA256}"
download_archive "git-manpages-${GIT_VERSION}.tar.xz" "${GIT_MAN_SHA256}"
tar -xJf "${GIT_BUILD_DIR}/git-${GIT_VERSION}.tar.xz" -C "${GIT_BUILD_DIR}"
cd "${GIT_BUILD_DIR}/git-${GIT_VERSION}"

# 2.56 の Rust は任意。既存の GCC でビルドし、PCRE2 と gettext を有効にする。
# ビルドとインストールで同じ設定を使い、/etc/gitconfig の参照を維持する。
GIT_MAKE_ARGS=(prefix=/usr/local sysconfdir=/etc PYTHON_PATH=/usr/bin/python3
    NO_RUST=YesPlease NO_TCLTK=YesPlease USE_LIBPCRE2=YesPlease)
make -j"$(nproc)" "${GIT_MAKE_ARGS[@]}" all
make "${GIT_MAKE_ARGS[@]}" install

install -D -m 0644 contrib/completion/git-completion.bash \
    /usr/local/share/bash-completion/completions/git
install -D -m 0644 contrib/completion/git-prompt.sh \
    /usr/local/share/git-core/contrib/completion/git-prompt.sh
install -D -m 0644 COPYING /usr/local/share/doc/git/COPYING
install -d /usr/local/share/man
tar -xJf "${GIT_BUILD_DIR}/git-manpages-${GIT_VERSION}.tar.xz" \
    -C /usr/local/share/man --no-same-owner

# sudo も通常の PATH と同じ順序で /usr/local のツールを解決する。
printf '%s\n' \
    'Defaults secure_path = /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
    > /etc/sudoers.d/local-tools
chmod 0440 /etc/sudoers.d/local-tools
visudo -c -f /etc/sudoers.d/local-tools
test "$(/usr/local/bin/git --version)" = "git version ${GIT_VERSION}"
test -x /usr/local/libexec/git-core/git-remote-https

dnf clean all
rm -f /var/log/dnf* /var/log/hawkey.log
rm -rf /var/cache/dnf
