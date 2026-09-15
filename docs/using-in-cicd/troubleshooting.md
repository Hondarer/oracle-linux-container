# トラブルシューティング

このドキュメントでは、Oracle Linux 開発用コンテナイメージを CI/CD パイプラインで運用する際に発生しやすい問題と、その解決方法を説明します。

## ナビゲーション

- [CI/CD でのコンテナイメージ利用ガイド](./README.md) - メインガイド
- [高度な設定](./advanced-configuration.md) - 高度な設定オプション
- [ベストプラクティス](./best-practices.md) - 推奨される運用方法

---

## 目次

- [コンテナ起動時のエラー](#コンテナ起動時のエラー)
- [権限エラー](#権限エラー)
- [ビルドエラー](#ビルドエラー)
- [ネットワークエラー](#ネットワークエラー)
- [デバッグ方法](#デバッグ方法)

## コンテナ起動時のエラー

### 問題: entrypoint.sh でユーザー作成に失敗する

```text
Error: useradd: UID 1000 is not unique
```

**解決策**: 既存の UID と競合しています。コンテナ環境内で重複しない別の UID を指定します。

```yaml
container:
  env:
    HOST_UID: 1100  # 別の UID を使用
    HOST_GID: 1100
```

### 問題: SSH サービスが起動しない

```text
Error: sshd: no hostkeys available
```

**解決策**: SSH ホストキーが正しく配置されているか確認します。コンテナイメージには事前に SSH ホストキーが含まれていますが、独自の設定で上書きしている場合はパーミッションや配置先を確認してください。

## 権限エラー

### 問題: ファイルへの書き込み権限がない

```text
Error: Permission denied
```

**解決策**: ホストまたはランナー環境と整合するよう、UID/GID の設定値を確認・調整します。

```yaml
container:
  env:
    # GitHub Actions のランナーと同じ UID/GID を使用
    HOST_USER: runner
    HOST_UID: 1001
    HOST_GID: 121
```

### 問題: sudo が使えない

```text
Error: user is not in the sudoers file
```

**解決策**: `entrypoint.sh` が正常に実行され、対象ユーザーが `wheel` グループに追加されているか確認します。

```yaml
steps:
  - name: Check user groups
    run: |
      id
      groups
```

## ビルドエラー

### 問題: メモリ不足

```text
Error: virtual memory exhausted: Cannot allocate memory
```

**解決策**: 並列ビルド数（`-j` オプション）を制限するか、より大きなメモリリソースを持つランナーインスタンスを使用します。

```yaml
steps:
  - name: Build with limited parallelism
    run: |
      make -j2  # 並列数を制限
```

### 問題: 依存パッケージがない

```text
Error: command not found
```

**解決策**: 実行に必要なパッケージを `dnf` でインストールします。

```yaml
steps:
  - name: Install additional packages
    run: |
      sudo dnf install -y <package-name>
```

### 問題: venv 内で pytest が見つからない

```text
bash: pytest: command not found
```

**解決策**: 推奨される対処方法は、`pytest` および `pytest-cov` を仮想環境内にインストールすることです。これにより、テスト対象の依存関係と同一の Python 環境で pytest が動作します。

```bash
python -m venv venv
source venv/bin/activate
python -m pip install pytest pytest-cov
python -m pytest --version
```

システムに組み込み済みの pytest を再利用する場合は、システムの site-packages を引き継いだ仮想環境を作成し、必ず仮想環境の Python を経由して実行します。

```bash
python -m venv --system-site-packages venv
source venv/bin/activate
python -m pytest -v
```

## ネットワークエラー

### 問題: イメージの pull に失敗する

```text
Error: unauthorized: authentication required
```

**解決策**: レジストリに対する認証情報（トークンや権限）が正しく設定されているか確認します。

```yaml
container:
  credentials:
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

プライベートイメージを利用する場合は、パッケージの読み取り権限（`read:packages`）を持つトークンを設定します。

## デバッグ方法

### コンテナ内の状態確認

問題発生時にコンテナ環境の詳細情報を出力して原因を切り分けます。

```yaml
steps:
  - name: Debug container state
    run: |
      echo "=== Current user ==="
      whoami
      id

      echo "=== Environment variables ==="
      env | sort

      echo "=== Working directory ==="
      pwd
      ls -la

      echo "=== Mounted volumes ==="
      df -h

      echo "=== Network configuration ==="
      ip addr

      echo "=== Running processes ==="
      ps aux

      echo "=== System resources ==="
      free -h
      cat /proc/cpuinfo | grep "model name" | head -1
```

### entrypoint.sh のログ確認

`entrypoint.sh` の詳細な実行ログを確認し、ユーザー作成や権限設定の失敗原因を調査します。

```yaml
steps:
  - name: Check entrypoint logs
    run: |
      cat /var/log/entrypoint.log
```

---

## 関連ドキュメント

- [CI/CD でのコンテナイメージ利用ガイド](./README.md) - メインガイド
- [高度な設定](./advanced-configuration.md) - 高度な設定オプション
- [ベストプラクティス](./best-practices.md) - 推奨される運用方法
- [GitHub Container Registry への公開ガイド](../publishing-to-github.md) - イメージの公開方法

## サポート

問題が解決しない場合は、次のリソースを参照してください。

- [GitHub Issues](https://github.com/<user>/<repo>/issues) - バグ報告や機能リクエスト
- [GitHub Actions ドキュメント](https://docs.github.com/en/actions) - GitHub Actions の公式ドキュメント
- [Podman ドキュメント](https://docs.podman.io/) - Podman の公式ドキュメント
