# 生成 dsh 品牌图标: favicon.svg -> dsh-icon.svg (深蓝圆角底+白鲸) -> PNG -> ICO
$ErrorActionPreference = 'Stop'

$favicon = 'C:\Users\HuangZY\.dsh\profiles\node_modules\@deepseek-ai\dsh-web-frontend\dist\favicon.svg'
$svgOut  = 'F:\tools\deepseek-harness\dsh-icon.svg'
$pngOut  = 'F:\tools\deepseek-harness\dsh-icon.png'
$icoOut  = 'F:\tools\deepseek-harness\dsh.ico'
$edge    = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

$src = Get-Content $favicon -Raw
$m = [regex]::Match($src, '\sd="([^"]+)"')
if (-not $m.Success) { throw 'favicon path not found' }
$d = $m.Groups[1].Value

$svg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#5B8CFF"/>
      <stop offset="1" stop-color="#2F4BCF"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="256" height="256" fill="url(#bg)"/>
  <g transform="translate(20 34) scale(4.4)">
    <path d="$d" fill="#ffffff"/>
  </g>
</svg>
"@
[System.IO.File]::WriteAllText($svgOut, $svg, (New-Object System.Text.UTF8Encoding($false)))

if (Test-Path $pngOut) { Remove-Item $pngOut -Force }
& $edge --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --window-size=256,256 --screenshot="$pngOut" "file:///F:/tools/deepseek-harness/dsh-icon.svg" 2>&1 | Out-Null
Start-Sleep -Seconds 2
if (-not (Test-Path $pngOut)) { throw 'PNG render failed' }

Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap($pngOut)
$hIcon = $bmp.GetHicon()
$icon = [System.Drawing.Icon]::FromHandle($hIcon)
$fs = [System.IO.File]::Create($icoOut)
$icon.Save($fs)
$fs.Close()
$icon.Dispose()
$bmp.Dispose()

Write-Output "ICO written: $((Get-Item $icoOut).Length) bytes"
