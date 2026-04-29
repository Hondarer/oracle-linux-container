# WSL2 インポートツール

Oracle Linux 開発環境を WSL2 にインポートするための PowerShell スクリプトです。OL8 と OL10 に対応しています。

## 概要

このスクリプトは、GitHub Releases から取得した WSL2 用 rootfs (`tar.gz`) を使って、WSL2 ディストリビューションとしてインポートします。

標準手順は、release asset として配布される `tar.gz` をローカルに保存し、`-RootFsPath` で指定する方法です。

必要に応じて、GitHub Container Registry (`ghcr.io`) に公開されている WSL2 専用 OCI artifact から rootfs を直接ダウンロードすることもできます。こちらは開発版や未リリース版を取得したい場合のオプション手順です。

Windows 標準の PowerShell のみを使用し、外部ツール (Docker、podman、oras など) は不要です。

## 前提条件

- Windows 10 (1803 以降) または Windows 11
- WSL2 がインストール済み
- インターネット接続 (release asset またはレジストリから取得する場合)

WSL2 がインストールされていない場合は、以下のコマンドでインストールしてください。

```powershell
wsl --install
```

## クイックスタート

### Release asset を使う標準手順

```powershell
# 1. GitHub Releases から対象バージョンの rootfs をダウンロード
#    https://github.com/hondarer/oracle-linux-container/releases/latest
#    例: OracleLinux8-Dev.tar.gz を Downloads に保存

# 2. スクリプトをダウンロード
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/hondarer/oracle-linux-container/main/examples/import-wsl/import-wsl.ps1" `
  -OutFile ".\import-wsl.ps1"

# 3. OL8 をインポート
.\import-wsl.ps1 `
  -RootFsPath "$env:USERPROFILE\Downloads\OracleLinux8-Dev.tar.gz" `
  -WslDistroName "OracleLinux8-Dev"

# OL10 をインポートする場合
.\import-wsl.ps1 `
  -RootFsPath "$env:USERPROFILE\Downloads\OracleLinux10-Dev.tar.gz" `
  -WslDistroName "OracleLinux10-Dev"

# インポートされたディストリビューションを起動
wsl -d OracleLinux8-Dev
```

### ローカルスクリプトを使用

```powershell
# リポジトリをクローン
git clone https://github.com/hondarer/oracle-linux-container.git
cd oracle-linux-container\examples\import-wsl

# GitHub Releases から事前に取得した rootfs を指定して実行
.\import-wsl.ps1 -RootFsPath "D:\staging\OracleLinux8-Dev.tar.gz" -WslDistroName "OracleLinux8-Dev"

# カスタムパラメータで実行
.\import-wsl.ps1 `
  -RootFsPath "D:\staging\OracleLinux8-Dev.tar.gz" `
  -WslDistroName "MyOracleLinux" `
  -InstallLocation "C:\WSL\MyDist"
```

### `ghcr.io` から直接取得するオプション手順

release asset ではなく、`ghcr.io` 上の WSL OCI artifact から直接取得したい場合は `Tag` または `ImageUrl` を使います。

```powershell
# スクリプトをダウンロード
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/hondarer/oracle-linux-container/main/examples/import-wsl/import-wsl.ps1" `
  -OutFile ".\import-wsl.ps1"

# main ブランチ相当の開発版を直接取得してインポート
.\import-wsl.ps1 -Tag "main-wsl"

# 完全なイメージ URL を指定する場合
.\import-wsl.ps1 -ImageUrl "ghcr.io/hondarer/oracle-linux-container/oracle-linux-8-dev:v1.0.0-wsl"

# rootfs をダウンロードだけして保存する場合
.\import-wsl.ps1 `
  -Tag "main-wsl" `
  -DownloadOnly `
  -RootFsOutputPath ".\OracleLinux8-Dev.tar.gz"
```

### エアギャップ環境へ持ち込んで実行

標準手順では、オンライン環境で GitHub Releases から `tar.gz` を取得し、USB メモリや社内配布ストレージなどでエアギャップ環境へ持ち込みます。

```powershell
# 1. オンライン環境でスクリプトを保存
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/hondarer/oracle-linux-container/main/examples/import-wsl/import-wsl.ps1" `
  -OutFile ".\import-wsl.ps1"

# 2. オンライン環境で GitHub Releases から rootfs をダウンロード
#    例: OracleLinux8-Dev.tar.gz を保存

# 3. エアギャップ環境へファイルを持ち込む
#    - import-wsl.ps1
#    - OracleLinux8-Dev.tar.gz

# 4. エアギャップ環境でローカル rootfs を指定してインストール
.\import-wsl.ps1 -RootFsPath "D:\staging\OracleLinux8-Dev.tar.gz" -WslDistroName "OracleLinux8-Dev"
```

## パラメータ

### RootFsPath

事前に取得したローカルの WSL rootfs (`tar.gz`) ファイルを指定します。通常は GitHub Releases からダウンロードしたファイルをここに指定します。指定した場合は `ImageUrl` と `Tag` より優先されます。**`RootFsPath` を使ってインストールする場合は `-WslDistroName` の指定が必要です。**

使用例:

```powershell
# release asset として取得した rootfs を使ってインポート
.\import-wsl.ps1 -RootFsPath "D:\staging\OracleLinux8-Dev.tar.gz" -WslDistroName "OracleLinux8-Dev"
```

### WslDistroName

WSL ディストリビューション名を指定します。`RootFsPath` を使う標準手順では必須です。デフォルトは `OracleLinux{OLVersion}-Dev` で、たとえば OL8 は `OracleLinux8-Dev`、OL10 は `OracleLinux10-Dev` です。

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

### OLVersion

Oracle Linux のバージョンを指定します (デフォルト: `8`)。主に `ghcr.io` から直接取得する場合の既定値生成に使われます。

使用例:

```powershell
# ghcr.io から OL10 をインポート
.\import-wsl.ps1 -OLVersion 10 -Tag "main-wsl"
```

### Tag

`ghcr.io` から直接取得する場合のイメージタグを指定します (デフォルト: `latest-wsl`)。

利用可能なタグ:

- `main-wsl`: main ブランチの最新ビルド
- `latest-wsl`: 最新の安定版リリース相当
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

完全なイメージ URL を指定します。`ghcr.io` 以外のレジストリを含めて明示したい場合に使用します。`Tag` パラメータより優先されます。

使用例:

```powershell
# カスタムレジストリから取得
.\import-wsl.ps1 -ImageUrl "ghcr.io/myuser/myrepo:custom-tag"
```

### DownloadOnly

`ghcr.io` などから WSL rootfs をダウンロードしたあと、`wsl --import` を行わずに終了します。オンライン環境で rootfs ファイルだけを事前取得したい場合に使用します。

使用例:

```powershell
# rootfs をダウンロードして終了
.\import-wsl.ps1 -DownloadOnly
```

### RootFsOutputPath

`DownloadOnly` または通常のオンライン取得時に、ダウンロードした WSL rootfs の保存先を指定します。未指定の場合は一時ディレクトリ配下に `wsl-rootfs.tar.gz` を保存します。

使用例:

```powershell
# 保存先を指定して rootfs をダウンロード
.\import-wsl.ps1 -DownloadOnly -RootFsOutputPath "D:\staging\wsl-rootfs.tar.gz"
```

## 重要な注意事項

### オフラインインストールについて

- `RootFsPath` に指定するファイルは、GitHub Releases から取得したものを含む、WSL2 に `wsl --import` できる rootfs (`tar.gz`) を想定しています
- `DownloadOnly` を指定すると、スクリプトは `ghcr.io` などから rootfs を保存したあとインストールせずに終了します
- `RootFsOutputPath` はダウンロードした rootfs の保存先です
- `RootFsPath` を指定した場合、スクリプトはレジストリへ接続せず、ローカルファイルをそのまま使用します
- `RootFsPath` を使ってインストールする場合は、インポート先を明確にするため `-WslDistroName` を必ず指定してください
- `ImageUrl` や `Tag` を同時に指定しても、`RootFsPath` が優先されます

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

### Release asset / ローカル rootfs を使う場合

1. **rootfs 指定**: `-RootFsPath` でローカルの `tar.gz` を指定
2. **既存ホームの退避 (必要時)**: 同名ディストリビューションがあり移行を選んだ場合、`/home` 配下を `tar.gz` として一時ディレクトリへ圧縮退避
3. **WSL2 インポート**: `wsl.exe --import` でディストリビューションとして登録
4. **ホーム復元 (必要時)**: 退避した `tar.gz` を新しいディストリビューションの `/home` に展開
5. **動作確認**: 基本的なコマンドで動作を確認

### `ghcr.io` から直接取得する場合

1. **レジストリ認証**: GitHub Container Registry から認証トークンを取得
2. **マニフェスト取得**: 指定されたタグの OCI マニフェストを取得
3. **Rootfs ダウンロード**: WSL2 用 rootfs (`tar.gz`) をダウンロード
4. 以降はローカル rootfs 指定時と同様に WSL2 へインポート

`ghcr.io` を使う場合も、処理はすべて PowerShell の標準機能 (`Invoke-RestMethod`、`Invoke-WebRequest`) を使用します。

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

WSL 用 rootfs には `user` ユーザーが事前作成されており、`/etc/wsl.conf` で既定ユーザーとして設定済みです。

そのため、インポート後は追加の初期化なしでそのまま利用できます。

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
- GitHub Releases から取得する場合は、release asset が完全にダウンロードされているか確認してください
- プロキシ環境の場合、PowerShell のプロキシ設定を確認してください
- `ghcr.io` を使う場合は、イメージ URL とタグが正しいか確認してください

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

# 再度インポート (release asset を使う標準手順)
.\import-wsl.ps1 -RootFsPath "D:\staging\OracleLinux8-Dev.tar.gz" -WslDistroName "OracleLinux8-Dev"
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

### OCI Registry API v2 (`ghcr.io` を使う場合)

`ghcr.io` から直接取得する場合、スクリプトは OCI Registry API v2 を使用して、以下の処理を行います。

- 認証トークンの取得
- マニフェストの取得
- Blob (rootfs) のダウンロード

### WSL2 インポート形式

release asset または `ghcr.io` から取得される rootfs は `tar.gz` 形式で、`wsl --import` コマンドで直接インポート可能です。

## 関連リンク

- [プロジェクトルート README](../../README.md)
- [GitHub Releases](https://github.com/Hondarer/oracle-linux-container/releases)
- [GitHub Container Registry](https://github.com/Hondarer/oracle-linux-container/pkgs/container/oracle-linux-container%2Foracle-linux-8-dev)
- [WSL ドキュメント](https://learn.microsoft.com/ja-jp/windows/wsl/)

## ライセンス

このスクリプトは MIT License で提供されています。詳細は [LICENSE](../../LICENSE) を参照してください。

インポートされるコンテナイメージは GPL-2.0、GPL-3.0-or-later、Apache-2.0、LGPL-2.1-or-later、MIT 等の複合ライセンスのコンポーネントから構成されています。詳細は [src/LICENSE-IMAGE](../../src/LICENSE-IMAGE)（Oracle Linux ライセンス条項）および [src/NOTICE](../../src/NOTICE) を参照してください。
