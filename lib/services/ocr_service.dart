/// OCR on-device (ML Kit Text Recognition v2, script latino) via canal nativo
/// (financ/ocr em MainActivity.kt) — sem plugin intermediário, para manter o
/// APK pequeno (inclui apenas o modelo latino).
///
/// - Roda 100% no aparelho: gratuito, ilimitado, sem rede, sem custo por foto.
import 'package:flutter/services.dart';

class OcrService {
  static const MethodChannel _channel = MethodChannel('financ/ocr');

  /// Extrai o texto completo de uma foto (caminho do arquivo local).
  Future<String> extractText(String filePath) async {
    try {
      final text = await _channel.invokeMethod<String>(
        'extractText',
        {'path': filePath},
      );
      return text ?? '';
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Falha ao executar o OCR.');
    }
  }

  void dispose() {
    // Sem recursos a liberar: o recognizer nativo é criado e fechado por chamada.
  }
}
