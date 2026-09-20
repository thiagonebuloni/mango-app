import '../models/models.dart';

/// Fallback opcional de análise via IA (Gemini Flash). **Desligado por
/// padrão e não usado no fluxo principal** — ML Kit + parser local + regras
/// resolvem a maioria dos cupons com custo zero. Se no futuro você quiser
/// um fallback para cupons difíceis, basta fornecer a API key.
///
/// A chamada envia SOMENTE o texto extraído pelo OCR (não a imagem), o que
/// mantém o custo por chamada mínimo (fração de centavo na camada gratuita).
///
/// Para ativar, implemente `CategoryResolver`/esta classe com sua chave e
/// registre-a no `Categorizer`. Mantida como ponto de extensão documentado.
class AiFallback {
  final String? apiKey;
  AiFallback({this.apiKey});

  bool get enabled => apiKey != null && apiKey!.isNotEmpty;

  /// Exemplo de payload que seria enviado ao endpoint:
  /// https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent
  ///
  /// prompt:
  ///   "Extraia JSON {estabelecimento, dataHora, total, pagamento} do
  ///    texto de cupom a seguir: `texto OCR`"
  Future<ReceiptDraft?> analyze(String ocrText) async {
    if (!enabled) return null; // sem chave: nenhum custo, nenhuma chamada
    throw UnimplementedError(
        'Fallback de IA é opcional; implemente com sua própria API key.');
  }
}
