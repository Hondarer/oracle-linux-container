#!/bin/bash
#
# Dev Container 用エントリーポイントスクリプト
# VS Code の Dev Container として使用する際に、ユーザー環境をセットアップします。
# このスクリプトは root 権限で実行されることを想定しています。
#

# root 権限の確認
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# 環境変数からユーザー情報を取得します。
HOST_USER=${HOST_USER:-vscode}
HOST_UID=${HOST_UID:-1000}
HOST_GID=${HOST_GID:-1000}

echo "Setting up Dev Container for user: ${HOST_USER} (UID: ${HOST_UID}, GID: ${HOST_GID})"

# グループが存在しない場合は新規作成します。
if ! getent group "${HOST_GID}" >/dev/null 2>&1; then
    groupadd -g "${HOST_GID}" "${HOST_USER}"
    echo "Created group: ${HOST_USER} (GID: ${HOST_GID})"
else
    EXISTING_GROUP=$(getent group "${HOST_GID}" | cut -d: -f1)
    echo "Group GID ${HOST_GID} already exists as: ${EXISTING_GROUP}"
    # 既存グループ名が HOST_USER と一致しない場合はグループ名を変更します。
    if [ "${EXISTING_GROUP}" != "${HOST_USER}" ]; then
        groupmod -n "${HOST_USER}" "${EXISTING_GROUP}"
        echo "Renamed group ${EXISTING_GROUP} to ${HOST_USER}"
    fi
fi

# ユーザーが存在しない場合は新規作成します。
if ! getent passwd "${HOST_UID}" >/dev/null 2>&1; then
    useradd -u "${HOST_UID}" -g "${HOST_GID}" -G wheel -d "/home/${HOST_USER}" -m -s /bin/bash "${HOST_USER}"
    echo "Created user: ${HOST_USER} (UID: ${HOST_UID})"
else
    EXISTING_USER=$(getent passwd "${HOST_UID}" | cut -d: -f1)
    echo "User UID ${HOST_UID} already exists as: ${EXISTING_USER}"
    # 既存ユーザー名が HOST_USER と一致しない場合はユーザー名を変更します。
    if [ "${EXISTING_USER}" != "${HOST_USER}" ]; then
        usermod -l "${HOST_USER}" "${EXISTING_USER}"
        usermod -d "/home/${HOST_USER}" -m "${HOST_USER}"
        echo "Renamed user ${EXISTING_USER} to ${HOST_USER}"
    fi

    # ホームディレクトリのパスが異なる場合は更新します。
    CURRENT_HOME=$(getent passwd "${HOST_USER}" | cut -d: -f6)
    if [ "${CURRENT_HOME}" != "/home/${HOST_USER}" ]; then
        usermod -d "/home/${HOST_USER}" -m "${HOST_USER}" 2>/dev/null || usermod -d "/home/${HOST_USER}" "${HOST_USER}"
        echo "Updated home directory from ${CURRENT_HOME} to /home/${HOST_USER}"
    fi

    # ログインシェルが /bin/bash でない場合は更新します (/bin/false などのサービスアカウントを想定)。
    CURRENT_SHELL=$(getent passwd "${HOST_USER}" | cut -d: -f7)
    if [ "${CURRENT_SHELL}" != "/bin/bash" ]; then
        usermod -s /bin/bash "${HOST_USER}"
        echo "Updated shell from ${CURRENT_SHELL} to /bin/bash"
    fi

    # wheel グループへの所属確認および追加を行います。
    if ! id -nG "${HOST_USER}" | grep -qw wheel; then
        usermod -aG wheel "${HOST_USER}"
        echo "Added ${HOST_USER} to wheel group"
    fi
fi

# パスワードの設定
echo "${HOST_USER}:${HOST_USER}_passwd" | chpasswd
echo "Set password for ${HOST_USER}: ${HOST_USER}_passwd"

# ホームディレクトリの所有権を確認し、必要に応じて修正します。
if [ -d "/home/${HOST_USER}" ]; then
    current_uid=$(stat -c "%u" "/home/${HOST_USER}")
    current_gid=$(stat -c "%g" "/home/${HOST_USER}")
    if [ "$current_uid" -ne "$HOST_UID" ] || [ "$current_gid" -ne "$HOST_GID" ]; then
        chown "${HOST_UID}:${HOST_GID}" "/home/${HOST_USER}"
    fi
fi

# ワークスペースディレクトリの所有権を確認し、必要に応じて修正します。
if [ -d "/workspace" ]; then
    current_uid=$(stat -c "%u" "/workspace")
    current_gid=$(stat -c "%g" "/workspace")
    if [ "$current_uid" -ne "$HOST_UID" ] || [ "$current_gid" -ne "$HOST_GID" ]; then
        chown "${HOST_UID}:${HOST_GID}" "/workspace"
    fi
fi

# ホームディレクトリが空 (~/.ssh ディレクトリを除く) の場合に初期設定ファイルを配置します。
if [ -z "$(find /home/${HOST_USER} -mindepth 1 -not -path "/home/${HOST_USER}/.ssh/*" -not -name ".ssh" -print -quit 2>/dev/null)" ]; then
    echo "Initializing home for ${HOST_USER}..."

    cd /tmp
    rm -rf temp_home
    mkdir temp_home
    cd temp_home
    cp -a /etc/skel/. .

    echo export LANG=ja_JP.UTF-8 >> .bashrc

    echo 'export PATH="$HOME/.node_modules/bin:$PATH"' >> .bashrc
    echo "prefix=/home/${HOST_USER}/.node_modules" >> .npmrc
    mkdir -p .node_modules/bin

    cd /tmp
    chown -R "${HOST_UID}:${HOST_GID}" temp_home
    chmod 700 temp_home

    mkdir -p /home/${HOST_USER}
    chown "${HOST_UID}:${HOST_GID}" /home/${HOST_USER}
    cp -rp /tmp/temp_home/. /home/${HOST_USER}/.
    rm -rf /tmp/temp_home
fi

# ホストの SSH 鍵のコピー (任意)
if [ -d /tmp/host-ssh ] && [ -n "$(ls -A /tmp/host-ssh 2>/dev/null)" ]; then
    echo "Copying SSH keys from host..."
    mkdir -p /home/${HOST_USER}/.ssh
    cp -r /tmp/host-ssh/* /home/${HOST_USER}/.ssh/
    chown -R "${HOST_UID}:${HOST_GID}" /home/${HOST_USER}/.ssh
    chmod 700 /home/${HOST_USER}/.ssh
    chmod 600 /home/${HOST_USER}/.ssh/* 2>/dev/null || true
fi

echo "Dev Container setup completed successfully!"
echo "User: ${HOST_USER}"
echo "Home: /home/${HOST_USER}"
echo "Workspace: /workspace"
