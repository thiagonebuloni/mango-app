import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// OCR on-device (ML Kit Text Recognition v2, script latino).
///
/// - Roda 100% no aparelho: gratuito, ilimitado, sem rede, sem custo por foto.
/// - O modelo é baixado via Google Play Services (Android) / bundled (iOS).
class OcrService {
  TextRecognizer? _recognizer;

  TextRecognizer get _rec {
    return _recognizer ??=
        TextRecognizer(script: TextRecognitionScript.latin);
  }

  /// Extrai o texto completo de uma foto (caminho do arquivo local).
  Future<String> extractText(String filePath) async {
    final inputImage = InputImage.fromFilePath(filePath);
    final recognizedText = await _rec.processImage(inputImage);
    return recognizedText.text;
  }

  void dispose() {
    _recognizer?.close();
    _recognizer = null;
  }
}
