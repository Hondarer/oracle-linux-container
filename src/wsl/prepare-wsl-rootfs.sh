#!/bin/sh
set -eu

# WSL2 用 rootfs カスタマイズスクリプト
# Containerfile.wsl のビルド時に root 権限で実行されます。
# Podman 運用時の entrypoint.sh に相当する初期設定を静的に行います。

# ディレクトリおよびユーザーの設定
# 既定では root ユーザーで実行されるため、通常利用する非 root ユーザーを作成します。
# wheel グループの sudoers 設定はベースイメージ (Dockerfile) で実施済みです。
useradd -m -s /bin/bash -G wheel user

# rootless Podman の UID/GID マッピング
touch /etc/subuid /etc/subgid
if ! grep -q '^user:' /etc/subuid; then
    echo 'user:100000:65536' >> /etc/subuid
fi
if ! grep -q '^user:' /etc/subgid; then
    echo 'user:100000:65536' >> /etc/subgid
fi

# rootless Podman のユーザー設定と API ソケット
mkdir -p /home/user/.config/containers \
         /home/user/.config/systemd/user/sockets.target.wants
cp /usr/share/containers/containers.conf /home/user/.config/containers/containers.conf
sed -i 's/^#cgroup_manager = "systemd"/cgroup_manager = "cgroupfs"/' \
    /home/user/.config/containers/containers.conf
cp /usr/lib/systemd/user/podman.socket \
   /usr/lib/systemd/user/podman.service \
   /home/user/.config/systemd/user/
ln -s ../podman.socket \
    /home/user/.config/systemd/user/sockets.target.wants/podman.socket

# WSL 起動時の既定ユーザーを設定し、systemd を有効化します。
echo "[user]"        > /etc/wsl.conf
echo "default=user" >> /etc/wsl.conf
echo "[boot]"       >> /etc/wsl.conf
echo "systemd=true" >> /etc/wsl.conf

# ロケールの設定
echo 'export LANG=ja_JP.UTF-8' >> /home/user/.bashrc

# Node.js のグローバルインストール先 (npm install -g) をユーザー単位に設定します。
echo 'export PATH="$HOME/.node_modules/bin:$PATH"' >> /home/user/.bashrc
echo 'prefix=/home/user/.node_modules'             >> /home/user/.npmrc
mkdir -p /home/user/.node_modules/bin

# ホームディレクトリの所有権と権限の調整
chown -R user:user /home/user
chmod 700 /home/user

# リリース情報ファイルをコンテナ用から WSL 用に変更します。
mv /etc/container-release /etc/wsl-release

# WSL では不要なコンテナ用エントリーポイントを削除します。
rm -f /usr/local/bin/entrypoint.sh
rm -f /usr/local/bin/devcontainer-entrypoint.sh

# ビルド中に再生成されたパッケージ管理キャッシュおよびログを削除します。
dnf clean all
rm -f /var/log/dnf* /var/log/hawkey.log
rm -rf /var/cache/dnf /root/.cache/pip /root/.npm
rm -rf /tmp/* /var/tmp/*
