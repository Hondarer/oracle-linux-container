# ベストプラクティス

このドキュメントでは、Oracle Linux 開発用コンテナイメージを CI/CD パイプラインで運用する際のベストプラクティスを説明します。

## ナビゲーション

- [CI/CD でのコンテナイメージ利用ガイド](./README.md) - メインガイド
- [高度な設定](./advanced-configuration.md) - 高度な設定オプション
- [トラブルシューティング](./troubleshooting.md) - よくある問題と解決方法

---

## 目次

- [1. イメージバージョンの固定](#1-イメージバージョンの固定)
- [2. キャッシュの活用](#2-キャッシュの活用)
- [3. 最小権限の原則](#3-最小権限の原則)
- [4. シークレットの安全な管理](#4-シークレットの安全な管理)
- [5. 失敗時の通知](#5-失敗時の通知)
- [6. タイムアウトの設定](#6-タイムアウトの設定)
- [7. アーティファクトの保存](#7-アーティファクトの保存)
- [8. 環境の再現性](#8-環境の再現性)
- [9. ドキュメントの自動生成](#9-ドキュメントの自動生成)
- [10. 定期的なイメージ更新](#10-定期的なイメージ更新)

## 1. イメージバージョンの固定

本番環境では、予期せぬ更新に伴う動作差異を防ぐため、`latest` タグではなくバージョンタグを明示的に指定します。

```yaml
# 推奨
container:
  image: ghcr.io/<user>/<repo>/oracle-linux-8-dev:v1.0.0

# 非推奨 (本番環境)
container:
  image: ghcr.io/<user>/<repo>/oracle-linux-8-dev:latest
```

## 2. キャッシュの活用

ビルド時間を短縮するため、パッケージや依存関係のキャッシュを活用します。

```yaml
- name: Cache dependencies
  uses: actions/cache@v3
  with:
    path: ~/.cache
    key: ${{ runner.os }}-deps-${{ hashFiles('**/lockfile') }}
```

## 3. 最小権限の原則

セキュリティリスクを最小化するため、ワークフローには必要最小限の権限のみを付与します。

```yaml
permissions:
  contents: read      # リポジトリの読み取り
  packages: read      # パッケージの読み取り
  # 不要な権限は付与しない
```

## 4. シークレットの安全な管理

機密情報はワークフロー定義ファイル等に直接記述せず、GitHub Secrets を使用して安全に管理します。

```yaml
steps:
  - name: Use secrets safely
    env:
      API_KEY: ${{ secrets.API_KEY }}
    run: |
      # シークレットを使用
      echo "Using API key: ${API_KEY:0:5}..."  # 最初の数文字のみ表示
```

## 5. 失敗時の通知

ビルドやテストが失敗した際に迅速に対処できるよう、通知処理を設定します。

```yaml
jobs:
  notify:
    if: failure()
    runs-on: ubuntu-latest
    steps:
      - name: Send notification
        uses: 8398a7/action-slack@v3
        with:
          status: ${{ job.status }}
          webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

## 6. タイムアウトの設定

ジョブのハングアップやリソースの過剰消費を防ぐため、ジョブには適切なタイムアウト値を設定します。

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 30  # 30分でタイムアウト
```

## 7. アーティファクトの保存

ビルド成果物やログは、後続の検証や配布のためにアーティファクトとして保存します。

```yaml
- name: Upload artifacts
  uses: actions/upload-artifact@v3
  with:
    name: build-artifacts
    path: |
      build/
      dist/
    retention-days: 7  # 7日間保存
```

## 8. 環境の再現性

開発環境と CI/CD 環境で同一のコンテナイメージを使用することで、環境差異による不具合の発生を防止します。

```bash
# ローカル開発環境
podman run -it --rm \
  -e HOST_USER=$USER \
  -e HOST_UID=$(id -u) \
  -e HOST_GID=$(id -g) \
  -v ./:/workspace:Z \
  ghcr.io/<user>/<repo>/oracle-linux-8-dev:latest
```

## 9. ドキュメントの自動生成

ソースコードの変更に合わせてドキュメントを自動生成し、常に最新の状態を維持します。

```yaml
- name: Generate and deploy docs
  run: |
    doxygen Doxyfile
    doxybook2 --input docs/xml --output docs/markdown
```

## 10. 定期的なイメージ更新

セキュリティ修正を取り込むため、スケジュール実行等によりコンテナイメージを定期的に更新します。

```yaml
on:
  schedule:
    # 毎週月曜日の午前2時に実行
    - cron: '0 2 * * 1'
```

---

## 関連ドキュメント

- [CI/CD でのコンテナイメージ利用ガイド](./README.md) - メインガイド
- [高度な設定](./advanced-configuration.md) - 高度な設定オプション
- [トラブルシューティング](./troubleshooting.md) - よくある問題と解決方法
- [GitHub Container Registry への公開ガイド](../publishing-to-github.md) - イメージの公開方法

## 追加リソース

- [GitHub Actions ドキュメント](https://docs.github.com/en/actions) - GitHub Actions の公式ドキュメント
- [Podman ドキュメント](https://docs.podman.io/) - Podman の公式ドキュメント
- [CLAUDE.md](../../CLAUDE.md) - プロジェクトの詳細仕様
- [README.md](../../README.md) - プロジェクト概要とクイックスタート
