# コンテナイメージ公開ガイド (GitHub Container Registry / Docker Hub)

このドキュメントでは、Oracle Linux 開発用コンテナイメージを GitHub Container Registry (ghcr.io) および Docker Hub に公開する方法を説明します。

GitHub Actions ワークフロー (`.github/workflows/build-and-publish.yml`) は、ghcr.io への公開を標準で行います。GitHub Secrets に `DOCKERHUB_USERNAME` と `DOCKERHUB_TOKEN` を設定すると、Docker Hub にも同時に push されます。

## 目次

- [前提条件](#前提条件)
- [手動公開](#手動公開)
- [GitHub Actions による自動公開](#github-actions-による自動公開)
- [Docker Hub への公開設定](#docker-hub-への公開設定)
- [イメージの利用方法](#イメージの利用方法)
- [トラブルシューティング](#トラブルシューティング)

## 前提条件

### 必要なツール

- Podman (rootless mode 推奨)
- Git
- GitHub アカウント

### GitHub Personal Access Token の作成

1. GitHub にログイン
2. Settings → Developer settings → Personal access tokens → Tokens (classic)
3. "Generate new token (classic)" をクリック
4. 以下の権限を付与:
   - `write:packages` - パッケージのアップロード
   - `read:packages` - パッケージの読み取り
   - `delete:packages` - パッケージの削除 (オプション)
5. トークンを生成し、安全な場所に保存

### 環境変数の設定

```bash
# GitHub Personal Access Token を環境変数に設定
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# GitHub ユーザー名
export GITHUB_USER="your-github-username"

# リポジトリ名
export GITHUB_REPO="oracle-linux-container"
```

## 手動公開

### 1. イメージのビルド

```bash
# プロジェクトディレクトリに移動
cd /path/to/oracle-linux-container

# イメージをビルド
./build-pod.sh
```

### 2. イメージのタグ付け

```bash
# ローカルイメージ名を確認
podman images | grep oracle-linux-8-dev

# GitHub Container Registry 用にタグ付け
podman tag oracle-linux-8-dev:latest \
  ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:latest

# バージョンタグも追加 (推奨)
podman tag oracle-linux-8-dev:latest \
  ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:v1.0.0
```

### 3. GitHub Container Registry にログイン

```bash
# Personal Access Token を使用してログイン
echo $GITHUB_TOKEN | podman login ghcr.io -u ${GITHUB_USER} --password-stdin
```

成功すると以下のメッセージが表示されます:

```text
Login Succeeded!
```

### 4. イメージの公開

```bash
# latest タグを公開
podman push ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:latest

# バージョンタグも公開
podman push ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:v1.0.0
```

### 5. イメージの可視性設定

デフォルトでは、公開されたイメージはプライベートです。パブリックにする場合:

1. GitHub リポジトリページに移動
2. Packages セクションを開く
3. 公開したイメージを選択
4. "Package settings" → "Change visibility"
5. "Public" を選択して確認

## GitHub Actions による自動公開

### ワークフローファイルの作成

`.github/workflows/build-and-publish.yml` を作成します:

```yaml
name: Build and Publish Container Image

on:
  push:
    branches:
      - main
    tags:
      - 'v*'
  pull_request:
    branches:
      - main

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}/oracle-linux-8-dev

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Podman
        run: |
          sudo apt-get update
          sudo apt-get -y install podman

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=semver,pattern={{major}}
            type=sha

      - name: Build container image
        run: |
          cd src
          podman build -t ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} .

      - name: Push container image
        if: github.event_name != 'pull_request'
        run: |
          # Push all tags
          for tag in ${{ steps.meta.outputs.tags }}; do
            podman tag ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} $tag
            podman push $tag
          done

      - name: Output image URL
        if: github.event_name != 'pull_request'
        run: |
          echo "Image published to: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}"
          echo "Tags: ${{ steps.meta.outputs.tags }}"
```

### ワークフローの有効化

1. 上記ファイルをコミット
2. GitHub リポジトリに push

```bash
git add .github/workflows/build-and-publish.yml
git commit -m "Add GitHub Actions workflow for container image publishing"
git push origin main
```

3. GitHub の "Actions" タブでワークフローの実行を確認

### タグベースのリリース

バージョンタグを作成すると、自動的にそのバージョンでイメージが公開されます:

```bash
# バージョンタグを作成
git tag v1.0.0
git push origin v1.0.0
```

以下のタグが自動的に作成されます:
- `ghcr.io/<user>/<repo>/oracle-linux-8-dev:v1.0.0`
- `ghcr.io/<user>/<repo>/oracle-linux-8-dev:1.0`
- `ghcr.io/<user>/<repo>/oracle-linux-8-dev:1`
- `ghcr.io/<user>/<repo>/oracle-linux-8-dev:sha-<commit-hash>`

## Docker Hub への公開設定

### 1. Docker Hub アカウントと Access Token の準備

1. [Docker Hub](https://hub.docker.com/) でアカウントを作成
2. **Account settings** → **Personal access tokens** → **Generate new token**
   - Access permissions: `Read & Write`
   - 生成されたトークンをコピー (一度しか表示されない)
3. Docker Hub でリポジトリを作成 (名前: `oracle-linux-8-dev`、`oracle-linux-10-dev`)

### 2. GitHub Secrets への登録

GitHub リポジトリの **Settings** → **Secrets and variables** → **Actions** で以下を追加:

| Secret 名 | 値 |
|-----------|-----|
| `DOCKERHUB_USERNAME` | Docker Hub の Username |
| `DOCKERHUB_TOKEN` | 手順 1 で生成した Access Token |

### 3. 動作確認

Secrets 登録後に main ブランチへ push すると、`Push container image to Docker Hub` ステップが実行され、以下のイメージが公開されます。

```text
<dockerhub-user>/oracle-linux-8-dev:main
<dockerhub-user>/oracle-linux-10-dev:main
```

バージョンタグ (`v*`) を push した場合は `latest` を含む全タグが Docker Hub にも push されます。

Secrets が未定義の場合は Docker Hub 関連ステップが自動的にスキップされ、ghcr.io への公開には影響しません。

## イメージの利用方法

### Podman での利用

```bash
# GitHub Container Registry から取得
podman pull ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:latest

# Docker Hub から取得 (Docker Hub 公開時)
podman pull <dockerhub-user>/oracle-linux-8-dev:latest

# コンテナの起動
podman run -it --rm ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:latest
```

### Docker での利用

```bash
# GitHub Container Registry から取得
docker pull ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:latest

# Docker Hub から取得 (Docker Hub 公開時)
docker pull <dockerhub-user>/oracle-linux-8-dev:latest

# コンテナの起動
docker run -it --rm ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:latest
```

### GitHub Actions での利用

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:latest
      credentials:
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: |
          node --version
          java --version
          python --version
```

### Kubernetes での利用

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dev-pod
spec:
  containers:
  - name: dev-container
    image: ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:latest
  imagePullSecrets:
  - name: ghcr-secret
```

imagePullSecret の作成:

```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=${GITHUB_USER} \
  --docker-password=${GITHUB_TOKEN}
```

## プライベートイメージの利用

### 認証が必要な場合

```bash
# GitHub Container Registry にログイン
echo $GITHUB_TOKEN | podman login ghcr.io -u ${GITHUB_USER} --password-stdin

# イメージの取得
podman pull ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:latest
```

## イメージのメタデータ確認

```bash
# イメージの詳細情報を表示
podman inspect ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:latest

# ラベル情報のみ表示
podman inspect ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:latest \
  --format '{{json .Config.Labels}}' | jq
```

出力例:

```json
{
  "org.opencontainers.image.title": "Oracle Linux Development Container",
  "org.opencontainers.image.description": "Oracle Linux based development container with Node.js, Java, .NET, Python, Doxygen, PlantUML, and other development tools",
  "org.opencontainers.image.licenses": "GPL-2.0",
  "org.opencontainers.image.vendor": "Oracle America, Inc.",
  "org.opencontainers.image.base.name": "oraclelinux:8"
}
```

## トラブルシューティング

### 認証エラー

```text
Error: unauthorized: authentication required
```

**解決方法**:
1. Personal Access Token が有効か確認
2. トークンに `write:packages` 権限があるか確認
3. 再度ログイン

```bash
podman logout ghcr.io
echo $GITHUB_TOKEN | podman login ghcr.io -u ${GITHUB_USER} --password-stdin
```

### イメージが見つからない

```text
Error: image not known
```

**解決方法**:
1. イメージ名とタグが正しいか確認
2. リポジトリの可視性設定を確認 (プライベート/パブリック)
3. 認証が必要な場合はログインしているか確認

### ビルドエラー

```text
Error: error building at STEP ...
```

**解決方法**:
1. `src/Dockerfile` の構文エラーを確認
2. ネットワーク接続を確認 (パッケージダウンロード時)
3. ローカルでビルドが成功するか確認

```bash
cd src
podman build -t test-image .
```

### GitHub Actions ワークフローの失敗

**解決方法**:
1. GitHub の "Actions" タブでログを確認
2. `GITHUB_TOKEN` の権限設定を確認
3. ワークフローファイルの YAML 構文を確認

## ベストプラクティス

### イメージのタグ戦略

1. **latest タグ**: 常に最新版を指す
2. **バージョンタグ**: セマンティックバージョニング (v1.2.3)
3. **SHA タグ**: 特定のコミットを指す (再現性のため)

```bash
# 複数のタグを同時に公開
podman tag local-image:latest ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:latest
podman tag local-image:latest ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:v1.0.0
podman tag local-image:latest ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev:sha-abc123

podman push --all-tags ghcr.io/${GITHUB_USER}/${GITHUB_REPO}/oracle-linux-8-dev
```

### セキュリティ

1. **Personal Access Token の管理**:
   - 定期的にローテーション
   - 最小限の権限のみ付与
   - 環境変数またはシークレットマネージャーで管理

2. **イメージのスキャン**:
   - 脆弱性スキャンツールを使用 (Trivy、Clair など)
   - 定期的にベースイメージを更新

3. **プライベート vs パブリック**:
   - 開発用イメージはプライベート推奨
   - パブリック公開時はライセンス表記を確認

### CI/CD の最適化

1. **キャッシュの活用**:
   - ビルドキャッシュを使用して時間短縮
   - レイヤーキャッシュの最適化

2. **並列ビルド**:
   - 複数のアーキテクチャ (amd64、arm64) を並列ビルド

3. **自動テスト**:
   - イメージビルド後に自動テストを実行
   - コンテナ起動テスト、パッケージバージョン確認など

## 関連リンク

- [GitHub Container Registry ドキュメント](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Docker Hub](https://hub.docker.com/)
- [Docker Hub Access Token の管理](https://docs.docker.com/security/for-developers/access-tokens/)
- [Podman 公式ドキュメント](https://podman.io/docs)
- [GitHub Actions ドキュメント](https://docs.github.com/en/actions)
- [OCI Image Format Specification](https://github.com/opencontainers/image-spec)
