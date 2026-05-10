# WSL rootfs エクスポート手順

`podman` が使える Linux 環境で、公開済みの Oracle Linux 開発用コンテナイメージを `pull` し、`wsl --import` で使える WSL 用 rootfs (`tar.gz`) を生成する手順です。

通常の利用では、まず GitHub Releases に添付された WSL 用 rootfs (`tar.gz`) を使うことを推奨します。このドキュメントは、独自に rootfs を再生成したい場合や、任意のコンテナレジストリ上のイメージから WSL 用 rootfs を作りたい場合の補助手順です。

ここでは WSL へインポートするための `tar.gz` を作成します。release asset を使った標準的なインポート手順は、[examples/import-wsl/README.md](../import-wsl/README.md) に従ってください。

## WSL 向け調整について

通常の開発用イメージをそのまま `podman export` するのではなく、いったん `src/Containerfile.wsl` で WSL 向け派生イメージを作ってから rootfs を出力します。

この派生イメージでは `src/wsl/prepare-wsl-rootfs.sh` により、少なくとも以下の WSL 向け調整が入ります。

- `/etc/wsl.conf` の作成
- 既定ユーザー `user` の前提設定
- `systemd=true` の有効化
- コンテナ前提の不要ファイル除去

そのため、WSL 用 rootfs を作る標準手順は「通常イメージを pull して直接 export」ではなく、「WSL 向け派生イメージを build して export」となります。

## 前提条件

- Linux 環境で `podman` と `gzip` が使えること
- このリポジトリをローカルに checkout 済みであること
- private registry を使う場合は、事前に `podman login` 済みであること

## クイックスタート

### GHCR の公式イメージから独自に rootfs を生成する

```bash
cd examples/export-wsl

# OL8
./export-wsl.sh \
  --image-ref ghcr.io/hondarer/oracle-linux-container/oracle-linux-8-dev:latest \
  --output ./OracleLinux8-Dev.tar.gz

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

`--image-ref` には、`registry/repository:tag` の完全なイメージ参照を指定してください。社内レジストリやユーザー管理のレジストリも同じ手順で扱えます。

## 生成物

生成されるファイルは、WSL に `wsl --import` できる rootfs の `tar.gz` です。

```bash
ls -lh ./OracleLinux8-Dev.tar.gz
tar -tzf ./OracleLinux8-Dev.tar.gz | head
```

この `tar.gz` を Windows に持ち込み、標準のインポート手順と同様に `RootFsPath` として指定します。

```powershell
powershell -ExecutionPolicy Bypass -File .\import-wsl.ps1 -RootFsPath "D:\staging\OracleLinux8-Dev.tar.gz" -WslDistroName "OracleLinux8-Dev"
```

## ヘルパーシェル

`export-wsl.sh` は以下の流れをまとめて実行します。

1. 指定イメージを `podman pull`
2. `src/Containerfile.wsl` で WSL 向け派生イメージを build
3. `podman create`
4. `podman export | gzip` で WSL rootfs を出力
5. 一時コンテナと一時イメージを cleanup

### 使い方

```bash
cd examples/export-wsl
./export-wsl.sh --image-ref <image-ref> [--output <path>] [--skip-pull]
```

### オプション

- `--image-ref <ref>`: 元になるコンテナイメージ参照。必須です
- `--output <path>`: 出力先。省略時は `./wsl-rootfs.tar.gz`
- `--skip-pull`: 既にローカルにあるイメージを使う場合、`podman pull` を省略します
- `--help`: ヘルプを表示します

## 注意事項

- rootless `podman` 前提の手順です
- `podman pull` に失敗する場合は、レジストリ URL、タグ、認証状態を確認してください
- 生成される `tar.gz` は `podman load` 用アーカイブではありません。用途は `wsl --import` 向け rootfs です
- 標準利用では GitHub Releases の配布物を使い、この手順は独自生成が必要な場合のみ使用してください
- 出力した rootfs をインポートする Windows 側の詳細は、[examples/import-wsl/README.md](../import-wsl/README.md) を参照してください
