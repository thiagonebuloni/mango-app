import '../models/models.dart';

import 'receipt_parser.dart';

/// Categorizador de gastos com custo zero:
///
/// 1. **Memória por estabelecimento** — se o usuário já categorizou um gasto
///    desse estabelecimento antes, repete a categoria (aprende com correções).
/// 2. **Regras por palavra-chave** — dicionário local leve (texto do cupom,
///    nome do estabelecimento e descrição).
class Categorizer {
  /// Carrega a memória estabelecimento → categoria (assíncrono: vem do banco).
  final Future<Map<String, Category>> Function() memoryLoader;

  /// Ponto de extensão opcional para um resolvedor externo (ex.: IA).
  final CategoryResolver? fallback;

  Categorizer({required this.memoryLoader, this.fallback});

  /// Decide a categoria considerando memória, regras e fallback.
  Future<Category> categorize({
    String? estabelecimento,
    String? text,
    String? descricao,
  }) async {
    final merchant = estabelecimento?.trim() ?? '';
    if (merchant.isNotEmpty) {
      final memory = await memoryLoader();
      final memorized =
          memory[ReceiptParser.normalizeMerchant(merchant)];
      if (memorized != null) return memorized;
    }
    return guessByKeywords(
        estabelecimento: estabelecimento, text: text, descricao: descricao);
  }

  /// Regras puras por palavra-chave (sem memória) — testável de forma síncrona.
  Category guessByKeywords({
    String? estabelecimento,
    String? text,
    String? descricao,
  }) {
    final haystack =
        '${estabelecimento ?? ''} ${descricao ?? ''} ${text ?? ''}'
            .toLowerCase();

    // A ordem dos grupos importa (específicos primeiro).
    const rules = <Category, List<String>>{
      Category.vestuario: [
        'vestuario', 'vestuário', 'roupa', 'calcado', 'calçado', 'sapato',
        'tenis', 'tênis', 'camisa', 'camiseta', 'calca', 'calça', 'blusa',
        'boutique', 'renner', 'riachuelo', 'zara', 'shein', 'hering',
      ],
      Category.mercado: [
        'supermercado', 'mercado', 'atacad', 'hortifruti', 'acougue',
        'açougue', 'assai', 'assaí', 'atacarejo', 'carrefour',
        'pão de açúcar', 'pao de acucar',
      ],
      Category.transporte: [
        'uber', '99 pop', 'posto', 'combustivel', 'combustível', 'gasolina',
        'etanol', 'diesel', 'onibus', 'ônibus', 'metro', 'metrô', 'trem',
        'estacionamento', 'pedagio', 'pedágio', 'shell', 'ipiranga', 'vibra',
      ],
      Category.saude: [
        'farmacia', 'farmácia', 'drogaria', 'drogasil', 'raia', 'pague menos',
        'clinica', 'clínica', 'hospital', 'laboratorio', 'laboratório',
        'dentista', 'odonto', 'psicolog', 'exame', 'medicament',
      ],
      Category.lazer: [
        'cinema', 'teatro', 'restaurante', 'bar ', 'lanch', 'pizz', 'hamburg',
        'coffee', 'cafeteria', 'delivery', 'ifood', 'rappi', 'jogo', 'steam',
        'netflix', 'spotify', 'balada', 'show',
      ],
      Category.moradia: [
        'aluguel', 'condominio', 'condomínio', 'energia', 'iptu', 'iplu',
        'sabesp', 'sanepar', 'copel', 'enel', 'claro', 'vivo', 'tim ', 'oi ',
        'internet', 'telefone',
      ],
      Category.alimentacao: [
        'pao', 'pão', 'padaria', 'confeitaria', 'acai', 'açaí', 'lanche',
        'bolo', 'cafe', 'café', 'marmita', 'salgad', 'sorvete', 'bebida',
      ],
    };

    for (final entry in rules.entries) {
      for (final keyword in entry.value) {
        if (haystack.contains(keyword)) return entry.key;
      }
    }

    final resolved = fallback?.resolve(
        estabelecimento: estabelecimento, text: text, descricao: descricao);
    return resolved ?? Category.outros;
  }
}

/// Ponto de extensão para um resolvedor externo (ex.: IA) — deve ser barato
/// e tolerante a falhas (retorno null = "não sei").
abstract class CategoryResolver {
  Category? resolve({String? estabelecimento, String? text, String? descricao});
}
