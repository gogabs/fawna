#!/usr/bin/env sh
# Baixa as extensões nativas do Fawna para a pasta addons/ (Linux/macOS).
# Uso, na raiz do projeto:  sh tools/instalar_extensoes.sh
set -eu

PRISM_VERSION="v0.18.3"
RESONANCE_VERSION="v1.1.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

install_ext() {
  name="$1"; folder="$2"; url="$3"
  if [ -d "$ROOT/addons/$folder" ]; then
    echo "$name: já instalado em addons/$folder"
    return
  fi
  echo "Baixando $name..."
  curl -fsSL -o "$TMP/$folder.zip" "$url"
  unzip -q -o "$TMP/$folder.zip" -d "$ROOT"
  echo "$name: instalado."
}

install_ext "Prism $PRISM_VERSION" prismatoid \
  "https://github.com/ethindp/prism/releases/download/$PRISM_VERSION/prismatoid-gdextension-$PRISM_VERSION.zip"
install_ext "Nexus Resonance $RESONANCE_VERSION" nexus_resonance \
  "https://github.com/undomick/godot-nexus-resonance/releases/download/$RESONANCE_VERSION/nexus_resonance-$RESONANCE_VERSION.zip"

echo "Pronto. Abra o projeto no Godot 4.6 ou mais novo."
