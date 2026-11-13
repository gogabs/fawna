# Copia os sons usados pelo jogo do pacote "World Sounds Audio Pack" para
# assets/sounds/world/. A lista sai de client/sounds.gd (MANIFEST), então
# basta adicionar um arquivo lá e rodar este script de novo.
# Uso (PowerShell, na raiz do projeto):
#   ./tools/copiar_sons.ps1                      # usa D:\Áudio\world
#   ./tools/copiar_sons.ps1 -Origem "E:\sons"    # outra pasta

param([string]$Origem = "D:\Áudio\world")

$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot
$destino = Join-Path $raiz "assets/sounds/world"
New-Item -ItemType Directory -Force -Path $destino | Out-Null

$manifesto = Get-Content -Raw -Encoding UTF8 (Join-Path $raiz "client/sounds.gd")
$arquivos = [regex]::Matches($manifesto, '"world/([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

# Licença do pacote vai junto.
$licenca = Join-Path $Origem "license.txt"
if (Test-Path -LiteralPath $licenca) { Copy-Item -LiteralPath $licenca -Destination $destino -Force }

$faltando = @()
foreach ($nome in $arquivos) {
    $origemArquivo = Join-Path $Origem $nome
    if (Test-Path -LiteralPath $origemArquivo) {
        Copy-Item -LiteralPath $origemArquivo -Destination $destino -Force
    } else {
        $faltando += $nome
    }
}
Write-Host "$($arquivos.Count - $faltando.Count) sons copiados para assets/sounds/world."
if ($faltando.Count -gt 0) {
    Write-Host "Não encontrados em ${Origem}:"
    $faltando | ForEach-Object { Write-Host "  $_" }
}
