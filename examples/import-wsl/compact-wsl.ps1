# WSL2 ディストリビューションの仮想ディスク (ext4.vhdx) を圧縮する PowerShell スクリプト
#
# このスクリプトは、次の手順で ext4.vhdx のファイルサイズを縮小します。
# 1. ディストリビューション内で fstrim を実行し、未使用ブロックを仮想ディスクへ通知する
# 2. wsl --shutdown で WSL2 を停止し、ext4.vhdx の使用を終了させる
# 3. diskpart の compact vdisk で ext4.vhdx を圧縮する
#
# 前提条件:
# - Windows 10 バージョン 2004 以降 (ビルド 19041 以降) または Windows 11
# - WSL2 ディストリビューションとして登録済み
# - 管理者として実行した PowerShell (diskpart の実行に必要)
#
# 使用する Windows 標準機能:
# - PowerShell
# - wsl.exe (WSL2 管理コマンド)
# - diskpart.exe (ディスク管理コマンド)

param(
    [string]$WslDistroName = "",
    [switch]$SkipTrim,
    [switch]$Force
)

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

function Format-Size {
    param([long]$Bytes)
    return "$(($Bytes / 1GB).ToString('F2')) GB"
}

# =============================================================================
# 前提条件の確認
# =============================================================================

function Test-Administrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WslDistroInfo {
    param([string]$DistroName)

    # WSL のディストリビューション登録情報は HKCU の Lxss 配下に保存される
    $lxssKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
    if (-not (Test-Path $lxssKey)) {
        throw "WSL ディストリビューションの登録情報が見つかりません: $lxssKey"
    }

    $entry = Get-ChildItem $lxssKey |
        ForEach-Object { Get-ItemProperty $_.PSPath } |
        Where-Object { $_.DistributionName -eq $DistroName } |
        Select-Object -First 1
    if ($null -eq $entry) {
        throw "ディストリビューション '$DistroName' が登録されていません。'wsl --list --verbose' で名前を確認してください。"
    }

    if ($entry.Version -ne 2) {
        throw "ディストリビューション '$DistroName' は WSL2 ではありません。WSL1 は仮想ディスクを使用しないため圧縮できません。"
    }

    # BasePath は '\\?\C:\...' 形式で保存される場合がある
    $basePath = ([string]$entry.BasePath) -replace '^\\\\\?\\', ''
    $vhdFileName = [string]$entry.VhdFileName
    if ([string]::IsNullOrEmpty($vhdFileName)) {
        $vhdFileName = "ext4.vhdx"
    }

    $vhdPath = Join-Path $basePath $vhdFileName
    if (-not (Test-Path -LiteralPath $vhdPath -PathType Leaf)) {
        throw "仮想ディスクが見つかりません: $vhdPath"
    }

    return $vhdPath
}

function Get-SizeOnDisk {
    param([string]$Path)

    # スパースファイルはファイルサイズ (Length) が変わらないため、ディスク上の実サイズを取得する
    if (-not ("CompactWsl.NativeMethods" -as [type])) {
        Add-Type -Namespace CompactWsl -Name NativeMethods -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern uint GetCompressedFileSizeW(string lpFileName, out uint lpFileSizeHigh);
'@
    }

    $high = [uint32]0
    $low = [CompactWsl.NativeMethods]::GetCompressedFileSizeW($Path, [ref]$high)
    if ($low -eq [uint32]::MaxValue) {
        $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($errorCode -ne 0) {
            throw "ディスク上のサイズを取得できません: $Path (エラーコード: $errorCode)"
        }
    }

    return ([long]$high -shl 32) + [long]$low
}

function Test-SparseFile {
    param([string]$Path)

    $attributes = (Get-Item -LiteralPath $Path).Attributes
    return (($attributes -band [System.IO.FileAttributes]::SparseFile) -ne 0)
}

# =============================================================================
# 圧縮処理
# =============================================================================

function Invoke-WslCommand {
    param(
        [string]$DistroName,
        [string[]]$Arguments
    )

    # Windows PowerShell 5.1 では、Stop のままネイティブコマンドの標準エラーをリダイレクトすると例外になる
    $ErrorActionPreference = "Continue"

    # Linux 側コマンドの出力 (UTF-8) を文字化けさせずに表示する
    $previousEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        & wsl.exe -d $DistroName -u root -- @Arguments 2>&1 | ForEach-Object { Write-Info "$_" }
        return $LASTEXITCODE
    } finally {
        [Console]::OutputEncoding = $previousEncoding
    }
}

function Invoke-Fstrim {
    param([string]$DistroName)

    Write-Step "未使用ブロックを解放中 (fstrim)"

    $exitCode = Invoke-WslCommand -DistroName $DistroName -Arguments @("fstrim", "-v", "/")
    if ($exitCode -ne 0) {
        throw "fstrim の実行に失敗しました (終了コード: $exitCode)"
    }

    Write-Success "fstrim が完了しました"
}

function Stop-Wsl {
    Write-Step "WSL2 を停止中 (wsl --shutdown)"

    & wsl.exe --shutdown
    if ($LASTEXITCODE -ne 0) {
        throw "wsl --shutdown に失敗しました (終了コード: $LASTEXITCODE)"
    }

    Write-Success "WSL2 を停止しました"
}

function Wait-VhdUnlocked {
    param(
        [string]$Path,
        [int]$TimeoutSeconds = 60
    )

    # wsl --shutdown 直後は仮想ディスクの使用が終わっていない場合があるため、
    # 排他的に開けるようになるまで待機する
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        try {
            $stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'None')
            $stream.Close()
            return
        } catch {
            if ((Get-Date) -ge $deadline) {
                throw "仮想ディスクが使用中のままです: $Path (WSL2 を使用するアプリケーションが動作していないか確認してください)"
            }
            Start-Sleep -Seconds 2
        }
    }
}

function Invoke-Diskpart {
    param([string[]]$Commands)

    # diskpart はスクリプトファイルをシステムの ANSI コードページで読み込むため、
    # 日本語を含むパスも扱えるよう同じコードページで書き出す
    $scriptPath = Join-Path $env:TEMP "compact-wsl-$(Get-Date -Format 'yyyyMMddHHmmss').txt"
    $ansiCodePage = [int](Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage").ACP
    $encoding = [System.Text.Encoding]::GetEncoding($ansiCodePage)
    [System.IO.File]::WriteAllLines($scriptPath, $Commands, $encoding)

    $ErrorActionPreference = "Continue"
    try {
        & diskpart.exe /s $scriptPath 2>&1 | ForEach-Object { Write-Info "$_" }
        return $LASTEXITCODE
    } finally {
        Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
    }
}

function Compress-Vhd {
    param([string]$Path)

    Write-Step "仮想ディスクを圧縮中 (diskpart compact vdisk)"
    Write-Info "サイズによっては数分以上かかります"

    $exitCode = Invoke-Diskpart -Commands @(
        "select vdisk file=`"$Path`"",
        "attach vdisk readonly",
        "compact vdisk",
        "detach vdisk",
        "exit"
    )

    if ($exitCode -ne 0) {
        # diskpart はエラー発生時点でスクリプトを中断するため、アタッチ済みの場合に備えてデタッチする
        Invoke-Diskpart -Commands @(
            "select vdisk file=`"$Path`"",
            "detach vdisk noerr",
            "exit"
        ) | Out-Null
        throw "diskpart による圧縮に失敗しました (終了コード: $exitCode)"
    }

    Write-Success "圧縮が完了しました"
}

# =============================================================================
# メイン処理
# =============================================================================

function Main {
    Write-Host ""
    Write-Output "========================================"
    Write-Output "  WSL2 仮想ディスク圧縮ツール"
    Write-Output "  Oracle Linux 開発環境"
    Write-Output "========================================"
    Write-Host ""

    try {
        # 前提条件の確認
        Write-Step "前提条件をチェック中"

        if ([string]::IsNullOrEmpty($WslDistroName)) {
            throw "圧縮するディストリビューションを -WslDistroName で指定してください"
        }

        # fstrim と wsl --shutdown を実行した後に diskpart が使えないと圧縮できないため、先に確認する
        if (-not (Test-Administrator)) {
            throw "diskpart の実行には管理者権限が必要です。PowerShell を管理者として実行してください。"
        }
        Write-Success "管理者権限で実行されています"

        $vhdPath = Get-WslDistroInfo -DistroName $WslDistroName
        $sizeBefore = Get-SizeOnDisk -Path $vhdPath
        $isSparse = Test-SparseFile -Path $vhdPath
        Write-Success "仮想ディスクを確認しました"

        # パラメータ表示
        Write-Host ""
        Write-Host "設定:"
        Write-Host "  WSL ディストリ名 : $WslDistroName"
        Write-Host "  仮想ディスク     : $vhdPath"
        Write-Host "  ディスク上サイズ : $(Format-Size $sizeBefore)"
        Write-Host "  スパース VHD     : $(if ($isSparse) { '有効' } else { '無効' })"
        Write-Host "  fstrim           : $(if ($SkipTrim) { 'スキップ' } else { '実行' })"
        Write-Host ""

        if (-not $Force) {
            Write-WarningMsg "警告: wsl --shutdown により、実行中のすべての WSL2 ディストリビューションが停止します"
            Write-Host "  - 作業中のファイルを保存し、WSL2 上のアプリケーションを終了してください"
            Write-Host "  - Docker Desktop など WSL2 を使用するアプリケーションも停止します"
            Write-Host ""
            $response = ([string](Read-Host "続行しますか? [y/N]")).Trim().ToLowerInvariant()
            if ($response -ne "y") {
                Write-Host "キャンセルしました。"
                return
            }
        }

        if (-not $SkipTrim) {
            Invoke-Fstrim -DistroName $WslDistroName
        }

        Stop-Wsl
        Wait-VhdUnlocked -Path $vhdPath

        if ($isSparse) {
            # スパース VHD は fstrim の時点でホスト側の領域が解放されるため、diskpart による圧縮は行わない
            Write-Step "仮想ディスクの圧縮をスキップ"
            Write-Info "スパース VHD が有効なため、fstrim の時点で未使用領域が解放されています"
        } else {
            Compress-Vhd -Path $vhdPath
        }

        # 結果表示
        $sizeAfter = Get-SizeOnDisk -Path $vhdPath
        Write-Host ""
        Write-Output "========================================"
        Write-Output "  処理が完了しました"
        Write-Output "========================================"
        Write-Host ""
        Write-Host "  処理前のディスク上サイズ : $(Format-Size $sizeBefore)"
        Write-Host "  処理後のディスク上サイズ : $(Format-Size $sizeAfter)"
        Write-Host "  削減量                   : $(Format-Size ($sizeBefore - $sizeAfter))"
        Write-Host ""

    } catch {
        Write-Host ""
        Write-ErrorMsg "エラーが発生しました: $_"
        Write-Host ""
        Write-Host "トラブルシューティング:"
        Write-Host "  - PowerShell を管理者として実行しているか確認してください"
        Write-Host "  - 'wsl --list --verbose' でディストリビューション名を確認してください"
        Write-Host "  - WSL2 を使用するアプリケーション (エディター、Docker Desktop など) を終了してください"
        Write-Host ""
        exit 1
    }
}

# スクリプトの実行
Main
