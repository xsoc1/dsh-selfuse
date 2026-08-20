# 启动本地生图服务（SDXL-Turbo / diffusers）供 dsh generate_image 工具使用。
# 用法：  powershell -ExecutionPolicy Bypass -File start-image-gen.ps1
# 端口：17821（可改）。模型已缓存到 F:\tools\image-gen\hf，无需重复下载。
$ErrorActionPreference = "Stop"
$venvPy = "F:\tools\image-gen\venv\Scripts\python.exe"
$server = "F:\tools\image-gen\server.py"
$port = 17821

# 健康检查
try {
    $alive = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 3
    Write-Host "生图服务已在运行: $($alive.model) @ $port"
    exit 0
} catch { }

if (-not (Test-Path $venvPy)) { Write-Error "缺少 venv python: $venvPy"; exit 1 }
if (-not (Test-Path $server)) { Write-Error "缺少 server.py: $server"; exit 1 }

Write-Host "启动生图服务 @ 127.0.0.1:$port ... (首次加载模型约 10-30s)"
$env:HF_HOME = "F:\tools\image-gen\hf"
$proc = Start-Process -FilePath $venvPy -ArgumentList @($server, "--port", "$port") -WindowStyle Hidden -PassThru
Write-Host "已启动 PID $($proc.Id)。健康检查:"
Start-Sleep -Seconds 5
$deadline = (Get-Date).AddSeconds(120)
do {
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 3
        Write-Host "OK: $($r.model) ready on $($r.device)"
        exit 0
    } catch {
        Start-Sleep -Seconds 5
    }
} while ((Get-Date) -lt $deadline)
Write-Host "服务未就绪，查看进程日志或手动运行: $venvPy $server --port $port"
exit 1
