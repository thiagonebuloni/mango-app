#!/usr/bin/env bash
# Instala o APK de release apenas no usuário principal (0) e confere que o app
# não aparece em outros usuários/espaços do aparelho (Xiaomi/MIUI: *Segundo
# espaço* = usuário 10; Android 15+: *espaço privado* = usuário 11).
#
# Por quê: `adb install` (e o `flutter run`) instala no usuário que estiver
# ativo no aparelho — se o Segundo espaço estiver aberto na hora, o app vai
# só para lá e depois um `adb install` no espaço principal falha com
# `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. Aqui o alvo é fixado com
# `pm install --user 0`, que não depende da tela do aparelho.
#
# Uso: tool/install_release.sh [caminho-do.apk]
set -euo pipefail

PKG=br.com.mango.mango
USUARIO_PRINCIPAL=0
APK=${1:-build/app/outputs/flutter-apk/app-release.apk}

if [[ ! -f "$APK" ]]; then
  echo "APK não encontrado: $APK" >&2
  echo "Gere antes com: flutter build apk --release" >&2
  exit 1
fi

if ! adb get-state >/dev/null 2>&1; then
  echo "Nenhum aparelho conectado (confira 'adb devices' e a depuração USB)." >&2
  exit 1
fi

ativo=$(adb shell am get-current-user | tr -d '\r')
if [[ "$ativo" != "$USUARIO_PRINCIPAL" ]]; then
  echo "AVISO: o usuário $ativo está ativo no aparelho (Segundo espaço?)." >&2
  echo "        Instalando assim mesmo só no usuário $USUARIO_PRINCIPAL." >&2
fi

remoto=/data/local/tmp/mango-release.apk
echo "Enviando $APK..."
adb push "$APK" "$remoto" >/dev/null

echo "Instalando no usuário $USUARIO_PRINCIPAL..."
adb shell pm install --user "$USUARIO_PRINCIPAL" -r "$remoto"
adb shell rm -f "$remoto"

echo
if adb shell pm list packages --user "$USUARIO_PRINCIPAL" | grep -qF "$PKG"; then
  echo "OK: $PKG instalado no usuário $USUARIO_PRINCIPAL."
else
  echo "ERRO: $PKG não aparece no usuário $USUARIO_PRINCIPAL." >&2
  exit 1
fi

# Outros usuários/espaços: o app não deveria estar lá. Se estiver, mostre o
# comando para remover daquele espaço — sem mexer no principal.
for u in $(adb shell pm list users | sed -n 's/.*UserInfo{\([0-9]\{1,\}\):.*/\1/p' | tr -d '\r'); do
  if [[ "$u" == "$USUARIO_PRINCIPAL" ]]; then
    continue
  fi
  if adb shell pm list packages --user "$u" | grep -qF "$PKG"; then
    echo "AVISO: $PKG também está no usuário $u. Para remover de lá:" >&2
    echo "       adb shell pm uninstall --user $u $PKG" >&2
  fi
done
