# Financ

App mobile (Flutter) para registrar gastos, organizá-los em categorias e somar
total **diário, semanal e mensal**. Cada gasto pode ser digitado manualmente ou
preenchido automaticamente a partir da **foto de um cupom fiscal** (OCR on-device).

## Como funciona (custo R$ 0)

- **OCR:** Google ML Kit Text Recognition v2, rodando **no próprio aparelho**
  (gratuito, ilimitado, offline).
- **Parsing do cupom:** heurísticas locais (`lib/services/receipt_parser.dart`)
  extraem estabelecimento (CNPJ), data/hora, itens, **TOTAL** e forma de
  pagamento de cupons SAT/NFC-e brasileiros.
- **Categorização:** regras por palavra-chave + **memória por estabelecimento**
  (o app aprende quando você corrige a categoria).
- **Confirmação humana:** o app nunca grava direto da foto — o formulário abre
  pré-preenchido para você conferir com 1 toque.
- **Dados 100% locais** (SQLite via sqflite). Sem servidor, sem backend.
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
flutter test      # 13 testes (parser do cupom + categorizador + UI)
```

## Rodando o app

```bash
flutter devices            # confira o aparelho/emulador conectado
flutter run                # debug no dispositivo padrão
flutter run -d <device_id> # escolher dispositivo específico
```

Na tela inicial: botão **+** → "Foto do cupom fiscal" (câmera/galeria) ou
"Lançamento manual". Aba **Relatórios** mostra total do período, gráfico por
categoria e por forma de pagamento (mês / 30 dias / ano / intervalo custom).

## Gerando o APK de release

```bash
flutter build apk --release
# APK em build/app/outputs/flutter-apk/app-release.apk
# Instalar no aparelho:
adb install build/app/outputs/flutter-apk/app-release.apk
```

Para iOS: `flutter build ios --release` (requer Mac + Xcode; ML Kit pede
target iOS ≥ 15.5 e excluir arquitetura armv7 em Runner > Build Settings).

## Estrutura

```
lib/
├── main.dart                  # app + navegação (Gastos / Relatórios)
├── models/models.dart         # Expense, Category, PaymentMethod, ReceiptDraft
├── db/db.dart                 # SQLite (sqflite) + agregações + períodos
├── state/providers.dart       # Riverpod: estado dos gastos + sumários dia/semana/mês
├── services/
│   ├── ocr_service.dart       # ML Kit Text Recognition (on-device)
│   ├── receipt_parser.dart    # parser heurístico de cupom fiscal BR
│   ├── categorizer.dart       # regras por palavra-chave + memória
│   └── ai_fallback.dart       # extensão opcional p/ IA (desligada por padrão)
├── screens/                   # home, captura do cupom, formulário, relatórios
└── widgets/common.dart        # formatação BRL, ícones/cores, tiles

test/                          # parser_test.dart + widget_test.dart
```

## Permissões

- **Android:** nenhuma permissão explícita (câmera via app do sistema).
- **iOS:** `NSCameraUsageDescription` e `NSPhotoLibraryUsageDescription` já
  configurados em `ios/Runner/Info.plist`.
