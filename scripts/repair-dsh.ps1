<#
.SYNOPSIS
    dsh 抢救/自检：补齐 client/web 构建产物、共享插件依赖。
.DESCRIPTION
    修复 dsh 升级后常见问题：
      1. client bundles 缺失 (MissingClientBundleError)
      2. out-of-tree 插件依赖解析失败 (Cannot find package)
    用法:
      powershell -NoProfile -ExecutionPolicy Bypass -File repair-dsh.ps1
#>
param(
    [switch]$SkipBuild,
    [switch]$SkipDeps,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$HarnessRoot    = '\\wsl.localhost\Ubuntu\home\huangzy\tools\deepseek-harness'
$LocalRoot      = '\\wsl.localhost\Ubuntu\home\huangzy\tools\dsh-local'
$CommunityRoot  = '\\wsl.localhost\Ubuntu\home\huangzy\tools\community-plugins'
$PnPmShim       = Join-Path $HarnessRoot 'node_modules\.bin\pnpm.cmd'

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Invoke-PnPm([string]$ScriptArgs, [string]$WorkingDir) {
    if ($DryRun) {
        Write-Host "    [dry-run] pnpm $ScriptArgs (in $WorkingDir)"
        return
    }
    Push-Location $WorkingDir
    try {
        & $PnPmShim @($ScriptArgs -split ' ') 2>&1 | ForEach-Object { Write-Host "    $_" }
        if ($LASTEXITCODE -ne 0) {
            throw "pnpm $ScriptArgs failed in $WorkingDir (exit $LASTEXITCODE)"
        }
    } finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "dsh repair" -ForegroundColor Green
Write-Host "Harness: $HarnessRoot"
if ($DryRun) { Write-Host "Mode: DRY RUN" -ForegroundColor Yellow }
Write-Host ""

# 1. client/web 构建产物
if (-not $SkipBuild) {
    Write-Step "检查 client/web 构建产物"
    $required = @(
        'packages/client/ui-reference/lib/client.js',
        'packages/client/ui-renderer/lib/client.js',
        'packages/client/ui-attachment/lib/client.js',
        'packages/client/ui-brand-official/lib/client.js',
        'apps/web/dist/index.html'
    )
    $missing = @($required | Where-Object { -not (Test-Path (Join-Path $HarnessRoot $_)) })
    if ($missing.Count -eq 0) {
        Write-Ok "构建产物完整"
    } else {
        Write-Warn "缺失: $($missing -join ', ')"
        Invoke-PnPm 'run build:lib:client' $HarnessRoot
        Invoke-PnPm 'run build:web' $HarnessRoot
        Write-Ok "client/web 构建完成"
    }
}

# 2. 共享依赖根 (dsh-local + community-plugins)
if (-not $SkipDeps) {
    Write-Step "检查共享插件依赖"
    foreach ($root in @($LocalRoot, $CommunityRoot)) {
        $pkg = Join-Path $root 'package.json'
        if (Test-Path $pkg) {
            Write-Host "    sync deps: $root"
            Invoke-PnPm 'install --no-frozen-lockfile --ignore-scripts' $root
        }
    }
    $verify = @'
const { createRequire } = require('module')
const cases = [
  ['\\wsl.localhost\Ubuntu\home\huangzy\tools\community-plugins/dsh-wsl-workspace/lib/index.js', '@deepseek-ai/schemastery'],
  ['\\wsl.localhost\Ubuntu\home\huangzy\tools\community-plugins/dsh-wsl-workspace/lib/index.js', '@deepseek-ai/dsh-shell'],
  ['\\wsl.localhost\Ubuntu\home\huangzy\tools\community-plugins/dsh-wsl-workspace/lib/index.js', '@deepseek-ai/dsh-fs-local'],
  ['\\wsl.localhost\Ubuntu\home\huangzy\tools\community-plugins/dsh-backup/lib/index.js', '@deepseek-ai/dsh-tools'],
  ['\\wsl.localhost\Ubuntu\home\huangzy\tools\community-plugins/dsh-backup/lib/index.js', '@deepseek-ai/dsh-typert-protocol'],
  ['\\wsl.localhost\Ubuntu\home\huangzy\tools\community-plugins/DSH-better-sidebar/lib/index.js', '@deepseek-ai/dsh-tools'],
  ['\\wsl.localhost\Ubuntu\home\huangzy\tools\dsh-local/plugins/dsh-routing-suite/injector-release/lib/index.js', 'schemastery'],
  ['\\wsl.localhost\Ubuntu\home\huangzy\tools\dsh-local/plugins/dsh-routing-suite/injector-release/lib/index.js', '@deepseek-ai/dsh-llm']
]
let failed = 0
for (const [base, name] of cases) {
  try {
    createRequire(base).resolve(name)
    console.log('OK  ' + name)
  } catch (e) {
    failed++
    console.log('FAIL ' + name + ' -> ' + e.message)
  }
}
process.exit(failed ? 1 : 0)
'@
    if ($DryRun) {
        Write-Host "    [dry-run] verify plugin dependency resolution"
    } else {
        node -e $verify
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "插件依赖解析全部通过"
        } else {
            Write-Warn "部分插件依赖解析失败，请检查上方 FAIL 项"
        }
    }
}

Write-Host ""
Write-Host "repair done" -ForegroundColor Green
