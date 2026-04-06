# Oracle Linux コンテナ マルチバージョン対応

## 概要

リポジトリ `oracle-linux-container` は Oracle Linux 8 と 10 の両方に対応しており、将来のバージョン追加も容易な構造となっている。マルチインスタンス対応と組み合わせ、`./storage/{version}/{instance}/` の階層構造でデータを管理する。

## 設計方針

| 項目 | 内容 |
|------|------|
| Dockerfile | 単一ファイル + `ARG OL_VERSION` で分岐 |
| シェルスクリプト | 第1引数でバージョン指定、共通設定を `version-config.sh` に集約 |
| ストレージ | `./storage/{version}/{instance}/` 例: `./storage/8/1/`, `./storage/10/1/` |
| ポート | 計算式: `40000 + (OL_VERSION * 100) + (21 + INSTANCE_NUM)` |
| ツールバージョン | 各ディストリビューションの標準に合わせる |
| コンテナ名 | `oracle-linux-{ver}_{instance}` 例: `oracle-linux-8_1` |

## ポート番号体系

```
OL8  インスタンス1: 40822  インスタンス2: 40823  インスタンス3: 40824 ...
OL10 インスタンス1: 41022  インスタンス2: 41023  インスタンス3: 41024 ...
```

計算式: `40000 + (OL_VERSION * 100) + (21 + INSTANCE_NUM)`

複数インスタンス (1〜9) の同時起動が可能であり、バージョン間のポート衝突も発生しない。

## 実装詳細

### `version-config.sh` — 共通設定ファイル

全スクリプトから `source` される共通設定ファイル。バージョンとインスタンス番号に基づいて以下の変数を設定する。

```
引数: $1 = OL_VERSION (デフォルト: 8), $2 = INSTANCE_NUM (デフォルト: 1)

設定される変数:
- OL_VERSION         バージョン番号 (8 or 10)
- INSTANCE_NUM       インスタンス番号
- CONTAINER_NAME     ベースイメージ名 (例: oracle-linux-8)
- CONTAINER_INSTANCE コンテナインスタンス名 (例: oracle-linux-8_1)
- SSH_HOST_PORT      SSH ポート番号 (計算式に基づく)
- STORAGE_DIR        ストレージパス (例: ./storage/8/1)
- BASE_IMAGE         OCI ベースイメージ (例: oraclelinux:8)
```

冪等性を考慮し、変数 (`CONTAINER_INSTANCE`) が設定済みの場合は再設定をスキップする。バージョンは 8 と 10 のみ受け付け、それ以外はエラーとなる。

### `src/Dockerfile` — マルチバージョン対応

単一の Dockerfile で `ARG OL_VERSION` による条件分岐を行い、OL8/OL10 の両方をサポートする。

**ベースイメージ**:

```dockerfile
ARG OL_VERSION=8
FROM oraclelinux:${OL_VERSION}
ARG OL_VERSION
```

**主な条件分岐**:

| 項目 | OL8 | OL10 |
|------|-----|------|
| EPEL | `oracle-epel-release-el8` | `oracle-epel-release-el10` |
| リポジトリ | `ol8_codeready_builder`, `ol8_developer_EPEL` | `ol10_codeready_builder`, `ol10_developer_EPEL` |
| Node.js | `dnf module enable nodejs:24` + install | `dnf install nodejs` (AppStream) |
| Java | `java-17-openjdk*` | `java-21-openjdk*` |
| Python pip | `python3.11-pip` | `python3-pip` (3.12 が標準) |
| フォント | DejaVu + VLGothic | Google Noto Sans CJK |
| doxybook2 | `linux-el8-x64` ビルド | `linux-el10-x64` ビルド |
| llvm-compat-libs | あり | 不要 |
| libmodman, libsoup, rest | あり | 不要 |

条件分岐は RUN ブロック内の `if [ "${OL_VERSION}" = "8" ]; then ... else ... fi` で実装している。

**alternatives 設定**:

Java と Python の alternatives はバージョンに応じたパターンで設定し、`java`、`javac`、`python3`、`pip3` コマンドが適切なバージョンを指すようにしている。

**doxybook2**:

GitHub リポジトリ (`Hondarer/doxybook2-bin`) から `linux-el${OL_VERSION}-x64` のバイナリを取得してインストールする。

### シェルスクリプト — バージョン指定による操作

全スクリプトは先頭で `version-config.sh` を source し、第1引数でバージョンを指定する。

#### `build-pod.sh`

- `source ./version-config.sh "${1:-8}" "${2:-1}"`
- `podman build --build-arg OL_VERSION=${OL_VERSION} -t ${CONTAINER_NAME} ./src/`
- ビルド前に `stop-pod.sh` を source して既存コンテナを停止
- `src/container-release` にビルドメタデータ (ビルド日時、Git コミット等) を記録

#### `start-pod.sh`

- `source ./version-config.sh "${1:-8}" "${2:-1}"`
- ストレージディレクトリ (`${STORAGE_DIR}/home_${USER}`, `${STORAGE_DIR}/workspace`) を自動作成
- `~/.ssh/id_rsa.pub` が存在すれば、ストレージの authorized_keys にコピー
- `podman run` で以下を指定:
  - `--userns=keep-id` により UID/GID マッピングを維持
  - `--user root` で entrypoint.sh を root 実行
  - `-p ${SSH_HOST_PORT}:22` でバージョン別ポートを割り当て
  - 環境変数 `HOST_USER`、`HOST_UID`、`HOST_GID` でユーザー情報を渡す

**ストレージ移行ガイダンス**: 旧構造 (`./storage/1/`) が検出された場合、新構造 (`./storage/8/1/`) への移行メッセージを表示する。

#### `stop-pod.sh`

- `CONTAINER_INSTANCE` が未設定の場合のみ `version-config.sh` を source
- `podman stop` / `podman rm` で対象コンテナを停止・削除 (エラーは抑制)

#### `save-pod.sh` / `load-pod.sh`

- `source ./version-config.sh "${1:-8}"`
- `image/${CONTAINER_NAME}.tar.gz` としてイメージを保存・読み込み

### GitHub Actions ワークフロー — マトリックスビルド

`.github/workflows/build-and-publish.yml` にて、`strategy.matrix.ol_version: ["8", "10"]` により OL8 と OL10 を並列にビルド・テスト・公開する。

- **イメージ名**: `oracle-linux-{8|10}-dev`
- **ビルド引数**: `--build-arg OL_VERSION=${{ matrix.ol_version }}`
- **テスト項目**: Node.js、Java、Python、.NET、Doxygen、PlantUML、sshd
- **公開先**: `ghcr.io/hondarer/oracle-linux-container/oracle-linux-{8|10}-dev:TAG`
- **WSL rootfs**: OCI アーティファクトとして `oracle-linux-{8|10}-dev-wsl:TAG` も公開
- **プッシュ条件**: PR イベント以外の場合のみレジストリにプッシュ

### Dev Container 設定 — バージョン別構成

`examples/devcontainer/` に OL8 と OL10 の個別設定を配置している。

```
examples/devcontainer/
├── README.md
├── ol8/
│   └── devcontainer.json
└── ol10/
    └── devcontainer.json
```

両バージョン共通の設定:
- イメージ: `ghcr.io/hondarer/oracle-linux-container/oracle-linux-{8|10}-dev:latest`
- postCreateCommand: `devcontainer-entrypoint.sh` を root で実行し、動的にユーザーを作成
- SSH 鍵: ホストの `~/.ssh` を読み取り専用でマウント
- ワークスペース: `/workspace` にバインドマウント
- VS Code 拡張機能: C++、Node.js、Java、.NET、Python、ドキュメントツール

### WSL インポートスクリプト — バージョンパラメータ対応

`examples/import-wsl/import-wsl.ps1` は `-OLVersion` パラメータ (デフォルト: "8") でバージョンを指定する。

- **ディストリビューション名**: `OracleLinux{OLVersion}-Dev`
- **イメージ URL**: `ghcr.io/hondarer/oracle-linux-container/oracle-linux-{OLVersion}-dev:{Tag}`
- **処理フロー**: OCI Registry v2 認証 → マニフェスト取得 → rootfs ダウンロード → WSL インポート → 動作テスト
- **安全性**: 既存ディストリビューションがある場合、データ消失の警告を表示

## OL8 と OL10 のパッケージ差分

| パッケージ | OL8 | OL10 | 対応 |
|-----------|-----|------|------|
| EPEL | `oracle-epel-release-el8` | `oracle-epel-release-el10` | 条件分岐 |
| リポジトリ | `ol8_codeready_builder`, `ol8_developer_EPEL` | `ol10_codeready_builder`, `ol10_developer_EPEL` | 条件分岐 |
| Node.js | `dnf module enable nodejs:24` + install | `dnf install nodejs` (AppStream) | 条件分岐 |
| Java | `java-17-openjdk*` | `java-21-openjdk*` | 条件分岐 |
| Python pip | `python3.11-pip` | `python3-pip` | 条件分岐 |
| llvm-compat-libs | あり | 不要 | 条件分岐 |
| libmodman | あり | 不要 | 条件分岐 |
| libsoup | あり | 不要 | 条件分岐 |
| rest | あり | 不要 | 条件分岐 |
| フォント | DejaVu + VLGothic | Google Noto Sans CJK | 条件分岐 |
| doxybook2 | `linux-el8-x64` | `linux-el10-x64` | URL 分岐 |
| .NET SDK | `dotnet-sdk-10.0` | `dotnet-sdk-10.0` | 共通 |

## バージョン拡張

新しい Oracle Linux バージョン (例: OL11) を追加する場合:

1. `version-config.sh` のバージョンバリデーションに追加
2. `src/Dockerfile` にパッケージの条件分岐を追加
3. GitHub Actions のマトリックスにバージョンを追加
4. `examples/devcontainer/` にバージョン別設定を追加

シェルスクリプト (`build-pod.sh` 等) は `version-config.sh` 経由でバージョンを受け取るため、変更不要である。
