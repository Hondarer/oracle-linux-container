# Oracle Linux 開発環境を WSL2 にインポートする PowerShell スクリプト
#
# このスクリプトは、GitHub Container Registry (ghcr.io) から
# OCI Artifact として公開されている WSL2 rootfs をダウンロードするか、
# 事前に取得したローカルの WSL rootfs (tar.gz) を使用して、
# WSL2 ディストリビューションとしてインポートします。
#
# 前提条件:
# - Windows 10 (1803以降) または Windows 11
# - WSL2 がインストール済み
# - インターネット接続 (レジストリから取得する場合)
#
# 使用する Windows 標準機能:
# - PowerShell (Invoke-RestMethod, Invoke-WebRequest)
# - wsl.exe (WSL2 管理コマンド)

param(
    [string]$OLVersion = "8",
    [string]$Tag = "latest-wsl",
    [string]$ImageUrl = "",
    [string]$RootFsPath = "",
    [switch]$DownloadOnly,
    [string]$RootFsOutputPath = "",
    [string]$WslDistroName = "",
    [string]$InstallLocation = "",
    [string]$TempDir = "$env:TEMP\wsl-import-$(Get-Date -Format 'yyyyMMddHHmmss')"
)

$hasExplicitWslDistroName = $PSBoundParameters.ContainsKey('WslDistroName')

# デフォルト値の設定
if ([string]::IsNullOrEmpty($WslDistroName) -and [string]::IsNullOrEmpty($RootFsPath)) {
    $WslDistroName = "OracleLinux${OLVersion}-Dev"
}
if ([string]::IsNullOrEmpty($InstallLocation) -and -not [string]::IsNullOrEmpty($WslDistroName)) {
    $InstallLocation = "$env:LOCALAPPDATA\WSL\$WslDistroName"
}
if ([string]::IsNullOrEmpty($ImageUrl) -and [string]::IsNullOrEmpty($RootFsPath)) {
    $ImageUrl = "ghcr.io/hondarer/oracle-linux-container/oracle-linux-${OLVersion}-dev:$Tag"
}

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

function Resolve-RootFsOutputPath {
    param(
        [string]$Path,
        [string]$TempDir
    )

    $fullPath = if ([string]::IsNullOrEmpty($Path)) {
        Join-Path $TempDir "wsl-rootfs.tar.gz"
    } else {
        [System.IO.Path]::GetFullPath($Path)
    }

    $parentDir = Split-Path -Path $fullPath -Parent
    if (-not [string]::IsNullOrEmpty($parentDir) -and -not (Test-Path -LiteralPath $parentDir -PathType Container)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $fullPath) {
        throw "rootfs の出力先ファイルが既に存在します: $fullPath"
    }

    return $fullPath
}

# イメージ URL 解析
# =============================================================================

function Parse-ImageUrl {
    param([string]$Url)

    # ghcr.io/owner/repo/image:tag 形式を解析
    if ($Url -match '^(?:([^/]+)/)?(.+?):(.+)$') {
        $registry = if ($matches[1]) { $matches[1] } else { "ghcr.io" }
        $image = $matches[2]
        $tag = $matches[3]
    } elseif ($Url -match '^(?:([^/]+)/)?(.+)$') {
        $registry = if ($matches[1]) { $matches[1] } else { "ghcr.io" }
        $image = $matches[2]
        $tag = "latest-wsl"
    } else {
        throw "無効なイメージ URL 形式: $Url"
    }

    return @{
        Registry = $registry
        Image = $image
        Tag = $tag
        Full = "$registry/$image`:$tag"
    }
}

# =============================================================================
# OCI Registry API v2 認証
# =============================================================================

function Get-RegistryToken {
    param(
        [string]$Registry,
        [string]$Image
    )

    Write-Info "認証トークンを取得中..."

    try {
        $tokenUrl = "https://$Registry/token?service=$Registry&scope=repository:$Image`:pull"
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Get -ContentType "application/json"

        if ($response.token) {
            Write-Success "認証トークンを取得しました"
            return $response.token
        } else {
            throw "トークンの取得に失敗しました"
        }
    } catch {
        Write-ErrorMsg "認証に失敗しました: $_"
        throw
    }
}

# =============================================================================
# マニフェスト取得
# =============================================================================

function Get-ArtifactManifest {
    param(
        [string]$Registry,
        [string]$Image,
        [string]$Tag,
        [string]$Token
    )

    Write-Info "マニフェストを取得中..."

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Accept" = "application/vnd.oci.image.manifest.v1+json"
    }

    $manifestUrl = "https://$Registry/v2/$Image/manifests/$Tag"

    try {
        $response = Invoke-RestMethod -Uri $manifestUrl -Method Get -Headers $headers
        Write-Success "マニフェストを取得しました"
        return $response
    } catch {
        Write-ErrorMsg "マニフェストの取得に失敗しました: $_"
        throw
    }
}

# =============================================================================
# Blob ダウンロード
# =============================================================================

function Download-Blob {
    param(
        [string]$Registry,
        [string]$Image,
        [string]$Token,
        [string]$Digest,
        [string]$OutputPath
    )

    $headers = @{
        "Authorization" = "Bearer $Token"
    }

    $blobUrl = "https://$Registry/v2/$Image/blobs/$Digest"
    $shortDigest = $Digest.Substring(0, 16)

    Write-Info "WSL rootfs をダウンロード中: $shortDigest..."

    try {
        Invoke-WebRequest -Uri $blobUrl -Method Get -Headers $headers -OutFile $OutputPath
        $size = (Get-Item $OutputPath).Length / 1MB
        Write-Success "ダウンロード完了: $($size.ToString('F2')) MB"
    } catch {
        Write-ErrorMsg "ダウンロード失敗: $_"
        throw
    }
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

function Get-RootFsFromRegistry {
    param(
        [string]$ImageUrl,
        [string]$TempDir,
        [string]$RootFsOutputPath
    )

    # イメージ URL の解析
    Write-Step "イメージ情報を解析中"
    $imageInfo = Parse-ImageUrl -Url $ImageUrl
    Write-Host "  レジストリ: $($imageInfo.Registry)"
    Write-Host "  イメージ  : $($imageInfo.Image)"
    Write-Host "  タグ      : $($imageInfo.Tag)"

    # 認証トークンの取得
    Write-Step "レジストリに接続中"
    $token = Get-RegistryToken -Registry $imageInfo.Registry -Image $imageInfo.Image

    # マニフェストの取得
    Write-Step "OCI Artifact マニフェストを取得中"
    $manifest = Get-ArtifactManifest `
        -Registry $imageInfo.Registry `
        -Image $imageInfo.Image `
        -Tag $imageInfo.Tag `
        -Token $token

    # レイヤー (WSL rootfs) の取得
    if (-not ($manifest.layers -and $manifest.layers.Count -gt 0)) {
        throw "マニフェストにレイヤーが含まれていません"
    }

    $layer = $manifest.layers[0]
    Write-Info "Rootfs サイズ: $([math]::Round($layer.size / 1MB, 2)) MB"
    Write-Info "Media Type: $($layer.mediaType)"

    $outputPath = Resolve-RootFsOutputPath -Path $RootFsOutputPath -TempDir $TempDir
    Write-Info "rootfs 保存先: $outputPath"

    # Rootfs のダウンロード
    Write-Step "WSL rootfs をダウンロード中"
    Download-Blob `
        -Registry $imageInfo.Registry `
        -Image $imageInfo.Image `
        -Token $token `
        -Digest $layer.digest `
        -OutputPath $outputPath

    return $outputPath
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
    wsl -d $DistroName cat /etc/os-release | Select-String "PRETTY_NAME"

    Write-Info "Node.js バージョンを確認中..."
    wsl -d $DistroName node --version

    Write-Info "Java バージョンを確認中..."
    wsl -d $DistroName java --version | Select-Object -First 1

    Write-Success "ディストリビューションが正常に動作しています"
}

# =============================================================================
# メイン処理
# =============================================================================

function Main {
    Write-Host ""
    Write-Output "========================================"
    Write-Output "  WSL2 インポートツール"
    Write-Output "  Oracle Linux $OLVersion 開発環境"
    Write-Output "========================================"
    Write-Host ""

    # パラメータ表示
    Write-Host "設定:"
    if ([string]::IsNullOrEmpty($RootFsPath)) {
        Write-Host "  イメージ URL     : $ImageUrl"
    } else {
        Write-Host "  ローカル rootfs  : $RootFsPath"
    }
    if (-not [string]::IsNullOrEmpty($RootFsOutputPath)) {
        Write-Host "  rootfs 出力先    : $RootFsOutputPath"
    }
    if ($DownloadOnly) {
        Write-Host "  ダウンロードのみ : 有効"
    }
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

        if ($DownloadOnly -and -not [string]::IsNullOrEmpty($RootFsPath)) {
            throw "DownloadOnly と RootFsPath は同時に指定できません"
        }
        if (-not [string]::IsNullOrEmpty($RootFsPath) -and -not [string]::IsNullOrEmpty($RootFsOutputPath)) {
            throw "RootFsPath と RootFsOutputPath は同時に指定できません"
        }
        if (-not [string]::IsNullOrEmpty($RootFsPath) -and -not $hasExplicitWslDistroName) {
            throw "RootFsPath を使ってインストールする場合は -WslDistroName を指定してください"
        }
        if ([string]::IsNullOrEmpty($InstallLocation) -and -not [string]::IsNullOrEmpty($WslDistroName)) {
            $InstallLocation = "$env:LOCALAPPDATA\WSL\$WslDistroName"
        }

        $rootfsTarGz = $null
        if ([string]::IsNullOrEmpty($RootFsPath)) {
            $rootfsTarGz = Get-RootFsFromRegistry `
                -ImageUrl $ImageUrl `
                -TempDir $TempDir `
                -RootFsOutputPath $RootFsOutputPath
        } else {
            if (-not [string]::IsNullOrEmpty($ImageUrl)) {
                Write-Info "RootFsPath が指定されているため ImageUrl は使用しません"
            }
            if ($Tag -ne "latest-wsl") {
                Write-Info "RootFsPath が指定されているため Tag は使用しません"
            }

            $rootfsTarGz = Get-RootFsFromLocalFile -Path $RootFsPath
        }

        if ($DownloadOnly) {
            Write-Host ""
            Write-Output "========================================"
            Write-Output "  WSL rootfs のダウンロードが完了しました"
            Write-Output "========================================"
            Write-Host ""
            Write-Host "保存した rootfs:"
            Write-Output "  $rootfsTarGz"
            Write-Host ""
            Write-Host "後でこの rootfs からインストールする場合:"
            Write-Output "  .\import-wsl.ps1 -RootFsPath `"$rootfsTarGz`" -WslDistroName `"OracleLinux${OLVersion}-Dev`""
            if ([System.IO.Path]::GetFullPath($rootfsTarGz).StartsWith([System.IO.Path]::GetFullPath($TempDir), [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Host ""
                Write-WarningMsg "  rootfs は一時ディレクトリ配下に保存されています。必要なら削除前に別の場所へ移動してください。"
            }
            Write-Host ""
            return
        }

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
        Write-Host "初回起動時はユーザーが作成されます。"
        Write-Host "環境変数で制御する場合:"
        Write-Output "  wsl -d $WslDistroName -e bash -c 'HOST_USER=myuser HOST_UID=1000 HOST_GID=1000 /entrypoint.sh'"
        Write-Host ""

    } catch {
        Write-Host ""
        Write-ErrorMsg "エラーが発生しました: $_"
        Write-Host ""
        Write-Host "トラブルシューティング:"
        if ([string]::IsNullOrEmpty($RootFsPath)) {
            Write-Host "  - インターネット接続を確認してください"
            Write-Host "  - イメージ URL が正しいか確認してください"
            if (-not [string]::IsNullOrEmpty($RootFsOutputPath)) {
                Write-Host "  - RootFsOutputPath の保存先が有効で、同名ファイルが存在しないか確認してください"
            }
        } else {
            Write-Host "  - RootFsPath で指定した rootfs ファイルが存在するか確認してください"
            Write-Host "  - 持ち込んだ rootfs が WSL 用 tar.gz であることを確認してください"
            Write-Host "  - RootFsPath を使う場合は -WslDistroName を指定してください"
        }
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
