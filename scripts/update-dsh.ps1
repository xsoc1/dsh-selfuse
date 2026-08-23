<#
.SYNOPSIS
    检查 / 更新本地 DeepSeek Harness 到上游最新版本。

.DESCRIPTION
    检查模式（-Check）只读地对比本地与上游版本；
    更新模式（-Apply）拉取上游 master、快进本地 master、
    rebase local/image-admission 维护分支，并重新构建 host lib。

    网络兜底：github.com 无法直连时自动切到 140.82.112.4 + Host header。

.PARAMETER Check
    只检查版本，不做任何修改。

.PARAMETER Apply
    执行更新（拉取 / rebase / 构建）。有冲突会中止并报告。

.PARAMETER DryRun
    打印将执行的动作，不实际修改。

.PARAMETER HarnessRoot
    DeepSeek Harness 源码目录。默认 DSH_ROOT / F:\tools\deepseek-harness。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\update-dsh.ps1 -Check
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\update-dsh.ps1 -Apply
#>
param(
    [switch]$Check,
    [switch]$Apply,
    [switch]$DryRun,
    [string]$HarnessRoot
)

$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $HarnessRoot) {
    $HarnessRoot = Join-Path $RepoRoot 'vendor\deepseek-harness'
    if (-not (Test-Path (Join-Path $HarnessRoot 'package.json'))) {
        if ($env:DSH_ROOT -and (Test-Path (Join-Path $env:DSH_ROOT 'package.json'))) {
            $HarnessRoot = $env:DSH_ROOT
        } else {
            $wslHarness = '\\wsl.localhost\Ubuntu\home\huangzy\tools\deepseek-harness'
            if (Test-Path (Join-Path $wslHarness 'package.json')) {
                $HarnessRoot = $wslHarness
            } else {
                $HarnessRoot = 'F:\tools\deepseek-harness'
            }
        }
    }
}
$GitHubApi = 'https://api.github.com/repos/deepseek-ai/deepseek-harness'
$GitHubIp = 'https://140.82.112.4/deepseek-ai/deepseek-harness.git'
$LocalBranch = 'local/image-admission'

function Write-Info($msg) { Write-Host "[i] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "[-] $msg" -ForegroundColor Red }

function Get-LocalVersion {
    if (-not (Test-Path (Join-Path $HarnessRoot 'package.json'))) {
        return @{ version = 'unknown'; commit = ''; branch = '' }
    }
    $pkg = Get-Content -Raw (Join-Path $HarnessRoot 'package.json') | ConvertFrom-Json
    $commit = ''
    $branch = ''
    try {
        $commit = (git -C $HarnessRoot rev-parse --short HEAD 2>$null).Trim()
        $branch = (git -C $HarnessRoot branch --show-current 2>$null).Trim()
    } catch {}
    return @{ version = $pkg.version; commit = $commit; branch = $branch }
}

function Get-UpstreamTag {
    try {
        $headers = @{ 'User-Agent' = 'dsh-selfuse' }
        $rel = Invoke-RestMethod -Uri "$GitHubApi/releases/latest" -Headers $headers -TimeoutSec 15
        if ($rel.tag_name) {
            return ($rel.tag_name -replace '^v', '')
        }
    } catch {}
    return ''
}

function Get-UpstreamMasterCommit {
    try {
        $env:GIT_SSL_NO_VERIFY = '1'
        $out = git -c http.sslVerify=false -c http.extraHeader='Host: github.com' ls-remote $GitHubIp refs/heads/master 2>$null
        if ($out -match '^([0-9a-f]{40})\s+refs/heads/master') {
            return $Matches[1]
        }
    } catch {}
    try {
        $out = git -C $HarnessRoot ls-remote origin refs/heads/master 2>$null
        if ($out -match '^([0-9a-f]{40})\s+refs/heads/master') {
            return $Matches[1]
        }
    } catch {}
    return ''
}

function Invoke-Git {
    param([string[]]$Args, [switch]$AllowFail)
    if ($DryRun) {
        Write-Host "    [dry-run] git $($Args -join ' ')"
        if ($AllowFail) { return $true }
        return $true
    }
    Push-Location $HarnessRoot
    try {
        & git @Args 2>&1 | ForEach-Object { Write-Host "    $_" }
        if ($LASTEXITCODE -ne 0 -and -not $AllowFail) {
            throw "git $($Args -join ' ') failed (exit $LASTEXITCODE)"
        }
        return ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }
}

function Update-Dsh {
    if ($DryRun) {
        Write-Info 'Dry-run: 以下为计划操作'
    }

    # 1. fetch upstream
    Write-Info '拉取上游 master ...'
    $fetchOk = $true
    if (-not $DryRun) {
        Push-Location $HarnessRoot
        try {
            git fetch origin master 2>&1 | ForEach-Object { Write-Host "    $_" }
            if ($LASTEXITCODE -ne 0) {
                Write-Warn '普通 fetch 失败，改用 GitHub IP 兜底 ...'
                git -c http.sslVerify=false -c http.extraHeader='Host: github.com' fetch $GitHubIp master:refs/remotes/origin/master 2>&1 | ForEach-Object { Write-Host "    $_" }
                if ($LASTEXITCODE -ne 0) { $fetchOk = $false }
            }
        } finally {
            Pop-Location
        }
    } else {
        Write-Host '    [dry-run] git fetch origin master (or IP fallback)'
    }
    if (-not $fetchOk) {
        Write-Err '无法拉取上游，更新中止'
        return $false
    }

    $upstreamSha = ''
    try {
        $upstreamSha = (git -C $HarnessRoot rev-parse refs/remotes/origin/master 2>$null).Trim()
    } catch {}
    if (-not $upstreamSha) {
        Write-Err 'fetch 后仍无法确定上游 commit，更新中止'
        return $false
    }

    $localMasterSha = ''
    try {
        $localMasterSha = (git -C $HarnessRoot rev-parse master 2>$null).Trim()
    } catch {}

    Write-Host "    本地 master: $localMasterSha"
    Write-Host "    上游 master: $upstreamSha"
    if ($localMasterSha -eq $upstreamSha) {
        Write-Ok '本地 master 已是最新，无需快进'
    } else {
        Write-Info '快进本地 master ...'
        Invoke-Git -Args @('checkout', 'master') -AllowFail
        Invoke-Git -Args @('merge', '--ff-only', 'origin/master')
    }

    Write-Info "rebase $LocalBranch 到 master ..."
    Invoke-Git -Args @('checkout', $LocalBranch) -AllowFail
    if ($DryRun) {
        Write-Host '    [dry-run] git rebase master'
    } else {
        Push-Location $HarnessRoot
        try {
            git rebase master 2>&1 | ForEach-Object { Write-Host "    $_" }
            if ($LASTEXITCODE -ne 0) {
                Write-Err 'rebase 存在冲突，已中止（本机未自动解决）。请手动处理后再运行。'
                git rebase --abort 2>&1 | Out-Null
                return $false
            }
        } finally {
            Pop-Location
        }
    }

    Write-Info '重新安装依赖并构建 host lib ...'
    if ($DryRun) {
        Write-Host '    [dry-run] pnpm install && npm run build:lib:host'
    } else {
        Push-Location $HarnessRoot
        try {
            pnpm install --no-frozen-lockfile 2>&1 | ForEach-Object { Write-Host "    $_" }
            if ($LASTEXITCODE -ne 0) { throw 'pnpm install failed' }
            npm run build:lib:host 2>&1 | ForEach-Object { Write-Host "    $_" }
            if ($LASTEXITCODE -ne 0) { throw 'npm run build:lib:host failed' }
        } finally {
            Pop-Location
        }
    }

    Write-Ok "更新完成，当前分支: $LocalBranch"
    return $true
}

# --- main ---
if (-not $Check -and -not $Apply) {
    Write-Host '用法:'
    Write-Host '  .\scripts\update-dsh.ps1 -Check   只检查版本'
    Write-Host '  .\scripts\update-dsh.ps1 -Apply   拉取并更新'
    exit 0
}

$local = Get-LocalVersion
$upstream = Get-UpstreamTag
$upstreamSha = Get-UpstreamMasterCommit

Write-Host ''
Write-Host '---- DSH 版本检查 ----' -ForegroundColor Cyan
Write-Host "  本地  : $($local.version) ($($local.branch), $($local.commit))"
if ($upstream) {
    Write-Host "  上游  : $upstream"
} else {
    Write-Host '  上游  : 无法获取 release tag（将使用 master commit 比较）'
}
if ($upstreamSha) {
    Write-Host "  上游commit: $($upstreamSha.Substring(0, 12))"
}

$needUpdate = $false
if ($upstream -and $upstream -ne $local.version) {
    $needUpdate = $true
    Write-Warn '版本不一致，可执行 -Apply 更新'
} elseif ($upstreamSha) {
    $currentSha = ''
    try { $currentSha = (git -C $HarnessRoot rev-parse master 2>$null).Trim() } catch {}
    if ($currentSha -ne $upstreamSha) {
        $needUpdate = $true
        Write-Warn '本地 master 与上游不一致，可执行 -Apply 更新'
    } else {
        Write-Ok '本地已经是最新'
    }
} else {
    Write-Warn '无法确定上游状态'
}

if ($Apply) {
    if ($needUpdate -or $true) {
        $ok = Update-Dsh
        if ($ok) {
            $local2 = Get-LocalVersion
            Write-Ok "更新后本地: $($local2.version) ($($local2.commit))"
        } else {
            exit 1
        }
    }
}
Write-Host ''
