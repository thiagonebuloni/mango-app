// Parser heurístico de cupons fiscais brasileiros (SAT CF-e / NFC-e / cupom
// comum). Trabalha sobre o texto puro extraído pelo OCR — sem dependências
// de Flutter, totalmente testável em unit tests.
//
// Estratégia: cupons brasileiros são padronizados, então regras simples de
// regex resolvem a maioria dos casos:
//   - Nome do estabelecimento: linha que precede (ou contém) o CNPJ/IE.
//   - Data/hora: padrão `dd/mm/aaaa hh:mm[:ss]`.
//   - Total: linhas com "TOTAL"/"VALOR A PAGAR" (excluindo "troco", "itens").
//     Fallback: maior valor monetário do texto.
//   - Forma de pagamento: palavras-chave (DINHEIRO, DÉBITO, CRÉDITO, PIX).

import '../models/models.dart';

class ReceiptParser {
  /// Valores monetários no formato brasileiro: 1.234,56 ou 12,34.
  static final RegExp _money =
      RegExp(r'(?:R\$)?\s*(\d{1,3}(?:\.\d{3})*,\d{2})');

  static final RegExp _cnpj = RegExp(r'CNPJ\s*:?\s*([\d.\-/]+)');

  static final RegExp _dateTime =
      RegExp(r'(\d{2}/\d{2}/\d{2,4})(?:\s+(\d{1,2}:\d{2})(?::\d{2})?)?');

  static ReceiptDraft parse(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return ReceiptDraft(
      estabelecimento: _merchant(lines),
      dataHora: _dateTimeFrom(text),
      totalCentavos: _total(lines),
      pagamento: _paymentMethod(text),
      itens: _items(lines),
      textoOcr: text,
    );
  }

  static String? _merchant(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final cnpjMatch = _cnpj.firstMatch(lines[i]);
      if (cnpjMatch != null) {
        // O nome geralmente vem em uma das 2 linhas anteriores ao CNPJ.
        for (var j = i - 1; j >= 0 && j >= i - 2; j--) {
          final candidate = _cleanMerchant(lines[j]);
          if (candidate != null) return candidate;
        }
        // Sem nome reconhecível: o CNPJ identifica o estabelecimento.
        return 'CNPJ ${cnpjMatch.group(1)}';
      }
    }
    // Fallback: primeira linha "curta e capitular" do cupom.
    for (final l in lines.take(3)) {
      final candidate = _cleanMerchant(l);
      if (candidate != null) return candidate;
    }
    return null;
  }

  static String? _cleanMerchant(String line) {
    final l = line.trim();
    if (l.isEmpty) return null;
    if (l.length < 3 || l.length > 40) return null;
    // Descarta linhas que parecem endereço / código fiscal / totais.
    if (_money.hasMatch(l) ||
        RegExp(r'(cnpj|cpf|ie|av\.|rua|r\.)', caseSensitive: false)
            .hasMatch(l)) {
      return null;
    }
    return l;
  }

  static DateTime? _dateTimeFrom(String text) {
    final m = _dateTime.firstMatch(text);
    if (m == null) return null;
    final parts = m.group(1)!.split('/');
    var year = int.parse(parts[2]);
    if (year < 100) year += 2000;
    final date = DateTime(year, int.parse(parts[1]), int.parse(parts[0]));
    final time = m.group(2);
    if (time != null) {
      final hm = time.split(':');
      return date
          .add(Duration(hours: int.parse(hm[0]), minutes: int.parse(hm[1])));
    }
    return date;
  }

  /// Converte "1.234,56" em centavos (123456).
  static int moneyToCentavos(String s) {
    final digits = s.replaceAll('.', '').replaceAll(',', '');
    return int.parse(digits);
  }

  static int? _total(List<String> lines) {
    // Marcadores fortes do valor total a pagar.
    const strongMarkers = [
      'valor a pagar',
      'valor total',
      'total a pagar',
      'total pago',
      'valor a cobrar',
    ];
    // Linhas que citam "total" mas NÃO são o total a pagar.
    const excluded = [
      'troco',
      'itens',
      'item',
      'desconto',
      'acresc',
      'devolu',
      'sub-total do',
      'tributos',
    ];

    int? weakCandidate;

    for (final line in lines.reversed) {
      final lower = line.toLowerCase();
      final mentionsTotal = lower.contains('total') ||
          lower.contains('a pagar') ||
          lower.contains('pagar');
      if (!mentionsTotal) continue;
      if (excluded.any(lower.contains)) continue;

      final matches = _money.allMatches(line).toList();
      if (matches.isEmpty) continue;
      final value = moneyToCentavos(matches.last.group(1)!);

      final isStrong = strongMarkers.any(lower.contains);
      final isPlainTotal =
          lower.replaceAll(RegExp(r'[^a-zà-ú]'), '').contains('total');

      if (isStrong) return value;
      if (isPlainTotal && weakCandidate == null) weakCandidate = value;
    }

    // Fallback 1: linhas "PGTO"/"PAGTO" do SAT (última linha de pagamento).
    for (final line in lines.reversed) {
      final lower = line.toLowerCase();
      if (lower.contains('pgto') || lower.contains('pagto')) {
        final matches = _money.allMatches(line).toList();
        if (matches.isNotEmpty) return moneyToCentavos(matches.last.group(1)!);
      }
    }

    // Fallback 2: maior valor monetário do cupom (o total costuma ser o maior).
    int? max;
    for (final m in _money.allMatches(lines.join(' '))) {
      final v = moneyToCentavos(m.group(1)!);
      if (max == null || v > max) max = v;
    }
    return weakCandidate ?? max;
  }

  static PaymentMethod? _paymentMethod(String text) {
    final lower = text
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i');
    // Ordem importa: "crédito" antes de "débito", e cartão antes de dinheiro.
    if (lower.contains('pix')) return PaymentMethod.pix;
    if (lower.contains('credito')) return PaymentMethod.credito;
    if (lower.contains('debito')) return PaymentMethod.debito;
    if (lower.contains('dinheiro')) return PaymentMethod.dinheiro;
    if (lower.contains('cartao')) return PaymentMethod.credito;
    return null;
  }

  static List<ReceiptItem> _items(List<String> lines) {
    const excluded = [
      'total',
      'troco',
      'subtotal',
      'pgto',
      'pagto',
      'cnpj',
      'tributos',
    ];
    final unit = RegExp(r'\b(un|kg|cx|lt|pc|fd|sc)\b', caseSensitive: false);
    final items = <ReceiptItem>[];
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (excluded.any(lower.contains)) continue;
      if (line.length < 8) continue;
      // Linha de item típica: "PÃO FRANCES KG 1,000 kg x 15,99 15,99"
      if (!unit.hasMatch(line)) continue;
      final matches = _money.allMatches(line).toList();
      if (matches.isEmpty) continue;
      final value = moneyToCentavos(matches.last.group(1)!);
      final name = line.substring(0, matches.first.start).trim();
      if (name.isEmpty) continue;
      items.add(ReceiptItem(nome: name, valorCentavos: value));
    }
    return items;
  }

  /// Normaliza o nome de um estabelecimento para uso como chave de memória
  /// (tabela `merchants`): minúsculas, sem pontuação/CNPJ/acentos.
  static String normalizeMerchant(String merchant) {
    const accents = <String, String>{
      'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a',
      'é': 'e', 'ê': 'e',
      'í': 'i',
      'ó': 'o', 'ô': 'o', 'õ': 'o',
      'ú': 'u', 'ü': 'u',
      'ç': 'c',
    };
    var s = merchant
        .toLowerCase()
        .replaceAll(RegExp(r'cnpj\s*:?\s*[\d.\-/]+'), '');
    accents.forEach((from, to) {
      s = s.replaceAll(from, to);
    });
    return s
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

}
