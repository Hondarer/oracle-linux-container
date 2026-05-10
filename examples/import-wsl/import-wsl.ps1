# Oracle Linux 開発環境を WSL2 にインポートする PowerShell スクリプト
#
# このスクリプトは、GitHub Releases から取得した WSL2 用 rootfs (tar.gz) を使って、
# WSL2 ディストリビューションとしてインポートします。
#
# 前提条件:
# - Windows 10 (1803以降) または Windows 11
# - WSL2 がインストール済み
#
# 使用する Windows 標準機能:
# - PowerShell
# - wsl.exe (WSL2 管理コマンド)

param(
    [string]$RootFsPath = "",
    [string]$WslDistroName = "",
    [string]$InstallLocation = "",
    [string]$TempDir = "$env:TEMP\wsl-import-$(Get-Date -Format 'yyyyMMddHHmmss')"
)

$hasExplicitWslDistroName = $PSBoundParameters.ContainsKey('WslDistroName')

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # 進捗表示を無効化して高速化

# =============================================================================
# 出力関数
# =============================================================================

function Write-Output {
    param(
        [string]$Message,
        [string]$Color = ""
    )

    if ([string]::IsNullOrEmpty($Color)) {
        Write-Host $Message
    } else {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Write-Step {
    param([string]$Message)
    Write-Output "`n==> $Message"
}

function Write-Success {
    param([string]$Message)
    Write-Output "[OK] $Message"
}

function Write-WarningMsg {
    param([string]$Message)
    Write-Output $Message "Yellow"
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Output "[ERROR] $Message" "Red"
}

function Write-Info {
    param([string]$Message)
    Write-Host "    $Message"
}

# =============================================================================
# パス・シェル補助関数
# =============================================================================

function Convert-WindowsPathToWslPath {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ($fullPath -match '^([A-Za-z]):\\(.*)$') {
        $driveLetter = $matches[1].ToLowerInvariant()
        $pathSuffix = $matches[2] -replace '\\', '/'
        return "/mnt/$driveLetter/$pathSuffix"
    }

    throw "WSL から参照できない Windows パスです: $fullPath"
}

function Resolve-RootFsPath {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "指定された rootfs ファイルが見つかりません: $fullPath"
    }

    return $fullPath
}

function Get-RootFsFromLocalFile {
    param([string]$Path)

    Write-Step "ローカル rootfs を確認中"

    $resolvedPath = Resolve-RootFsPath -Path $Path
    $size = (Get-Item -LiteralPath $resolvedPath).Length / 1MB

    Write-Info "ローカル rootfs: $resolvedPath"
    Write-Info "ファイルサイズ: $($size.ToString('F2')) MB"
    Write-Success "ローカル rootfs を使用します"

    return $resolvedPath
}

# =============================================================================
# WSL2 インポート
# =============================================================================

function Prompt-ReimportMode {
    param([string]$DistroName)

    Write-Host ""
    Write-WarningMsg "警告: 既存のディストリビューション '$DistroName' が見つかりました"
    Write-Host ""
    Write-WarningMsg "  このディストリビューションを削除すると、現在の登録は置き換えられます:"
    Write-Host "  - クリーン再作成を選ぶと、既存のホームディレクトリ内データは失われます"
    Write-Host "  - 移行を選ぶと、/home 配下を tar.gz で圧縮退避してから復元します"
    Write-Host "  - /home ディレクトリ自体は置き換えず、配下のファイルとディレクトリを移行します"
    Write-Host ""
    Write-Host "再作成方法を選択してください:"
    Write-Host "  [Enter] M : /home 配下を移行する"
    Write-Host "          C : クリーンな環境で再作成する"
    Write-Host "          N : キャンセルする"

    while ($true) {
        $response = ([string](Read-Host "選択してください [M/c/n]")).Trim().ToLowerInvariant()
        switch ($response) {
            "" { return "migrate" }
            "m" { return "migrate" }
            "c" { return "clean" }
            "n" { return "cancel" }
            default {
                Write-WarningMsg "M、C、N のいずれかを入力してください。"
            }
        }
    }
}

function Backup-WslHomeContents {
    param(
        [string]$DistroName,
        [string]$BackupArchivePath
    )

    Write-Step "既存の /home 配下を退避中"

    $backupDir = Split-Path -Path $BackupArchivePath -Parent
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    if (Test-Path $BackupArchivePath) {
        Remove-Item -Path $BackupArchivePath -Force
    }

    $backupArchiveWslPath = Convert-WindowsPathToWslPath -Path $BackupArchivePath
    wsl -d $DistroName -u root -- tar -czf $backupArchiveWslPath -C /home .
    if ($LASTEXITCODE -ne 0) {
        throw "/home 配下の圧縮退避に失敗しました (終了コード: $LASTEXITCODE)"
    }

    if (-not (Test-Path $BackupArchivePath)) {
        throw "退避アーカイブが作成されませんでした: $BackupArchivePath"
    }

    $size = (Get-Item $BackupArchivePath).Length / 1MB
    Write-Success "/home 配下を退避しました: $($size.ToString('F2')) MB"
    Write-Info "退避アーカイブ: $BackupArchivePath"
}

function Restore-WslHomeContents {
    param(
        [string]$DistroName,
        [string]$BackupArchivePath
    )

    Write-Step "退避した /home 配下を復元中"

    if (-not (Test-Path $BackupArchivePath)) {
        throw "復元に必要な退避アーカイブが見つかりません: $BackupArchivePath"
    }

    $backupArchiveWslPath = Convert-WindowsPathToWslPath -Path $BackupArchivePath
    wsl -d $DistroName -u root -- tar -xzf $backupArchiveWslPath -C /home
    if ($LASTEXITCODE -ne 0) {
        throw "/home 配下の復元に失敗しました (終了コード: $LASTEXITCODE)"
    }

    Write-Success "/home 配下を復元しました"
}

function Import-ToWSL2 {
    param(
        [string]$DistroName,
        [string]$InstallLocation,
        [string]$RootFsTarGz,
        [string]$TempDir
    )

    Write-Step "WSL2 にインポート中"

    $backupArchivePath = $null

    # 既存のディストリビューションを確認
    $existingDistros = wsl --list --quiet 2>$null
    if ($existingDistros -contains $DistroName) {
        $reimportMode = Prompt-ReimportMode -DistroName $DistroName
        switch ($reimportMode) {
            "migrate" {
                $backupArchivePath = Join-Path $TempDir "home-contents-backup.tar.gz"
                Backup-WslHomeContents -DistroName $DistroName -BackupArchivePath $backupArchivePath
            }
            "clean" {
                Write-Info "クリーンな環境で再作成します"
            }
            default {
                throw "インポートがキャンセルされました"
            }
        }

        Write-Info "既存のディストリビューションを削除中..."
        wsl --unregister $DistroName
        if ($LASTEXITCODE -ne 0) {
            throw "既存のディストリビューションの削除に失敗しました (終了コード: $LASTEXITCODE)"
        }
        Write-Success "削除しました"
    }

    # インストール先ディレクトリの作成
    if (-not (Test-Path $InstallLocation)) {
        New-Item -ItemType Directory -Path $InstallLocation -Force | Out-Null
    }

    # WSL2 にインポート
    Write-Info "インポート中: $DistroName"
    Write-Info "インストール先: $InstallLocation"

    wsl --import $DistroName $InstallLocation $RootFsTarGz

    if ($LASTEXITCODE -eq 0) {
        Write-Success "WSL2 へのインポートが完了しました"

        if ($backupArchivePath) {
            Restore-WslHomeContents -DistroName $DistroName -BackupArchivePath $backupArchivePath
        }
    } else {
        throw "WSL2 へのインポートに失敗しました (終了コード: $LASTEXITCODE)"
    }
}

# =============================================================================
# WSL ディストリビューションのテスト
# =============================================================================

function Test-WslDistro {
    param([string]$DistroName)

    Write-Step "ディストリビューションをテスト中"

    Write-Info "OS 情報を取得中..."
    $osInfo = @(wsl -d $DistroName grep "^PRETTY_NAME=" /etc/os-release 2>&1)
    Write-Host $osInfo[0]

    Write-Info "Node.js バージョンを確認中..."
    $nodeVersion = @(wsl -d $DistroName node --version 2>&1)
    Write-Host $nodeVersion[0]

    Write-Info "Java バージョンを確認中..."
    $javaVersion = @(wsl -d $DistroName java --version 2>&1)
    Write-Host $javaVersion[0]

    Write-Success "ディストリビューションが正常に動作しています"
}

# =============================================================================
# メイン処理
# =============================================================================

function Main {
    Write-Host ""
    Write-Output "========================================"
    Write-Output "  WSL2 インポートツール"
    Write-Output "  Oracle Linux 開発環境"
    Write-Output "========================================"
    Write-Host ""

    # パラメータ表示
    Write-Host "設定:"
    Write-Host "  ローカル rootfs  : $RootFsPath"
    Write-Host "  WSL ディストリ名 : $WslDistroName"
    Write-Host "  インストール先   : $InstallLocation"
    Write-Host "  一時ディレクトリ : $TempDir"
    Write-Host ""

    try {
        # 前提条件チェック
        Write-Step "前提条件をチェック中"

        # WSL2 の確認
        $wslVersion = wsl --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "WSL2 がインストールされていません。'wsl --install' を実行してください。"
        }
        Write-Success "WSL2 が利用可能です"

        # 一時ディレクトリの作成
        Write-Step "作業環境を準備中"
        if (-not (Test-Path $TempDir)) {
            New-Item -ItemType Directory -Path $TempDir | Out-Null
        }
        Write-Success "一時ディレクトリを作成しました: $TempDir"

        if ([string]::IsNullOrEmpty($RootFsPath)) {
            throw "rootfs ファイルのパスを -RootFsPath で指定してください。GitHub Releases から WSL 用 rootfs (tar.gz) をダウンロードして指定してください。"
        }
        if (-not $hasExplicitWslDistroName) {
            throw "RootFsPath を使ってインストールする場合は -WslDistroName を指定してください"
        }
        if ([string]::IsNullOrEmpty($InstallLocation) -and -not [string]::IsNullOrEmpty($WslDistroName)) {
            $InstallLocation = "$env:LOCALAPPDATA\WSL\$WslDistroName"
        }

        $rootfsTarGz = Get-RootFsFromLocalFile -Path $RootFsPath

        # WSL2 へのインポート
        Import-ToWSL2 `
            -DistroName $WslDistroName `
            -InstallLocation $InstallLocation `
            -RootFsTarGz $rootfsTarGz `
            -TempDir $TempDir

        # テスト実行
        Test-WslDistro -DistroName $WslDistroName

        # 完了メッセージ
        Write-Host ""
        Write-Output "========================================"
        Write-Output "  インポートが完了しました！"
        Write-Output "========================================"
        Write-Host ""
        Write-Host "次のコマンドでディストリビューションを起動できます:"
        Write-Output "  wsl -d $WslDistroName"
        Write-Host ""
        Write-Host "デフォルトのディストリビューションに設定する場合:"
        Write-Output "  wsl --set-default $WslDistroName"
        Write-Host ""
        Write-Host "WSL 用 rootfs には既定ユーザー 'user' が事前作成されています。"
        Write-Host ""

    } catch {
        Write-Host ""
        Write-ErrorMsg "エラーが発生しました: $_"
        Write-Host ""
        Write-Host "トラブルシューティング:"
        Write-Host "  - RootFsPath で指定した rootfs ファイルが存在するか確認してください"
        Write-Host "  - 持ち込んだ rootfs が WSL 用 tar.gz であることを確認してください"
        Write-Host "  - RootFsPath を使う場合は -WslDistroName を指定してください"
        Write-Host "  - WSL2 が正しくインストールされているか確認してください"
        Write-Host ""
        exit 1
    } finally {
        # クリーンアップの提案
        if (Test-Path $TempDir) {
            Write-Host ""
            Write-Host "一時ファイルをクリーンアップする場合:"
            Write-Output "  Remove-Item -Recurse -Force '$TempDir'"
            Write-Host ""
        }
    }
}

# スクリプト実行
Main
