param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('cn','ai')]
    [string]$Product,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$ToolDir = $PSScriptRoot
$DataDir = Join-Path $env:LOCALAPPDATA 'DualGuard'
$LogPath = Join-Path $DataDir 'logs\dg-launch.log'
$LogDir  = Split-Path $LogPath
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$IsoRoot = Join-Path $env:LOCALAPPDATA 'WB-Isolated'

function Write-Log([string]$msg) {
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Product, $msg
    Add-Content -Path $LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Get-RunKey {
    Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
}

function Find-CnExe {
    foreach ($p in @('D:\workbuddy\WorkBuddy.exe','E:\workbuddy\WorkBuddy.exe','C:\Program Files\WorkBuddy\WorkBuddy.exe')) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    $reg = Get-RunKey
    if ($reg) {
        foreach ($n in $reg.PSObject.Properties.Name) {
            if ($n -like '*WorkBuddy*') {
                $v = [string]$reg.$n
                if ($v -notlike '*WorkBuddyAI.exe') {
                    $v = $v.Trim('"')
                    if (Test-Path -LiteralPath $v) { return $v }
                }
            }
        }
    }
    return $null
}

function Find-AiExe {
    $reg = Get-RunKey
    if ($reg) {
        foreach ($n in $reg.PSObject.Properties.Name) {
            $v = [string]$reg.$n
            if ($v -like '*WorkBuddyAI.exe') {
                $v = $v.Trim('"')
                if (Test-Path -LiteralPath $v) { return $v }
            }
        }
    }
    foreach ($drive in @('F:\','D:\','E:\','G:\','C:\Program Files')) {
        if (-not (Test-Path -LiteralPath $drive)) { continue }
        $dirs = Get-ChildItem -LiteralPath $drive -Directory -ErrorAction SilentlyContinue
        foreach ($d in $dirs) {
            $cand = Join-Path $d.FullName 'WorkBuddyAI\WorkBuddyAI.exe'
            if (Test-Path -LiteralPath $cand) { return $cand }
        }
    }
    return $null
}

if ($Product -eq 'cn') { $Exe = Find-CnExe } else { $Exe = Find-AiExe }

if (-not $Exe) {
    Write-Log 'ERROR: executable not found, launch aborted'
    Write-Host ('ERROR: executable not found. See ' + $LogPath) -ForegroundColor Red
    exit 2
}

$AppTemp = Join-Path $IsoRoot (Join-Path $Product 'temp')
if (-not (Test-Path -LiteralPath $AppTemp)) {
    New-Item -ItemType Directory -Force -Path $AppTemp | Out-Null
}

$env:TMP = $AppTemp
$env:TEMP = $AppTemp

if ($DryRun) {
    Write-Host ('exe  : ' + $Exe)
    Write-Host ('temp : ' + $AppTemp)
    Write-Host ('iso  : isolated={0}' -f (Test-Path -LiteralPath $AppTemp))
    exit 0
}

Write-Log ('launch exe=' + $Exe + ' temp=' + $AppTemp)

try {
    Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -LiteralPath $Exe)
} catch {
    Write-Log ('ERROR: start failed - ' + $_.Exception.Message)
    exit 3
}
exit 0
