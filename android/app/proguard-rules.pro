# ---------------------------------------------------------------------------
# ML Kit (OCR de cupom) — regras de keep necessárias para o build de RELEASE
# ---------------------------------------------------------------------------
# Sintoma corrigido: o OCR funcionava em debug e falhava no APK de release com
#
#   Falha ao ler o cupom: Exception: Attempt to invoke virtual method
#   'java.lang.Class java.lang.Object.getClass()' on a null object reference
#
#   at com.google.mlkit.common.sdkinternal.LazyInstanceMap.get(...)
#
# Causa: o ML Kit descobre seus componentes (registradores) por reflexão. O
# firebase-components traz em seu proguard.txt a regra abaixo, mas SEM `{ *; }`:
#
#   -keep class * implements com.google.firebase.components.ComponentRegistrar
#
# Com o R8 full mode (padrão a partir do AGP 9 / este projeto usa AGP 9.0.1)
# o R8 mantém o nome da classe mas remove o construtor sem argumentos. Na hora
# de instanciar o registrador via reflexão a criação falha, o provider do
# recognizer nunca é registrado e TextRecognition.getClient(...) quebra.
# Evidência: build/app/outputs/mapping/release/usage.txt listava, como
# removidos, `TextRegistrar: public void <init>()`,
# `CommonComponentRegistrar: public void <init>()` e
# `VisionCommonRegistrar: public void <init>()`.
#
# Referência: https://github.com/googlesamples/mlkit/issues/1018
# (mesmo problema de R8 full mode em outros SDKs do ML Kit).
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }

# Mantém nomes e membros do ML Kit: as classes internas (ex.:
# com.google.mlkit.vision.text.internal.TextRegistrar) e os criadores do
# recognizer bundled são carregados/instanciados por nome em tempo de execução.
-keep class com.google.mlkit.** { *; }
