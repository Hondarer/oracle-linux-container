# WSL2 インポートツール

Oracle Linux 開発環境を WSL2 にインポートするための PowerShell スクリプトです。OL8 と OL10 に対応しています。

## 概要

このスクリプトは、GitHub Container Registry (ghcr.io) から OCI Artifact として公開されている WSL2 専用 rootfs をダウンロードし、WSL2 ディストリビューションとしてインポートします。

Windows 標準の PowerShell のみを使用し、外部ツール (Docker、podman、oras など) は不要です。

## 前提条件

- Windows 10 (1803 以降) または Windows 11
- WSL2 がインストール済み
- インターネット接続

WSL2 がインストールされていない場合は、以下のコマンドでインストールしてください。

```powershell
wsl --install
```

## クイックスタート

### GitHub から直接実行

```powershell
# スクリプトをダウンロードして実行
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/hondarer/oracle-linux-container/main/examples/import-wsl/import-wsl.ps1).TrimStart([char]0xFEFF)))

# インポートされたディストリビューションを起動
wsl -d OracleLinux8-Dev
```

### ローカルスクリプトを使用

```powershell
# リポジトリをクローン
git clone https://github.com/hondarer/oracle-linux-container.git
cd oracle-linux-container\examples\import-wsl

# スクリプトを実行 (デフォルト: latest-wsl タグ)
.\import-wsl.ps1

# 特定のタグを指定して実行 (latest-wsl が存在しない場合など)
.\import-wsl.ps1 -Tag "main-wsl"

# カスタムパラメータで実行
.\import-wsl.ps1 -WslDistroName "MyOracleLinux" -InstallLocation "C:\WSL\MyDist"

# 完全なイメージ URL を指定する場合
.\import-wsl.ps1 -ImageUrl "ghcr.io/hondarer/oracle-linux-container/oracle-linux-8-dev:v1.0.0-wsl"
```

## パラメータ

### OLVersion

Oracle Linux のバージョンを指定します (デフォルト: `8`)

使用例:

```powershell
# OL10 をインポート
.\import-wsl.ps1 -OLVersion 10
```

### Tag

イメージタグを指定します (デフォルト: `latest-wsl`)

利用可能なタグ:

- `main-wsl`: main ブランチの最新ビルド
- `latest-wsl`: 最新の安定版リリース (バージョンタグがプッシュされている場合)
- `v1.0.0-wsl`: 特定バージョン (例)
- `sha-xxxxx-wsl`: 特定コミット

使用例:

```powershell
# main ブランチの最新ビルドを使用
.\import-wsl.ps1 -Tag "main-wsl"

# 特定バージョンを使用
.\import-wsl.ps1 -Tag "v1.0.0-wsl"
```

### ImageUrl

完全なイメージ URL を指定します。Tag パラメータより優先されます。

使用例:

```powershell
# カスタムレジストリから取得
.\import-wsl.ps1 -ImageUrl "ghcr.io/myuser/myrepo:custom-tag"
```

### WslDistroName

WSL ディストリビューション名を指定します (デフォルト: `OracleLinux{OLVersion}-Dev`、例: `OracleLinux8-Dev`)

使用例:

```powershell
# カスタム名でインポート
.\import-wsl.ps1 -WslDistroName "OracleLinux-Custom"
```

### InstallLocation

インストール先ディレクトリを指定します (デフォルト: `$env:LOCALAPPDATA\WSL\<DistroName>`)

使用例:

```powershell
# カスタムディレクトリにインストール
.\import-wsl.ps1 -InstallLocation "D:\WSL\OracleLinux"
```

## 重要な注意事項

### 既存のディストリビューションについて

同名の WSL ディストリビューションが既に登録されている場合、スクリプトは再作成方法を確認します。

```
警告: 既存のディストリビューション 'OracleLinux8-Dev' が見つかりました

  このディストリビューションを削除すると、現在の登録は置き換えられます:
  - クリーン再作成を選ぶと、既存のホームディレクトリ内データは失われます
  - 移行を選ぶと、/home 配下を tar.gz で圧縮退避してから復元します
  - /home ディレクトリ自体は置き換えず、配下のファイルとディレクトリを移行します

再作成方法を選択してください:
  [Enter] M : /home 配下を移行する
          C : クリーンな環境で再作成する
          N : キャンセルする
```

Enter または `M` を入力すると、`/home` 配下の内容を一時ディレクトリに `tar.gz` で退避してから、新しいディストリビューションの `/home` へ復元します。`C` を入力すると移行せずにクリーンな環境として再作成します。`N` を入力するとインポートをキャンセルします。

**重要**: 移行対象は `/home` ディレクトリそのものではなく、その直下のファイル・ディレクトリです。重要なデータがある場合は、事前に追加バックアップを取るか、異なる `WslDistroName` を指定してください。

### データのバックアップ方法

既存のディストリビューションをバックアップする場合:

```powershell
# ディストリビューションをエクスポート
wsl --export OracleLinux8-Dev C:\backup\oracle-linux-backup.tar

# 後で復元する場合
wsl --import OracleLinux8-Dev-Restored C:\WSL\Restored C:\backup\oracle-linux-backup.tar
```

## 仕組み

このスクリプトは以下の手順で WSL2 にインポートします。

1. **レジストリ認証**: GitHub Container Registry から認証トークンを取得
2. **マニフェスト取得**: 指定されたタグの OCI マニフェストを取得
3. **Rootfs ダウンロード**: WSL2 用 rootfs (tar.gz) をダウンロード
4. **既存ホームの退避 (必要時)**: 同名ディストリビューションがあり移行を選んだ場合、`/home` 配下を `tar.gz` として一時ディレクトリへ圧縮退避
5. **WSL2 インポート**: `wsl.exe --import` でディストリビューションとして登録
6. **ホーム復元 (必要時)**: 退避した `tar.gz` を新しいディストリビューションの `/home` に展開
7. **動作確認**: 基本的なコマンドで動作を確認

すべての処理は PowerShell の標準機能 (`Invoke-RestMethod`、`Invoke-WebRequest`) を使用します。

## インポート後の使用方法

### ディストリビューションの起動

```powershell
# ディストリビューションを起動
wsl -d OracleLinux8-Dev

# デフォルトのディストリビューションに設定
wsl --set-default OracleLinux8-Dev

# 起動後はデフォルトで使用可能
wsl
```

### 初回起動時の設定

初回起動時、entrypoint.sh により自動的にユーザーが作成されます。

デフォルトでは Windows ユーザー名と同じユーザーが作成されますが、環境変数で制御することもできます。

```powershell
# カスタムユーザーで起動 (初回のみ)
wsl -d OracleLinux8-Dev -e bash -c 'HOST_USER=myuser HOST_UID=1000 HOST_GID=1000 /entrypoint.sh'
```

### インストール済みツールの確認

```bash
# Node.js
node --version

# Java
java --version

# .NET
dotnet --version

# Python
python --version

# その他のツール
doxygen --version
plantuml -version
pandoc --version
```

## トラブルシューティング

### WSL2 が利用できない

```powershell
# WSL のバージョン確認
wsl --version

# WSL2 をインストール
wsl --install
```

> **Hyper-V ゲストの Windows で WSL2 を使用する場合**
>
> Hyper-V 上の仮想マシンで Windows を実行している場合、WSL2 を有効にするにはホスト側でネスト仮想化 (ExposeVirtualizationExtensions) を有効にする必要があります。
> 対象の仮想マシンをシャットダウンした後、**ホスト** の PowerShell で以下を実行してください。
>
> ```powershell
> # 現在の設定を確認 (ホストで実行)
> Get-VMProcessor -VMName * | ft VMName,ExposeVirtualizationExtensions
>
> # ネスト仮想化を有効化 (ホストで実行、<VMName> は対象 VM 名に変更)
> Set-VMProcessor -VMName <VMName> -ExposeVirtualizationExtensions $true
> ```
>
> 設定後、仮想マシンを起動して再度 WSL2 のインストールをお試しください。

### ダウンロードが失敗する

- インターネット接続を確認してください
- プロキシ環境の場合、PowerShell のプロキシ設定を確認してください
- イメージ URL とタグが正しいか確認してください

### インポートが失敗する

```powershell
# WSL のログを確認
wsl --list --verbose

# 既存のディストリビューションを確認
wsl --list
```

### ディストリビューションが起動しない

```powershell
# ディストリビューションを削除
wsl --unregister OracleLinux8-Dev

# 再度インポート
.\import-wsl.ps1
```

## アンインストール

```powershell
# ディストリビューションを削除
wsl --unregister OracleLinux8-Dev

# インストールディレクトリを削除 (オプション)
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\WSL\OracleLinux8-Dev"

# 一時ファイルを削除
Remove-Item -Recurse -Force "$env:TEMP\wsl-import-*"
```

## 技術仕様

### 使用する Windows 標準機能

- **PowerShell**: Invoke-RestMethod、Invoke-WebRequest
- **wsl.exe**: WSL2 管理コマンド

### OCI Registry API v2

スクリプトは OCI Registry API v2 を使用して、以下の処理を行います。

- 認証トークンの取得
- マニフェストの取得
- Blob (rootfs) のダウンロード

### WSL2 インポート形式

ダウンロードされる rootfs は `tar.gz` 形式で、`wsl --import` コマンドで直接インポート可能です。

## 関連リンク

- [プロジェクトルート README](../../README.md)
- [GitHub Container Registry](https://github.com/Hondarer/oracle-linux-container/pkgs/container/oracle-linux-container%2Foracle-linux-8-dev)
- [WSL ドキュメント](https://learn.microsoft.com/ja-jp/windows/wsl/)

## ライセンス

このスクリプトは MIT License で提供されています。詳細は [LICENSE](../../LICENSE) を参照してください。

インポートされるコンテナイメージは GPL-2.0、GPL-3.0-or-later、Apache-2.0、LGPL-2.1-or-later、MIT 等の複合ライセンスのコンポーネントから構成されています。詳細は [src/LICENSE-IMAGE](../../src/LICENSE-IMAGE)（Oracle Linux ライセンス条項）および [src/NOTICE](../../src/NOTICE) を参照してください。
