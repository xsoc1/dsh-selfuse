<#
.SYNOPSIS
    Setup portable Ollama and required models for dsh-local.
.DESCRIPTION
    Skeleton. In the future this will download/import Ollama and run
    `ollama pull qwen3-vl:4b`. Model binaries are never stored in git.
#>
param([switch]$DryRun)

$ErrorActionPreference = "Stop"
Write-Host "Ollama setup skeleton" -ForegroundColor Green

# TODO:
# 1. Download portable Ollama zip if missing
# 2. Set OLLAMA_HOST=127.0.0.1:11810 and OLLAMA_MODELS to local cache
# 3. Start `ollama serve`
# 4. `ollama pull qwen3-vl:4b`
# 5. Verify GET http://127.0.0.1:11810/

if ($DryRun) {
    Write-Host "[dry-run] would download Ollama, set OLLAMA_HOST=127.0.0.1:11810, pull qwen3-vl:4b"
}
