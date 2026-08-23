# Patch node-pty 1.1.0 conpty console-list agent so AttachConsole failure is
# tolerated when dsh runs without an interactive console (e.g. hidden watchdog).
# Idempotent: safe to run multiple times.
$ErrorActionPreference = 'Stop'

$base = 'F:\tools\community-plugins\DSH-better-sidebar\node_modules\.pnpm\node-pty@1.1.0\node_modules\node-pty'
if (-not (Test-Path $base)) {
    Write-Warning "node-pty package not found at $base; skipping patch"
    exit 0
}

$js = Join-Path $base 'lib\conpty_console_list_agent.js'
$ts = Join-Path $base 'src\conpty_console_list_agent.ts'

function Apply-Patch($file, [string]$old, [string]$new) {
    if (-not (Test-Path $file)) {
        Write-Warning "missing $file"
        return
    }
    $content = Get-Content -Raw -LiteralPath $file
    if ($content.Contains('catch (err)')) {
        Write-Output "already patched: $file"
        return
    }
    if (-not $content.Contains($old)) {
        Write-Warning "pattern not found in $file; patch may need updating"
        return
    }
    $content = $content.Replace($old, $new)
    [System.IO.File]::WriteAllText($file, $content, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output "patched: $file"
}

$jsOld = "var consoleProcessList = getConsoleProcessList(shellPid);`nprocess.send({ consoleProcessList: consoleProcessList });"
$jsNew = "var consoleProcessList = [];`ntry {`n  consoleProcessList = getConsoleProcessList(shellPid);`n} catch (err) {`n  consoleProcessList = [];`n}`nprocess.send({ consoleProcessList: consoleProcessList });"
Apply-Patch $js $jsOld $jsNew

$tsOld = "const consoleProcessList = getConsoleProcessList(shellPid);`nprocess.send!({ consoleProcessList });"
$tsNew = "let consoleProcessList: number[] = [];`ntry {`n  consoleProcessList = getConsoleProcessList(shellPid);`n} catch (err) {`n  consoleProcessList = [];`n}`nprocess.send!({ consoleProcessList });"
Apply-Patch $ts $tsOld $tsNew

Write-Output 'node-pty patch complete'
