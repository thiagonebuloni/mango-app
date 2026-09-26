# Financ

App mobile (Flutter) para registrar gastos, organizá-los em categorias e somar
total **diário, semanal e mensal**. Cada gasto pode ser digitado manualmente ou
preenchido automaticamente a partir da **foto de um cupom fiscal** (OCR on-device).


## Como funciona (custo R$ 0)

- **OCR:** Google ML Kit Text Recognition v2, rodando **no próprio aparelho**
  (gratuito, ilimitado, offline).
- **Parsing do cupom:** heurísticas locais (`lib/services/receipt_parser.dart`)
  extraem estabelecimento (CNPJ), data/hora, itens, **TOTAL** e forma de
  pagamento de cupons SAT/NFC-e brasileiros. A data do gasto é escolhida
  priorizando linhas de emissão/venda/cupom (ignorando validade/vencimento e
  aceitando a hora na linha de baixo) e **"À VISTA"** é interpretado como
  **Dinheiro**.
- **Categorização:** regras por palavra-chave + **memória por estabelecimento**
  (o app aprende quando você corrige a categoria).
- **Confirmação humana:** o app nunca grava direto da foto — o formulário abre
  pré-preenchido para você conferir com 1 toque.
- **Dados 100% locais** (SQLite via sqflite). Sem servidor, sem backend.
- **Perfil e tela inicial:** nome, avatar (emoticon ou foto com recorte) e
  cor de fundo escolhidos no primeiro acesso
  (`lib/screens/profile_setup_screen.dart`); a tela inicial
  (`lib/screens/landing_screen.dart`) mostra avatar + nome e os botões
- **Foto do cupom:** limite de 8 MB — imagens maiores (em geral vindas da
  galeria) são recusadas **antes** de decodificar/rodar o OCR, pois decodificar
  aloca muito mais memória e pode travar o app em aparelhos simples.
- **Avatar:** tocar no avatar abre o menu — **emoticon** (atalhos mais usados
  **e** a grade de emojis do app, que já abre direto com todos: busca,
  categorias e recentes, sem depender do teclado do aparelho; guarda o
  primeiro emoticon, funcionando com compostos como 👨‍👩‍👧) ou **foto**
  (galeria/câmera, `lib/widgets/avatar.dart`). A foto tem limite de 5 MB
  (recusada antes de decodificar, como o cupom), é copiada para os documentos
  do app e tem edição simples: arrastar posiciona o recorte e o slider dá
  zoom (posição + zoom salvos no perfil, SQLite v5).
- **Fallback IA (opcional):** `lib/services/ai_fallback.dart` documenta o ponto
  de extensão para Gemini Flash (camada gratuita), enviando só o texto do OCR.

## Requisitos

- Flutter SDK (estável, ≥ 3.47 — testado com 3.47.5 / Dart 3.12)
- Android SDK/Studio (para Android) ou Xcode (para iOS)
- Um dispositivo/emulador Android ou iOS

## Rodando os testes

```bash
flutter pub get
flutter analyze   # deve terminar com "No issues found!"
flutter test      # 40 testes (parser do cupom + categorizador + UI)
```

## Rodando o app

```bash
flutter devices            # confira o aparelho/emulador conectado
flutter run                # debug no dispositivo padrão
flutter run -d <device_id> # escolher dispositivo específico
```

Dentro do app, botão **+** → "Foto do cupom fiscal" (câmera/galeria) ou
"Lançamento manual". Aba **Relatórios** mostra gráfico de barras despesas
x receitas do período, total do período, gráfico por categoria e por forma
de pagamento (mês / 30 dias / ano / intervalo custom).

## Gerando o APK de release

```bash
flutter build apk --release
# APK em build/app/outputs/flutter-apk/app-release.apk
# Instalar no aparelho:
adb install build/app/outputs/flutter-apk/app-release.apk
```

> **Importante (OCR no release):** o APK de release passa por minificação/R8.
> O ML Kit descobre seus componentes por reflexão, e o R8 full mode (padrão a
> partir do AGP 9, usado neste projeto) remove o construtor sem argumentos dos
> registradores. Isso faz `TextRecognition.getClient()` quebrar no release com
> `Attempt to invoke virtual method 'java.lang.Class java.lang.Object.getClass()'
> on a null object reference`. As regras de keep necessárias estão em
> **`android/app/proguard-rules.pro`** — não remova esse arquivo. Mais detalhes
> e como validar em [Solução de problemas](#solução-de-problemas).

## Solução de problemas

### "Falha ao ler o cupom ... getClass() ... on a null object reference"

Acontece **só no APK de release** (em debug o OCR funciona). É R8 removendo o
construtor dos registradores do ML Kit, que são instanciados via reflexão.

Correção (já aplicada em `android/app/proguard-rules.pro`):

```proguard
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google.mlkit.** { *; }
```

Como conferir que o release saiu correto — nenhuma linha de saída e o DEX deve
conter o construtor do registrador:

```bash
grep -E '^(TextRegistrar|CommonComponentRegistrar|VisionCommonRegistrar):' \
  build/app/outputs/mapping/release/usage.txt
# (nenhuma saída = construtores preservados)
```

Se você gerou APKs por ABI (`--split-per-abi`) antes da correção, apague-os:
`flutter build apk --release` reescreve apenas `app-release.apk` e os splits
antigos (quebrados) continuam no disco.

Para iOS: `flutter build ios --release` (requer Mac + Xcode; ML Kit pede
target iOS ≥ 15.5 e excluir arquitetura armv7 em Runner > Build Settings).

## Estrutura

```
lib/
├── main.dart                  # app + ProfileGate (primeiro acesso × tela inicial)
├── models/models.dart         # Expense, Category, PaymentMethod, ReceiptDraft, UserProfile
├── db/db.dart                 # SQLite (sqflite) + perfil + agregações + períodos
├── state/providers.dart       # Riverpod: gastos, perfil, sumários dia/semana/mês
├── theme/app_theme.dart       # tema do app a partir da cor de fundo do perfil
├── services/
│   ├── ocr_service.dart       # ML Kit Text Recognition (on-device)
│   ├── receipt_parser.dart    # parser heurístico de cupom fiscal BR
│   ├── categorizer.dart       # regras por palavra-chave + memória
│   └── ai_fallback.dart       # extensão opcional p/ IA (desligada por padrão)
├── screens/
│   ├── root_nav.dart          # abas Gastos / Relatórios (deslize)
│   ├── landing_screen.dart    # tela inicial: avatar + nome + Meus gastos/Menu
│   ├── profile_setup_screen.dart  # cadastro/edição: nome, avatar e cor de fundo
│   ├── home_screen.dart       # lista de gastos + resumo
│   ├── capture_screen.dart    # foto do cupom + OCR
│   ├── expense_form_screen.dart   # confirmação/edição do gasto
│   └── reports_screen.dart    # relatórios por período
└── widgets/common.dart        # formatação BRL, ícones/cores, FAB, tiles

test/                          # parser_test.dart + widget_test.dart
```

## Permissões

- **Android:** nenhuma permissão explícita (câmera via app do sistema).
- **iOS:** `NSCameraUsageDescription` e `NSPhotoLibraryUsageDescription` já
  configurados em `ios/Runner/Info.plist`.
