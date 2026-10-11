# Prépare le checkout Nestora pour un build local :
# 1. clone ../Nestora si absent  2. copie nginx.conf -> frontend/nginx.ops.conf
param(
  [string]$NestoraUrl = "https://github.com/Marouanof/Nestora.git",
  [string]$ParentDir = (Split-Path -Parent $PSScriptRoot | Split-Path -Parent)
)
$ErrorActionPreference = "Stop"
$nestoraDir = Join-Path $ParentDir "Nestora"
$opsDir = Split-Path -Parent $PSScriptRoot
if (!(Test-Path $nestoraDir)) {
  Write-Host "Clone Nestora -> $nestoraDir"
  git clone --depth 1 $NestoraUrl $nestoraDir
} else {
  Write-Host "Nestora déjà présent : $nestoraDir"
}
Copy-Item (Join-Path $opsDir "docker\nginx.conf") (Join-Path $nestoraDir "frontend\nginx.ops.conf") -Force
Write-Host "OK : frontend/nginx.ops.conf synchronisé."
Write-Host "Suite : copy .env.example -> .env, remplis les secrets, puis docker compose up --build"
