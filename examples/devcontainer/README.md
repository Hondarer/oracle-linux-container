# Dev Container サンプル設定

このディレクトリには、公開されている Oracle Linux コンテナイメージを使用し、対象プロジェクトで Dev Container を設定するためのサンプルが含まれています。
OL8、OL9、OL10 の各バリアントが `ol8/`、`ol9/`、`ol10/` サブディレクトリに用意されています。

## クイックスタート

### 1. プロジェクトへのコピー

対象ディレクトリの内容をプロジェクトのルートへコピーします。

```bash
# プロジェクトディレクトリで実行
cp -r /path/to/oracle-linux-container/examples/devcontainer/ol8 .devcontainer
```

### 2. VS Code で開く

1. VS Code と [Dev Containers 拡張機能](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) をインストールします。
2. Docker Desktop または Podman をインストールします。
3. プロジェクトを VS Code で開きます。
4. `Ctrl+Shift+P` (Mac: `Cmd+Shift+P`) を押し、"Dev Containers: Reopen in Container" を実行します。
5. イメージのダウンロードおよび起動の完了を待ちます。

## 含まれる開発ツール

- **言語ランタイム**: Node.js 24、Java 17(OL8)/21(OL9/10)、.NET 10、Python 3.11(OL8)/3.9(OL9)/3.12(OL10)
- **ビルドツール**: GCC、CMake、Make、automake
- **ドキュメント**: Doxygen、PlantUML、Pandoc
- **テスト**: Jest、JUnit、pytest、xUnit
- **日本語環境**: 日本語ロケールとフォント

## ファイル構成

- `ol8/devcontainer.json` - OL8 用 Dev Container 設定ファイル
  - 公開イメージ (`ghcr.io/hondarer/oracle-linux-container/oracle-linux-8-dev:latest`) を使用
- `ol9/devcontainer.json` - OL9 用 Dev Container 設定ファイル
  - 公開イメージ (`ghcr.io/hondarer/oracle-linux-container/oracle-linux-9-dev:latest`) を使用
- `ol10/devcontainer.json` - OL10 用 Dev Container 設定ファイル
  - 公開イメージ (`ghcr.io/hondarer/oracle-linux-container/oracle-linux-10-dev:latest`) を使用
- 共通機能:
  - ホストのユーザー名と UID/GID の自動マッピング
  - 推奨 VS Code 拡張機能の自動インストール
  - ホームディレクトリの永続化

## カスタマイズ

`devcontainer.json` を編集することで、次の項目をカスタマイズできます。

- VS Code 拡張機能の追加・削除
- 環境変数の設定
- ポート転送の設定
- 追加パッケージのインストール

詳細なドキュメントは [docs-src/using-in-vscode/](../../docs-src/using-in-vscode/) を参照してください。
