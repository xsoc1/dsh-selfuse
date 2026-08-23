$ErrorActionPreference = 'Stop'
$root = 'F:\tools\dsh-skill-router\node_modules'
$chk = 'F:\tools\deepseek-harness'
function Link-J($name, $target) {
  $p = Join-Path $root $name
  if (-not (Test-Path $p)) { New-Item -ItemType Junction -Path $p -Target (Join-Path $chk $target) | Out-Null; Write-Host "linked $name" }
  else { Write-Host "exists $name" }
}
Link-J 'cordis' 'vendor\cordis'
Link-J 'cosmokit' 'vendor\cosmokit'
Link-J 'schemastery' 'vendor\schemastery'
Link-J '@deepseek-ai\dsh-tools' 'packages\core\tools'
Link-J '@deepseek-ai\dsh-llm' 'packages\llm\llm'
Link-J '@deepseek-ai\dsh-system-prompt' 'packages\core\system-prompt'
Link-J '@types\node' 'node_modules\@types\node'
Write-Host 'deps done'
