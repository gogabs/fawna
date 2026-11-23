# Baixa as extensões nativas do Fawna para a pasta addons/.
#   - Prism (prismatoid): fala pelo leitor de tela ou motor de voz
#   - Nexus Resonance: Steam Audio com HRTF binaural
# Uso (PowerShell, na raiz do projeto):  ./tools/instalar_extensoes.ps1

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$PrismVersion = "v0.18.3"
$ResonanceVersion = "v1.2.0"

$extensoes = @(
    @{ Nome = "Prism $PrismVersion"; Pasta = "prismatoid";
       Url = "https://github.com/ethindp/prism/releases/download/$PrismVersion/prismatoid-gdextension-$PrismVersion.zip" },
    @{ Nome = "Nexus Resonance $ResonanceVersion"; Pasta = "nexus_resonance";
       Url = "https://github.com/undomick/godot-nexus-resonance/releases/download/$ResonanceVersion/nexus_resonance-$ResonanceVersion.zip";
       Versao = $ResonanceVersion.TrimStart("v") }
)

$raiz = Split-Path -Parent $PSScriptRoot
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "fawna-extensoes"
New-Item -ItemType Directory -Force -Path $temp | Out-Null

foreach ($ext in $extensoes) {
    $destino = Join-Path $raiz "addons/$($ext.Pasta)"
    if (Test-Path $destino) {
        # Com versão conhecida, troca uma versão antiga pela nova.
        $cfg = Join-Path $destino "plugin.cfg"
        $atual = (Test-Path $cfg) -and (Select-String -Path $cfg -SimpleMatch "version=""$($ext.Versao)""" -Quiet)
        if (-not $ext.Versao -or $atual) {
            Write-Host "$($ext.Nome): já instalado em addons/$($ext.Pasta)"
            continue
        }
        Write-Host "$($ext.Nome): trocando a versão antiga em addons/$($ext.Pasta)"
        Remove-Item -Recurse -Force $destino
    }
    $zip = Join-Path $temp "$($ext.Pasta).zip"
    Write-Host "Baixando $($ext.Nome)..."
    Invoke-WebRequest -Uri $ext.Url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $raiz -Force
    Write-Host "$($ext.Nome): instalado."
}

Write-Host "Pronto. Abra o projeto no Godot 4.6 ou mais novo."
