$ErrorActionPreference = 'Continue'

$ToolDir   = $PSScriptRoot
$DataDir   = Join-Path $env:LOCALAPPDATA 'DualGuard'
$SnapRoot  = Join-Path $DataDir 'snapshots'
$LogPath   = Join-Path $DataDir 'logs\dg-maintain.log'
foreach ($d in @($SnapRoot, (Split-Path $LogPath))) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}
$Sides     = @('cn','ai')
$Names     = @('workbuddy-update-x64','workbuddy-update-x64-workbuddy','workbuddy-update-x64-workbuddy-ai')
$ExcludeDirs = @('logs','traces','cache','binaries','plugins','app','Logs','Cache')

# 系统 TEMP（用户环境变量里的原值）。不能用 $env:TEMP：若本工具是从 WorkBuddy 会话内启动的，
# 进程继承的 TEMP 已被启动器改为隔离目录，会去清理/扫描错误的位置，甚至误删占位文件。
function Get-SysTemp {
    foreach ($t in @([Environment]::GetEnvironmentVariable('TEMP','User'), [Environment]::GetEnvironmentVariable('TEMP','Machine'))) {
        if ($t -and (Test-Path -LiteralPath $t)) { return $t.TrimEnd('\') }
    }
    return (Join-Path $env:LOCALAPPDATA 'Temp')
}
$SysTemp   = Get-SysTemp
$IsoRoot   = Join-Path $env:LOCALAPPDATA 'WB-Isolated'

function Log([string]$m) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m
    Add-Content -Path $LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Line($ch = '-') { Write-Host ($ch * 56) -ForegroundColor DarkGray }

function Get-AppProcs {
    Get-Process -Name 'WorkBuddy','WorkBuddyAI' -ErrorAction SilentlyContinue
}

function Show-Procs {
    $p = Get-AppProcs
    if (-not $p) { Write-Host '  进程: 两版均未运行  [OK]' -ForegroundColor Green; return }
    $g = $p | Group-Object ProcessName
    $txt = ($g | ForEach-Object { $_.Name + ' x' + $_.Count }) -join ', '
    Write-Host ('  进程: ' + $txt + '  [仍在运行]') -ForegroundColor Yellow
}

function Wait-AllClosed {
    while ($true) {
        $p = Get-AppProcs
        if (-not $p) { Write-Host '  检查通过：两个客户端均已退出。' -ForegroundColor Green; return $true }
        $g = $p | Group-Object ProcessName
        Write-Host ''
        Write-Host '  仍有进程在运行：' -ForegroundColor Red
        foreach ($x in $g) { Write-Host ('    ' + $x.Name + '  数量 ' + $x.Count) -ForegroundColor Red }
        Write-Host '  请到托盘图标右键退出两个客户端（点窗口 X 不算退出）。'
        Write-Host '  按回车重新检查，输入 0 返回菜单。'
        $r = Read-Host '  '
        if ($r -eq '0') { return $false }
    }
}

function Get-PlaceholderCount {
    $n = 0
    foreach ($s in $Sides) {
        foreach ($nm in $Names) {
            if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA ('WB-Isolated\' + $s + '\temp\' + $nm))) { $n++ }
        }
    }
    return $n
}

function Get-Version([string]$exe) {
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { return '-' }
    $mf = Join-Path (Split-Path -Parent $exe) 'resources\install-manifest.json'
    if (-not (Test-Path -LiteralPath $mf)) { return '?' }
    $m = [regex]::Match((Get-Content -LiteralPath $mf -Raw), '"appVersion"\s*:\s*"([^"]+)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return '?'
}

function Get-Endpoint([string]$exe) {
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { return '-' }
    $pj = Join-Path (Split-Path -Parent $exe) 'resources\app.asar.unpacked\cli\product.json'
    if (-not (Test-Path -LiteralPath $pj)) { return '?' }
    $m = [regex]::Match((Get-Content -LiteralPath $pj -Raw), '"endpoint"\s*:\s*"(https?://[^"]+)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return '?'
}

function Get-CnExe {
    foreach ($c in @('D:\workbuddy\WorkBuddy.exe','E:\workbuddy\WorkBuddy.exe','C:\Program Files\WorkBuddy\WorkBuddy.exe')) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Get-AiExe {
    $cands = @('F:\软件\WorkBuddyAI\WorkBuddyAI.exe','D:\WorkBuddyAI\WorkBuddyAI.exe','E:\WorkBuddyAI\WorkBuddyAI.exe')
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $c } }
    $reg = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
    if ($reg) {
        foreach ($n in $reg.PSObject.Properties.Name) {
            $v = [string]$reg.$n
            if ($v -like '*WorkBuddyAI.exe*') {
                $v = ($v -replace '"','').Trim()
                if (Test-Path -LiteralPath $v) { return $v }
            }
        }
    }
    foreach ($root in @('F:\','D:\','E:\','G:\')) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($d in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            $p = Join-Path $d.FullName 'WorkBuddyAI\WorkBuddyAI.exe'
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    return $null
}

function Show-Status {
    Write-Host ''
    Write-Host '== 状态 ==' -ForegroundColor Cyan
    $cn = Get-CnExe; $ai = Get-AiExe
    Write-Host ('  国内版  ' + $(if ($cn) { $cn } else { '未找到' }))
    if ($cn) { Write-Host ('          版本 ' + (Get-Version $cn) + '   端点 ' + (Get-Endpoint $cn)) }
    Write-Host ('  国际版  ' + $(if ($ai) { $ai } else { '未找到' }))
    if ($ai) { Write-Host ('          版本 ' + (Get-Version $ai) + '   端点 ' + (Get-Endpoint $ai)) }
    Show-Procs
    $ph = Get-PlaceholderCount
    if ($ph -eq 6) { Write-Host '  自动更新: 已冻结（两侧）' -ForegroundColor Yellow }
    elseif ($ph -eq 0) { Write-Host '  自动更新: 开放（两侧）' -ForegroundColor Green }
    else { Write-Host ('  自动更新: 部分冻结 (' + $ph + '/6)') -ForegroundColor Magenta }
    $reg = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
    if ($reg) {
        foreach ($n in $reg.PSObject.Properties.Name) {
            if ([string]$reg.$n -like '*WorkBuddy*') { Write-Host ('  自启项  ' + $n + ' = ' + [string]$reg.$n) }
        }
    }
    $found = $false
    foreach ($d in $Names) {
        $p = Join-Path $SysTemp $d
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $s = Get-ChildItem -LiteralPath $p -Filter 'WorkBuddy-Setup-*.exe' -ErrorAction SilentlyContinue
        foreach ($f in $s) {
            $found = $true
            Write-Host ('  遗留安装包  ' + $p + '\' + $f.Name + '  ' + [math]::Round($f.Length/1MB) + ' MB') -ForegroundColor Yellow
        }
    }
    if (-not $found) { Write-Host '  共用缓存: 无遗留安装包  [OK]' -ForegroundColor Green }
}

function Do-Snapshot {
    Write-Host ''
    Write-Host '== 快照 ==' -ForegroundColor Cyan
    if (-not (Wait-AllClosed)) { return }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $out   = Join-Path $SnapRoot ('dg-' + $stamp + '.zip')
    $stage = Join-Path $SysTemp ('dg-snap-' + $stamp)
    New-Item -ItemType Directory -Force -Path $SnapRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $srcs = @(
        @{ F = (Join-Path $env:USERPROFILE '.workbuddy');          T = (Join-Path $stage '.workbuddy') },
        @{ F = (Join-Path $env:USERPROFILE '.workbuddy-ai');       T = (Join-Path $stage '.workbuddy-ai') },
        @{ F = (Join-Path $env:LOCALAPPDATA 'CodeBuddyExtension');  T = (Join-Path $stage 'CodeBuddyExtension') }
    )
    foreach ($s in $srcs) {
        if (-not (Test-Path -LiteralPath $s.F)) { Write-Host ('  跳过 ' + $s.F) -ForegroundColor DarkGray; continue }
        Write-Host ('  复制 ' + $s.F)
        robocopy $s.F $s.T /E /XD $ExcludeDirs /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
    }
    Write-Host '  打包中，请稍候...'
    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($tar) { & $tar.Source -a -c -f $out -C $stage . 2>$null }
    else { Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $out -CompressionLevel Optimal }
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $out)) { Write-Host '  失败：未生成压缩包。' -ForegroundColor Red; Log 'snapshot FAILED'; return }
    $mb = [math]::Round((Get-Item -LiteralPath $out).Length / 1MB, 1)
    Write-Host ('  完成 ' + $out + '  ' + $mb + ' MB') -ForegroundColor Green
    Log ('snapshot ok ' + $out + ' ' + $mb + 'MB')
    Get-ChildItem -LiteralPath $SnapRoot -Filter 'dg-*.zip' | Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 5 | ForEach-Object { Write-Host ('  清理旧快照 ' + $_.Name) -ForegroundColor DarkGray; Remove-Item -LiteralPath $_.FullName -Force }
}

function Do-Clean {
    Write-Host ''
    Write-Host '== 清理共用更新缓存 ==' -ForegroundColor Cyan
    if (-not (Wait-AllClosed)) { return }
    $targets = @()
    foreach ($d in $Names) {
        $p = Join-Path $SysTemp $d
        if (Test-Path -LiteralPath $p) {
            $sz = (Get-ChildItem -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            if (-not $sz) { $sz = 0 }
            $targets += [pscustomobject]@{ Path = $p; MB = [math]::Round($sz/1MB,1) }
        }
    }
    # 防御：绝不触碰隔离目录（那里只有占位文件，删了等于解冻）
    $skip = @($targets | Where-Object { $_.Path.StartsWith($IsoRoot, 'OrdinalIgnoreCase') })
    if ($skip.Count -gt 0) {
        foreach ($s in $skip) { Write-Host ('  跳过隔离目录 ' + $s.Path) -ForegroundColor DarkGray }
        $targets = @($targets | Where-Object { -not $_.Path.StartsWith($IsoRoot, 'OrdinalIgnoreCase') })
    }
    if ($targets.Count -eq 0) { Write-Host '  这些目录已不存在，无需清理。' -ForegroundColor Green; return }
    Write-Host ''
    Write-Host '  将要删除以下目录（仅限应用更新缓存）：' -ForegroundColor Yellow
    foreach ($t in $targets) { Write-Host ('    ' + $t.MB + ' MB   ' + $t.Path) }
    Write-Host ''
    Write-Host '  输入 yes 确认删除，其他任何输入取消。'
    if ((Read-Host '  确认') -ne 'yes') { Write-Host '  已取消。' -ForegroundColor DarkGray; return }
    foreach ($t in $targets) {
        Remove-Item -LiteralPath $t.Path -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $t.Path) { Write-Host ('  失败（文件被占用） ' + $t.Path) -ForegroundColor Red; Log ('clean FAILED ' + $t.Path) }
        else { Write-Host ('  已删除 ' + $t.Path) -ForegroundColor Green; Log ('clean ok ' + $t.Path) }
    }
}

function Do-Freeze([bool]$freeze) {
    Write-Host ''
    if ($freeze) { Write-Host '== 冻结自动更新 ==' -ForegroundColor Cyan } else { Write-Host '== 解冻自动更新 ==' -ForegroundColor Cyan }
    foreach ($s in $Sides) {
        $dir = Join-Path $env:LOCALAPPDATA ('WB-Isolated\' + $s + '\temp')
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        foreach ($nm in $Names) {
            $p = Join-Path $dir $nm
            if ($freeze) {
                if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType File -Path $p | Out-Null }
            } else {
                if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
            }
        }
    }
    $n = Get-PlaceholderCount
    if ($freeze) {
        Write-Host ('  完成：两侧占位文件 ' + $n + '/6，自动更新已阻断。') -ForegroundColor Yellow
        Write-Host '  下次通过 .cmd 启动器启动后生效。'
        Log 'freeze on'
    } else {
        Write-Host ('  完成：剩余占位文件 ' + $n + '/6，自动更新已恢复。') -ForegroundColor Green
        Write-Host '  更新前请先完全退出另一版本；更新完成后建议重新冻结。'
        Log 'freeze off'
    }
}

while ($true) {
    Clear-Host
    Write-Host '========================================================'
    Write-Host '  DualGuard   WorkBuddy 双版本隔离与维护'
    Write-Host '========================================================'
    Show-Status
    Line '='
    Write-Host '  1  生成快照                  需两个客户端退出'
    Write-Host '  2  清理共用更新缓存          需两个客户端退出'
    Write-Host '  3  依次执行 1 + 2           需两个客户端退出，推荐'
    Write-Host '  4  解冻自动更新              允许应用内更新'
    Write-Host '  5  冻结自动更新              阻断自动更新'
    Write-Host '  6  刷新状态'
    Write-Host '  0  退出'
    Line '='
    $c = Read-Host '  请选择'

    switch ($c) {
        '1' { Do-Snapshot; Read-Host '  按回车返回菜单' | Out-Null }
        '2' { Do-Clean;    Read-Host '  按回车返回菜单' | Out-Null }
        '3' { Do-Snapshot; Do-Clean; Read-Host '  按回车返回菜单' | Out-Null }
        '4' { Do-Freeze $false; Read-Host '  按回车返回菜单' | Out-Null }
        '5' { Do-Freeze $true;  Read-Host '  按回车返回菜单' | Out-Null }
        '6' { }
        '0' { break }
        default { }
    }
    if ($c -eq '0') { break }
}
Write-Host ''
Write-Host '  已退出。' -ForegroundColor DarkGray
