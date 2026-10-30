# WSL2 インポートツール

Oracle Linux 開発環境を WSL2 にインポートするための PowerShell スクリプトです。
OL8、OL9、OL10 に対応しています。

インポート後に WSL2 の仮想ディスク (`ext4.vhdx`) を圧縮するスクリプト `compact-wsl.ps1` も同梱しています。
詳細は [仮想ディスクの圧縮](#仮想ディスクの圧縮) を参照してください。

## 概要

このスクリプトは、GitHub Releases から取得した WSL2 用 rootfs (`tar.gz` または `tar`) を使用し、WSL2 ディストリビューションとしてインポートします。

GitHub Releases から release asset として配布される `tar.gz` をローカルに保存し、`-RootFsPath` で指定して実行します。
`tar.gz` を展開した `tar` ファイルをそのまま指定することもできます (`wsl --import` が `tar.gz` / `tar` の両形式を自動判別します)。

Windows 標準の PowerShell のみを使用し、外部ツール (Docker、podman など) は不要です。

## 前提条件

- Windows 10 バージョン 2004 以降 (ビルド 19041 以降) または Windows 11
- WSL2 がインストール済み
- インターネット接続 (release asset から取得する場合)

WSL2 がインストールされていない場合は、管理者の PowerShell で以下を実行し、再起動してください。
`--no-distribution` を指定しない場合は、既定の Ubuntu がインストールされます。
本手順では GitHub Releases の rootfs をインポートするため、既定のディストリビューションは不要です。

```powershell
wsl --install --no-distribution
```

## クイックスタート

### Release asset を使用する標準手順

```powershell
# 1. GitHub Releases から対象バージョンの rootfs をダウンロード
#    https://github.com/hondarer/oracle-linux-container/releases/latest
#    例: oracle-linux-8-dev-vYYYYMMDD.x.x-wsl-rootfs.tar.gz を Downloads に保存

# 2. スクリプトをダウンロード
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/hondarer/oracle-linux-container/main/examples/import-wsl/import-wsl.ps1" `
  -OutFile ".\import-wsl.ps1"

# 3. OL8 をインポート
$RootFs8 = "$env:USERPROFILE\Downloads\oracle-linux-8-dev-vYYYYMMDD.x.x-wsl-rootfs.tar.gz"
powershell -ExecutionPolicy Bypass -File .\import-wsl.ps1 `
  -RootFsPath $RootFs8 `
  -WslDistroName "OracleLinux8-Dev"

# OL9 をインポートする場合
$RootFs9 = "$env:USERPROFILE\Downloads\oracle-linux-9-dev-vYYYYMMDD.x.x-wsl-rootfs.tar.gz"
powershell -ExecutionPolicy Bypass -File .\import-wsl.ps1 `
  -RootFsPath $RootFs9 `
  -WslDistroName "OracleLinux9-Dev"

# OL10 をインポートする場合
$RootFs10 = "$env:USERPROFILE\Downloads\oracle-linux-10-dev-vYYYYMMDD.x.x-wsl-rootfs.tar.gz"
powershell -ExecutionPolicy Bypass -File .\import-wsl.ps1 `
  -RootFsPath $RootFs10 `
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
powershell -ExecutionPolicy Bypass -File .\import-wsl.ps1 -RootFsPath "D:\staging\oracle-linux-8-dev-vYYYYMMDD.x.x-wsl-rootfs.tar.gz" -WslDistroName "OracleLinux8-Dev"

# カスタムパラメータで実行
powershell -ExecutionPolicy Bypass -File .\import-wsl.ps1 `
  -RootFsPath "D:\staging\oracle-linux-8-dev-vYYYYMMDD.x.x-wsl-rootfs.tar.gz" `
  -WslDistroName "MyOracleLinux" `
  -InstallLocation "C:\WSL\MyDist"
```

### エアギャップ環境へ持ち込んで実行

標準手順では、オンライン環境で GitHub Releases から `tar.gz` を取得し、USB メモリや社内配布ストレージなどでエアギャップ環境へ持ち込みます。

```powershell
# 1. オンライン環境でスクリプトを保存
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/hondarer/oracle-linux-container/main/examples/import-wsl/import-wsl.ps1" `
  -OutFile ".\import-wsl.ps1"

# 2. オンライン環境で GitHub Releases から rootfs をダウンロード
#    例: oracle-linux-8-dev-vYYYYMMDD.x.x-wsl-rootfs.tar.gz を保存

# 3. エアギャップ環境へファイルを持ち込む
#    - import-wsl.ps1
#    - oracle-linux-8-dev-vYYYYMMDD.x.x-wsl-rootfs.tar.gz

# 4. エアギャップ環境でローカル rootfs を指定してインストール
powershell -ExecutionPolicy Bypass -File .\import-wsl.ps1 -RootFsPath "D:\staging\oracle-linux-8-dev-vYYYYMMDD.x.x-wsl-rootfs.tar.gz" -WslDistroName "OracleLinux8-Dev"
```

## パラメータ

### RootFsPath

事前に取得したローカルの WSL rootfs (`tar.gz` または `tar`) ファイルを指定します。
通常は GitHub Releases からダウンロードしたファイルをここに指定します。
`tar.gz` を展開した `tar` ファイルも指定できます。
**`-WslDistroName` の指定が必要です。**

使用例:

```powershell
# release asset として取得した rootfs を使用してインポート
powershell -ExecutionPolicy Bypass -File .\import-wsl.ps1 -RootFsPath "D:\staging\oracle-linux-8-dev-vYYYYMMDD.x.x-wsl-rootfs.tar.gz" -WslDistroName "OracleLinux8-Dev"
```

### WslDistroName

WSL ディストリビューション名を指定します。必須です。

使用例:

```powershell
# カスタム名でインポート
powershell -ExecutionPolicy Bypass -File .\import-wsl.ps1 `
  -RootFsPath "D:\staging\oracle-linux-8-dev-vYYYYMMDD.x.x-wsl-rootfs.tar.gz" `
  -WslDistroName "OracleLinux-Custom"
```

### InstallLocation

インストール先ディレクトリを指定します (既定値: `$env:LOCALAPPDATA\WSL\<DistroName>`)。

使用例:

```powershell
# カスタムディレクトリにインストール
powershell -ExecutionPolicy Bypass -File .\import-wsl.ps1 `
  -RootFsPath "D:\staging\oracle-linux-8-dev-vYYYYMMDD.x.x-wsl-rootfs.tar.gz" `
  -WslDistroName "OracleLinux8-Dev" `
  -InstallLocation "D:\WSL\OracleLinux"
```

## 重要な注意事項

### オフラインインストールについて

- `RootFsPath` に指定するファイルは、WSL2 に `wsl --import` できる rootfs (`tar.gz` または `tar`) を想定しています。
- `RootFsPath` を使用してインストールする場合は、インポート先を明確にするため `-WslDistroName` を必ず指定してください。

### 既存のディストリビューションについて

同名の WSL ディストリビューションが既に登録されている場合、スクリプトは再作成方法を確認します。

```text
警告: 既存のディストリビューション 'OracleLinux8-Dev' が見つかりました

  このディストリビューションを削除すると、現在の登録は置き換えられます:
  - クリーン再作成を選択した場合、既存のホームディレクトリ内のデータは失われます
  - 移行を選択した場合、/home 配下を tar.gz 形式で圧縮退避してから復元します
  - /home ディレクトリ自体は置き換えず、配下のファイルとディレクトリを移行します

再作成方法を選択してください:
  [Enter] M : /home 配下を移行する
          C : クリーンな環境で再作成する
          N : キャンセルする
```

Enter または `M` を入力すると、`/home` 配下の内容を一時ディレクトリに `tar.gz` で退避してから、新しいディストリビューションの `/home` へ復元します。
`C` を入力すると移行せずにクリーンな環境として再作成します。
`N` を入力するとインポートをキャンセルします。

**重要**: 移行対象は `/home` ディレクトリそのものではなく、配下のファイルおよびディレクトリです。
重要なデータが存在する場合は、事前に追加バックアップを取得するか、異なる `WslDistroName` を指定してください。

### データのバックアップ方法

既存のディストリビューションをバックアップする場合のコマンド例です。

```powershell
# ディストリビューションをエクスポート
wsl --export OracleLinux8-Dev C:\backup\oracle-linux-backup.tar

# 後で復元する場合
wsl --import OracleLinux8-Dev-Restored C:\WSL\Restored C:\backup\oracle-linux-backup.tar
```

## 仕組み

1. **rootfs 指定**: `-RootFsPath` でローカルの `tar.gz` または `tar` を指定
2. **既存ホームの退避 (必要時)**: 同名ディストリビューションが存在し移行を選択した場合、`/home` 配下を `tar.gz` として一時ディレクトリへ圧縮退避
3. **WSL2 インポート**: `wsl.exe --import` でディストリビューションとして登録
4. **ホーム復元 (必要時)**: 退避した `tar.gz` を新しいディストリビューションの `/home` に展開
5. **動作確認**: 基本的なコマンドによる動作確認

## インポート後の使用方法

### ディストリビューションの起動

```powershell
# ディストリビューションを起動
wsl -d OracleLinux8-Dev

# 既定のディストリビューションに設定
wsl --set-default OracleLinux8-Dev

# 既定のディストリビューションとして起動
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

### Podman の利用

WSL rootfs には rootless Podman、Docker 互換の `docker`、および `podman-compose` が含まれます。
既定ユーザー `user` の UID/GID マッピングと cgroup 設定は事前設定済みです。

```bash
podman run --rm quay.io/podman/hello
docker --version
podman-compose --version
systemctl --user status podman.socket
```

Podman API socket を再度有効化する場合は、次のコマンドを実行します。

```bash
systemctl --user enable --now podman.socket
```

## 仮想ディスクの圧縮

WSL2 のディストリビューションは、ファイルシステムを Windows 上の仮想ディスクファイル `ext4.vhdx` に保存します。
このファイルはデータの書き込みに応じて大きくなりますが、Linux 側でファイルを削除しても自動的には小さくなりません。
ビルドやパッケージの更新を繰り返すと、実際の使用量より大きな領域を Windows のドライブ上で占有し続けます。

`compact-wsl.ps1` は、この未使用領域を解放して `ext4.vhdx` のサイズを縮小するスクリプトです。

### 圧縮の仕組み

スクリプトは次の 3 段階で処理します。

1. **未使用ブロックの解放 (fstrim)**: ディストリビューション内で root として `fstrim -v /` を実行します。fstrim は、ファイルシステム上で使われていないブロックを仮想ディスクへ通知するコマンドです。通知を受けた仮想ディスクは該当ブロックを未割り当てとして扱い、以降はゼロとして読み出します。ゼロを書き込むゼロフィルと同じ効果を、実際の書き込みを行わずに得られます。
2. **WSL2 の停止 (wsl --shutdown)**: `ext4.vhdx` を使用中のままでは圧縮できないため、WSL2 の仮想マシンを停止します。停止後、ファイルの使用が終わるまで最大 60 秒待機します。
3. **仮想ディスクの圧縮 (diskpart)**: Windows 標準のディスク管理コマンド `diskpart` で `ext4.vhdx` を読み取り専用でアタッチし、`compact vdisk` で未割り当てブロックをファイルから取り除きます。完了後にデタッチします。

`diskpart` が実行するコマンドは次のとおりです。

```text
select vdisk file="C:\Users\<ユーザー名>\AppData\Local\WSL\OracleLinux8-Dev\ext4.vhdx"
attach vdisk readonly
compact vdisk
detach vdisk
exit
```

圧縮対象の `ext4.vhdx` のパスは、WSL の登録情報 (レジストリの `HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss`) から自動的に取得します。
Hyper-V の `Optimize-VHD` コマンドレットでも同じ圧縮ができますが、Hyper-V 管理ツールが必要で Windows Home エディションでは使用できません。
このスクリプトは、どのエディションでも利用できる `diskpart` を使用します。

### 使用方法

`diskpart` の実行には管理者権限が必要です。
PowerShell を **管理者として実行** し、圧縮するディストリビューション名を指定します。

```powershell
# スクリプトをダウンロード
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/hondarer/oracle-linux-container/main/examples/import-wsl/compact-wsl.ps1" `
  -OutFile ".\compact-wsl.ps1"

# OL8 のディストリビューションを圧縮
powershell -ExecutionPolicy Bypass -File .\compact-wsl.ps1 -WslDistroName "OracleLinux8-Dev"
```

実行すると、仮想ディスクのパス・処理前のサイズ・処理内容を表示し、`wsl --shutdown` を実行してよいか確認します。
`y` を入力すると処理を開始し、終了時に処理前後のディスク上サイズと削減量を表示します。

```text
  処理前のディスク上サイズ : 18.42 GB
  処理後のディスク上サイズ : 9.87 GB
  削減量                   : 8.55 GB
```

上記の数値は表示形式を示す例です。削減量は、削除したファイルの量や仮想ディスク内の断片化の状況によって変わります。

### compact-wsl.ps1 のパラメータ

| パラメータ | 説明 |
|------------|------|
| `-WslDistroName` | 圧縮するディストリビューション名 (必須)。`wsl --list --verbose` で確認できます。 |
| `-SkipTrim` | fstrim を実行せずに、停止と圧縮だけを行います。直前に手動で fstrim を実行済みの場合に使用します。 |
| `-Force` | `wsl --shutdown` 前の確認を省略します。タスクスケジューラーなどから無人で実行する場合に使用します。 |

### 手動で実行する場合

スクリプトを使わずに同じ処理を行う手順です。

```powershell
# 1. 未使用ブロックを解放 (通常の PowerShell でも実行可)
wsl -d OracleLinux8-Dev -u root -- fstrim -v /

# 2. WSL2 を停止
wsl --shutdown

# 3. 管理者の PowerShell で diskpart を起動し、前述のコマンドを入力
diskpart
```

### 圧縮時の注意事項

- `wsl --shutdown` は、圧縮対象以外も含めて実行中のすべての WSL2 ディストリビューションを停止します。VS Code の WSL 接続や Docker Desktop など、WSL2 を利用するアプリケーションも停止するため、作業中のデータを保存してから実行してください。
- 圧縮中に `ext4.vhdx` を使用すると失敗します。完了するまで `wsl` コマンドや WSL2 を利用するアプリケーションを起動しないでください。
- `compact vdisk` は読み取り専用でアタッチして実行するため、ファイルシステムの内容は変更しません。ただし、重要なデータがある場合は、事前に [データのバックアップ方法](#データのバックアップ方法) に従ってエクスポートしておくことを推奨します。
- スパース VHD (`wsl --manage <ディストリビューション名> --set-sparse true` で設定) が有効な場合は、fstrim の時点で Windows 側の領域が解放されるため、スクリプトは `diskpart` による圧縮を省略します。スパースファイルはファイルサイズの表示が変わらないため、スクリプトはディスク上の実サイズで処理前後を比較します。
- 圧縮後のファイルサイズは、ディストリビューション内の使用量 (`df -h /` の Used) より大きくなる場合があります。仮想ディスク内でデータが分散して配置されていると、ブロック単位でしか解放できないためです。

## トラブルシューティング

### WSL2 が利用できない

```powershell
# WSL のバージョン確認
wsl --version

# WSL2 をインストール (既定のディストリビューションは含めない)
wsl --install --no-distribution
```

> **Hyper-V ゲストの Windows で WSL2 を使用する場合**
>
> Hyper-V 上の仮想マシンで Windows を実行している場合、WSL2 を有効にするにはホスト側でネスト仮想化 (ExposeVirtualizationExtensions) を有効にする必要があります。
> 対象の仮想マシンをシャットダウンした後、**ホスト** の PowerShell で次を実行してください。
>
> ```powershell
> # 現在の設定を確認 (ホストで実行)
> Get-VMProcessor -VMName * | ft VMName,ExposeVirtualizationExtensions
>
> # ネスト仮想化を有効化 (ホストで実行、<VMName> は対象 VM 名に変更)
> Set-VMProcessor -VMName <VMName> -ExposeVirtualizationExtensions $true
> ```
>
> 設定後、仮想マシンを起動して再度 WSL2 のインストールを実行してください。

### ダウンロードが失敗する

- インターネット接続を確認してください。
- GitHub Releases から取得する場合は、release asset が完全にダウンロードされているか確認してください。
- プロキシ環境の場合、PowerShell のプロキシ設定を確認してください。

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

# 再度インポート (release asset を使用する標準手順)
powershell -ExecutionPolicy Bypass -File .\import-wsl.ps1 -RootFsPath "D:\staging\oracle-linux-8-dev-vYYYYMMDD.x.x-wsl-rootfs.tar.gz" -WslDistroName "OracleLinux8-Dev"
```

## アンインストール

```powershell
# ディストリビューションを削除
wsl --unregister OracleLinux8-Dev

# インストールディレクトリを削除 (任意)
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\WSL\OracleLinux8-Dev"

# 一時ファイルを削除
Remove-Item -Recurse -Force "$env:TEMP\wsl-import-*"
```

## 技術仕様

### 使用する Windows 標準機能

- **PowerShell**
- **wsl.exe**: WSL2 管理コマンド
- **diskpart.exe**: ディスク管理コマンド (`compact-wsl.ps1` による仮想ディスクの圧縮で使用)

### WSL2 インポート形式

release asset の rootfs は `tar.gz` 形式で、`wsl --import` コマンドで直接インポート可能です。
`wsl --import` は `tar.gz` / `tar` の両形式を自動判別するため、`tar.gz` を展開した `tar` ファイルを `-RootFsPath` に指定してインポートすることもできます。

## 関連リンク

- [プロジェクトルート README](../../README.md)
- [GitHub Releases](https://github.com/hondarer/oracle-linux-container/releases)
- [WSL ドキュメント](https://learn.microsoft.com/ja-jp/windows/wsl/)

## ライセンス

このスクリプトは MIT License で提供されています。
詳細は [LICENSE](../../LICENSE) を参照してください。

インポートされるコンテナイメージは GPL-2.0、GPL-3.0-or-later、Apache-2.0、LGPL-2.1-or-later、MIT 等の複合ライセンスのコンポーネントから構成されています。
詳細は [src/LICENSE-IMAGE](../../src/LICENSE-IMAGE) (Oracle Linux ライセンス条項) および [src/NOTICE](../../src/NOTICE) を参照してください。
