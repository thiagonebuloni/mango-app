#!/usr/bin/env bash
# Baixa (se preciso) e envia o modelo de I.A. para o aparelho via adb.
#
# Por quê: o app é 100% offline (o release não tem permissão de internet) —
# o modelo chega por fora e a inferência roda no próprio aparelho. O
# arquivo vai para a pasta externa do app (Android/data/<pkg>/files/models),
# que o app lê em qualquer build; se o push falhar (alguns aparelhos
# restringem essa pasta em Android 11+), o script tenta o diretório privado
# com `run-as` (funciona em build de debug, que é o caso de teste).
#
# Modelo padrão: Qwen3 0.6B em `.litertlm` (345 MB, licença Apache-2.0), da
# coleção litert-community (formato oficial do LiteRT-LM). A variante
# `_dynamic_wi4b32_afp32` é a indicada na documentação do Flutter Edge AI —
# o arquivo base `Qwen3-0.6B.litertlm` não carrega nas versões atuais.
# Qualquer outro `.litertlm` no mesmo diretório também é reconhecido pela
# tela do relatório.
#
# Uso: tool/install_modelo_ia.sh [caminho-local-do.litertlm]
set -euo pipefail

PKG=br.com.mango.mango
REPO=litert-community/Qwen3-0.6B
ARQUIVO=Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm
URL="https://huggingface.co/$REPO/resolve/main/$ARQUIVO"
CACHE="$HOME/.cache/mango-modelos"
LOCAL=${1:-"$CACHE/$ARQUIVO"}

if ! adb get-state >/dev/null 2>&1; then
  echo "Nenhum aparelho conectado (confira 'adb devices' e a depuração USB)." >&2
  exit 1
fi

mkdir -p "$(dirname "$LOCAL")"
if [[ ! -f "$LOCAL" ]]; then
  echo "Baixando $ARQUIVO (~345 MB) do Hugging Face..."
  if command -v wget >/dev/null 2>&1; then
    wget -O "$LOCAL.part" "$URL"
  else
    curl -L -o "$LOCAL.part" "$URL"
  fi
  mv "$LOCAL.part" "$LOCAL"
fi

DESTINO="Android/data/$PKG/files/models"
echo "Enviando para o aparelho ($DESTINO)..."
if adb shell mkdir -p "/sdcard/$DESTINO" 2>/dev/null && \
   adb push "$LOCAL" "/sdcard/$DESTINO/$ARQUIVO"; then
  echo "OK: /sdcard/$DESTINO/$ARQUIVO"
else
  echo "Push na pasta externa falhou; tentando o diretório privado (build debug)..."
  adb shell "run-as $PKG mkdir -p files/models"
  adb push "$LOCAL" "/data/local/tmp/$ARQUIVO"
  adb shell "cat /data/local/tmp/$ARQUIVO | run-as $PKG sh -c 'cat > files/models/$ARQUIVO'"
  adb shell "rm -f /data/local/tmp/$ARQUIVO"
  echo "OK: files/models/$ARQUIVO (área privada do app)"
fi

echo "Abra o app: aba Relatórios → Gerar relatório mensal por I.A. → Atualizar lista."
