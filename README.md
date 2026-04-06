# Oracle Linux 開発用コンテナ

Oracle Linux ベースのポータブルな開発用コンテナシステムです。Podman を使用して、開発ツールや日本語環境が事前設定された開発環境を簡単に構築・利用できます。

Oracle Linux 8 および 10 のマルチバージョンに対応しています。

## 特徴

- **ポータブル設計**: ビルド時にユーザー情報に依存せず、どの環境でも利用可能
- **豊富な開発ツール**: Node.js、Java、.NET、Python、C/C++ 開発環境
- **ドキュメント生成**: Doxygen、PlantUML、Pandoc による文書作成支援
- **日本語対応**: 日本語ロケール、フォント、マニュアルページを完備
- **セキュア**: SSH キー認証、適切な権限管理
- **高速**: rootless Podman による軽量コンテナ

## 利用シナリオ

このコンテナは以下のシナリオで利用できます。

### 🖥️ リモートサーバー開発（主用途）

**サーバー上にコンテナを常駐させ、VS Code Remote SSH で接続するスタイルです。**

コンテナ起動後は SSH サーバーが待ち受け状態となり、ローカルの VS Code から [Remote - SSH 拡張機能](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) を通じて直接接続できます。  
ホームディレクトリとワークスペースはホストにマウントされるため、コンテナを再起動しても作業データは保持されます。

```
[ローカル PC の VS Code]
        │  SSH 接続 (port 40822 / 41022)
        ▼
[リモートサーバー上の Podman コンテナ]
  ├── SSH サーバー（常駐）
  ├── 開発ツール群
  └── /workspace  ← ホストにマウント
```

この設計により、ローカルに開発ツールをインストールせず、複数人が同一サーバーのコンテナを個別インスタンスとして利用する構成も可能です。

### 📦 VS Code Dev Container として利用

**プロジェクトに `.devcontainer/` を配置し、Dev Containers 拡張機能から起動するスタイルです。**

ローカル環境に Docker または Podman があれば、イメージをダウンロードするだけで即座に開発環境が構築できます。

```bash
# サンプル設定をプロジェクトにコピー
cp -r examples/devcontainer/ol8 /your/project/.devcontainer
```

VS Code で `Dev Containers: Reopen in Container` を実行すると、開発ツールが事前設定された環境が起動します。  
詳細は [examples/devcontainer/](examples/devcontainer/) および [docs-src/using-in-vscode/](docs-src/using-in-vscode/) を参照してください。

### 🪟 WSL2 ディストリビューションとして利用（Windows）

Windows 標準の PowerShell のみで WSL2 にインポートできます。  
詳細は「[Windows 環境で WSL2 にインポート](#windows-環境で-wsl2-にインポート)」を参照してください。

### ⚙️ CI/CD での利用

GitHub Actions 等のビルド・テスト環境としても利用できます。  
詳細は [docs-src/using-in-cicd/](docs-src/using-in-cicd/) を参照してください。

---

## 公開イメージ

### GitHub Container Registry

| イメージ | タグ |
|---------|------|
| [oracle-linux-8-dev](https://github.com/hondarer/oracle-linux-container/pkgs/container/oracle-linux-container%2Foracle-linux-8-dev) | `latest` / `main` / `vYYYYMMDD.x.x` |
| [oracle-linux-10-dev](https://github.com/hondarer/oracle-linux-container/pkgs/container/oracle-linux-container%2Foracle-linux-10-dev) | `latest` / `main` / `vYYYYMMDD.x.x` |

```bash
podman pull ghcr.io/hondarer/oracle-linux-container/oracle-linux-8-dev:latest
podman pull ghcr.io/hondarer/oracle-linux-container/oracle-linux-10-dev:latest
```

### Docker Hub

GitHub Secrets (`DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`) を設定した場合、ghcr.io と同一タグで push されます。

| イメージ | タグ |
|---------|------|
| [hondarer/oracle-linux-8-dev](https://hub.docker.com/r/hondarer/oracle-linux-8-dev) | `latest` / `main` / `vYYYYMMDD.x.x` |
| [hondarer/oracle-linux-10-dev](https://hub.docker.com/r/hondarer/oracle-linux-10-dev) | `latest` / `main` / `vYYYYMMDD.x.x` |

```bash
podman pull hondarer/oracle-linux-8-dev:latest
podman pull hondarer/oracle-linux-10-dev:latest
```

## インストール済みツール

### 言語ランタイム

| ツール | OL8 | OL10 |
|--------|-----|------|
| Node.js | 24 | 22 |
| Java (OpenJDK) | 17 | 21 |
| .NET SDK | 10 | 10 |
| Python | 3.11 | 3.12 |
| C/C++ (GCC) | 8 | 14 |

### ドキュメント生成

- **Doxygen** + doxybook2
- **PlantUML**
- **Pandoc** + pandoc-crossref

### テスト・ビルドツール

- **Make**、**CMake**、**automake**、**libtool**
- **pkg-config**、**cmake**

### 開発ライブラリ

- **openssl-devel**、**libssh-devel**、**libcurl-devel**
- **binutils-devel**、**libX11-devel**、**libXt-devel**
- **glibc-static**、**libstdc++-static**

### ユーティリティ

- **jq**、**tree**、**rsync**
- **expect**、**nkf**、**cloc**
- **bubblewrap** (bwrap)
- **git**、**curl**、**wget**

## クイックスタート

### イメージビルド

```bash
# OL8 をビルド (デフォルト)
./build-pod.sh 8

# OL10 をビルド
./build-pod.sh 10
```

### コンテナ起動

```bash
# OL8 インスタンス1 を起動 (デフォルト)
./start-pod.sh 8

# OL10 インスタンス1 を起動
./start-pod.sh 10
```

### SSH 接続

```bash
# OL8 SSH 接続 (ポート 40822)
ssh -p 40822 user@127.0.0.1

# OL10 SSH 接続 (ポート 41022)
ssh -p 41022 user@127.0.0.1

# 初回接続時、SSH キーキャッシュのクリア
ssh-keygen -R "[127.0.0.1]:40822"
```

### コンテナ停止

```bash
# OL8 を停止
./stop-pod.sh 8

# OL10 を停止
./stop-pod.sh 10
```

## 基本的な使い方

### SSH キー認証の設定

ホストに `~/.ssh/id_rsa.pub` が存在する場合、自動的に SSH キー認証が設定されます。

```bash
# SSH キーペア生成 (必要に応じて)
ssh-keygen -t rsa -b 4096
```

### 開発環境の確認

```bash
# コンテナ内で各ツールのバージョン確認
node --version
java --version
dotnet --version
python --version
gcc --version
```

### ドキュメント生成例

```bash
# PlantUML 図の生成
plantuml diagram.puml

# Doxygen ドキュメント生成
doxygen Doxyfile

# Pandoc による文書変換
pandoc README.md -o README.pdf
```

## 高度な使い方

### イメージの保存・読み込み

```bash
# OL8 イメージを圧縮ファイルとして保存
./save-pod.sh 8

# OL10 イメージを保存
./save-pod.sh 10

# 保存したイメージを読み込み
./load-pod.sh 8
./load-pod.sh 10
```

### 追加パッケージの事前配置

`src/packages/` にパッケージファイルを配置すると、キャッシュとして動作します。  
対象パッケージファイルは、`src/Dockerfile` を参照してください。

### カスタムフォントの追加

`src/fonts/` にフォントファイルを配置すると、システムフォントとして利用可能になります。

## ディレクトリ構成

```text
.
├── build-pod.sh          # イメージビルドスクリプト
├── start-pod.sh          # コンテナ起動スクリプト
├── stop-pod.sh           # コンテナ停止スクリプト
├── save-pod.sh           # イメージ保存スクリプト
├── load-pod.sh           # イメージ読み込みスクリプト
├── src/                  # ビルドファイル
│   ├── Dockerfile       # メインのビルド定義
│   ├── entrypoint.sh    # コンテナ起動スクリプト
│   ├── keys/            # SSH ホストキー (オプション)
│   ├── fonts/           # 追加フォント (オプション)
│   └── packages/        # 追加パッケージ (オプション)
├── version-config.sh     # バージョン別共通設定
├── storage/              # 永続化データ
│   ├── 8/1/             # OL8 インスタンス1
│   │   ├── home_${USER}/
│   │   └── workspace/
│   └── 10/1/            # OL10 インスタンス1
│       ├── home_${USER}/
│       └── workspace/
├── image/                # イメージ保存場所
├── CLAUDE.md             # Claude Code 用ガイド
└── README.md             # このファイル
```

## 技術仕様

- **ベースイメージ**: Oracle Linux 8 / 10
- **コンテナエンジン**: Podman (rootless mode)
- **アーキテクチャ**: x86_64
- **ポート**: 22 (SSH、ホスト側は 40822/41022 等)
- **マウント**: ホームディレクトリ、ワークスペース
- **UID/GID マッピング**: Podman keep-id
- **ストレージ**: `./storage/{version}/{instance}/`

## トラブルシューティング

### SSH 接続できない場合

```bash
# コンテナの状態確認
podman ps

# コンテナログの確認 (OL8 の場合)
podman logs oracle-linux-8_1

# SSH キーキャッシュのクリア (OL8 の場合)
ssh-keygen -R "[127.0.0.1]:40822"
```

### 権限エラーが発生する場合

```bash
# SELinux コンテキストの修正
sudo restorecon -R ./storage/

# ストレージディレクトリの再作成 (OL8 インスタンス1 の場合)
rm -rf ./storage/8/1/
mkdir -p ./storage/8/1/{home_$(whoami),workspace}
```

### ビルドエラーが発生する場合

```bash
# 古いイメージの削除 (OL8 の場合)
podman rmi oracle-linux-8

# キャッシュクリア後の再ビルド
podman system prune -f
./build-pod.sh 8
```

## Windows 環境で WSL2 にインポート

Windows 標準の PowerShell のみで、GitHub Container Registry から WSL2 用 rootfs をダウンロードし、WSL2 ディストリビューションとしてインポートできます。

### クイックスタート (Windows)

```powershell
# WSL2 のインストール (未インストールの場合)
wsl --install

# スクリプトをダウンロードして実行 (OL8)
irm https://raw.githubusercontent.com/hondarer/oracle-linux-container/main/examples/import-wsl/import-wsl.ps1 | iex

# OL10 の場合
.\import-wsl.ps1 -OLVersion 10

# インポートされたディストリビューションを起動
wsl -d OracleLinux8-Dev
```

詳細は [examples/import-wsl/README.md](examples/import-wsl/README.md) を参照してください。

## 関連ドキュメント

### プロジェクトドキュメント

- [docs-src/](docs-src/) - 追加ドキュメント
  - [コンテナイメージ公開ガイド (GitHub / Docker Hub)](docs-src/publishing-to-github.md) - イメージの公開方法
  - [VS Code Dev Container として使用する](docs-src/using-in-vscode/) - Dev Containers 拡張機能を使った開発環境のセットアップ
  - [CI/CD でのコンテナイメージ利用ガイド](docs-src/using-in-cicd/) - 他のプロジェクトでの利用方法
    - 言語別サンプル: [C/C++](docs-src/using-in-cicd/cpp-example.md)、[Node.js](docs-src/using-in-cicd/nodejs-example.md)、[Java](docs-src/using-in-cicd/java-example.md)、[Python](docs-src/using-in-cicd/python-example.md)、[.NET](docs-src/using-in-cicd/dotnet-example.md)
- [examples/devcontainer/](examples/devcontainer/) - Dev Container サンプル設定ファイル（プロジェクトへコピーして利用）
- [CLAUDE.md](CLAUDE.md) - Claude Code を使用する際の詳細ガイド

### 外部リンク

- [Oracle Linux 8 公式ドキュメント](https://docs.oracle.com/en/operating-systems/oracle-linux/8/)
- [Oracle Linux 10 公式ドキュメント](https://docs.oracle.com/en/operating-systems/oracle-linux/10/)
- [Podman 公式ドキュメント](https://podman.io/docs)

## ライセンス

このプロジェクトは、**スクリプト・ドキュメント**と**生成されるコンテナイメージ**でライセンスが異なります。

### プロジェクトスクリプトおよびドキュメント

- **ライセンス**: MIT License
- **適用範囲**: ビルドスクリプト (build-pod.sh、start-pod.sh など)、ドキュメント、設定ファイル
- **詳細**: [LICENSE](./LICENSE) を参照してください

### コンテナイメージ

- **ライセンス**: GPL-2.0、GPL-3.0-or-later、MIT、BSD-3-Clause、PSF、OFL-1.1 などの複合ライセンス
- **適用範囲**: ビルドされるコンテナイメージとその内容
- **ベースOS ライセンス条項**: [src/LICENSE-IMAGE](./src/LICENSE-IMAGE) を参照してください
- **含まれるコンポーネント**: [src/NOTICE](./src/NOTICE) を参照してください

コンテナイメージは Oracle Linux (GPL-2.0) をベースとしており、GCC・PlantUML・rsync 等の GPL-3.0 コンポーネントを含む多数のオープンソースソフトウェアから構成されています。イメージを再配布する場合は、含まれる各コンポーネントのライセンス条項（特に GPL の copyleft 条件）に従う必要があります。

### 主要コンポーネントのライセンス

- **Oracle Linux 8/10**: GPL-2.0
- **OpenJDK 17/21**: GPL-2.0 with Classpath Exception
- **Node.js 24 (OL8) / 22 (OL10)**: MIT License
- **.NET 10**: MIT License
- **Python 3.11/3.12**: PSF License
- **GCC 8/14**: GPL-3.0-or-later
- **Doxygen**: GPL-2.0
- **PlantUML**: GPL-3.0+
- **Pandoc**: GPL-2.0+
- **rsync**: GPL-3.0

詳細なコンポーネントリストとライセンス情報は以下を参照してください：
- [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md) - 包括的なライセンス情報（推奨）
- [src/NOTICE](./src/NOTICE) - コンテナイメージに含まれるサードパーティコンポーネント一覧
