# WSL rootfs エクスポート手順

`podman` が利用可能な Linux 環境において、公開済みの Oracle Linux 開発用コンテナイメージを `pull` し、`wsl --import` で利用可能な WSL 用 rootfs (`tar.gz`) を生成する手順です。

通常の利用では、GitHub Releases に添付された WSL 用 rootfs (`tar.gz`) の使用を推奨します。
本文書は、独自に rootfs を再生成したい場合や、任意のコンテナレジストリ上のイメージから WSL 用 rootfs を作成したい場合の補助手順について説明します。

ここでは WSL へインポートするための `tar.gz` を作成します。
release asset を使用した標準的なインポート手順は、[examples/import-wsl/README.md](../import-wsl/README.md) を参照してください。

## WSL 向けの事前設定

通常の開発用イメージを直接 `podman export` するのではなく、`src/Containerfile.wsl` により WSL 向け派生イメージをビルドしてから rootfs を出力します。

この派生イメージでは `src/wsl/prepare-wsl-rootfs.sh` により、次の WSL 向け設定が適用されます。

- `/etc/wsl.conf` の作成
- 既定ユーザー `user` の初期設定
- `systemd=true` の有効化
- rootless Podman、Docker 互換コマンド、Compose のユーザー設定
- コンテナ前提の不要ファイルの削除

したがって、WSL 用 rootfs を作成する手順は、通常イメージを直接 export する構成ではなく、WSL 向け派生イメージをビルドして export する構成となります。

## 前提条件

- Linux 環境で `podman` と `gzip` が利用可能であること
- 本リポジトリをローカルにチェックアウト済みであること
- プライベートレジストリを使用する場合は、事前に `podman login` を完了していること

## クイックスタート

### GHCR の公式イメージから独自に rootfs を生成する

```bash
cd examples/export-wsl

# OL8
./export-wsl.sh \
  --image-ref ghcr.io/hondarer/oracle-linux-container/oracle-linux-8-dev:latest \
  --output ./OracleLinux8-Dev.tar.gz

# OL9
./export-wsl.sh \
  --image-ref ghcr.io/hondarer/oracle-linux-container/oracle-linux-9-dev:latest \
  --output ./OracleLinux9-Dev.tar.gz

# OL10
./export-wsl.sh \
  --image-ref ghcr.io/hondarer/oracle-linux-container/oracle-linux-10-dev:latest \
  --output ./OracleLinux10-Dev.tar.gz
```

### Docker Hub の公式イメージから独自に rootfs を生成する

```bash
cd examples/export-wsl

./export-wsl.sh \
  --image-ref hondarer/oracle-linux-8-dev:latest \
  --output ./OracleLinux8-Dev.tar.gz
```

### 任意のコンテナレジストリから独自に rootfs を生成する

```bash
cd examples/export-wsl

./export-wsl.sh \
  --image-ref registry.example.com/team/oracle-linux-8-dev:v1.2.3 \
  --output ./OracleLinux8-Dev.tar.gz
```

`--image-ref` には、`registry/repository:tag` の完全なイメージ参照を指定してください。
社内レジストリや独自管理のレジストリも同一の手順で利用できます。

## 生成物

生成されるファイルは、`wsl --import` でインポート可能な rootfs の `tar.gz` 形式アーカイブです。

```bash
ls -lh ./OracleLinux8-Dev.tar.gz
tar -tzf ./OracleLinux8-Dev.tar.gz | head
```

この `tar.gz` を Windows 環境へ配置し、標準のインポート手順と同様に `RootFsPath` として指定します。

```powershell
powershell -ExecutionPolicy Bypass -File .\import-wsl.ps1 -RootFsPath "D:\staging\OracleLinux8-Dev.tar.gz" -WslDistroName "OracleLinux8-Dev"
```

## ヘルパースクリプト

`export-wsl.sh` は、次の一連の処理を一括実行します。

1. 指定イメージの `podman pull`
2. `src/Containerfile.wsl` による WSL 向け派生イメージのビルド
3. `podman create` による一時コンテナの作成
4. `podman export | gzip` による WSL rootfs の出力
5. 一時コンテナおよび一時イメージの削除

### 使い方

```bash
cd examples/export-wsl
./export-wsl.sh --image-ref <image-ref> [--output <path>] [--skip-pull]
```

### オプション

- `--image-ref <ref>`: 元となるコンテナイメージの参照 (必須)
- `--output <path>`: 出力先パス (省略時の既定値: `./wsl-rootfs.tar.gz`)
- `--skip-pull`: ローカルに存在するイメージを使用し、`podman pull` を省略するフラグ
- `--help`: ヘルプを表示

## 注意事項

- rootless `podman` の実行を前提とします。
- `podman pull` に失敗する場合は、レジストリ URL、タグ、認証状態を確認してください。
- 生成される `tar.gz` は `podman load` 用アーカイブではありません。用途は `wsl --import` 向け rootfs です。
- 通常の利用では GitHub Releases の配布物を使用し、本文書の手順は独自生成が必要な場合のみ使用してください。
- 出力した rootfs をインポートする Windows 側の詳細は、[examples/import-wsl/README.md](../import-wsl/README.md) を参照してください。
