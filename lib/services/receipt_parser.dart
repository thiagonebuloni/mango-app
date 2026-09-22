// Parser heurístico de cupons fiscais brasileiros (SAT CF-e / NFC-e / cupom
// comum). Trabalha sobre o texto puro extraído pelo OCR — sem dependências
// de Flutter, totalmente testável em unit tests.
//
// Estratégia: cupons brasileiros são padronizados, então regras simples de
// regex resolvem a maioria dos casos:
//   - Nome do estabelecimento: linha que precede (ou contém) o CNPJ/IE.
//   - Data/hora: padrão `dd/mm/aaaa` (também `dd-mm-aa`), priorizando as
//     linhas que descrevem a venda (data/emissão/cupom/SAT/NFC-e) e
//     descartando datas de validade/vencimento/fabricação. A hora pode vir na
//     mesma linha ou, como em vários cupons SAT, sozinha na linha seguinte.
//   - Total: linhas com "TOTAL"/"VALOR A PAGAR" (excluindo "troco", "itens").
//     Fallback: maior valor monetário do texto.
//   - Forma de pagamento: palavras-chave (DINHEIRO, DÉBITO, CRÉDITO, PIX) e
//     "À VISTA" (quando não há cartão no cupom) → DINHEIRO.

import '../models/models.dart';

class ReceiptParser {
  /// Valores monetários no formato brasileiro: 1.234,56 ou 12,34.
  static final RegExp _money =
      RegExp(r'(?:R\$)?\s*(\d{1,3}(?:\.\d{3})*,\d{2})');

  static final RegExp _cnpj = RegExp(r'CNPJ\s*:?\s*([\d.\-/]+)');

  /// Data do cupom: 20/03/2026, 20-03-2026, 20-03-26 ou 20.3.2026.
  static final RegExp _date =
      RegExp(r'\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})\b');

  /// Hora: 14:32 ou 14:32:05 (aparece logo depois da data).
  static final RegExp _time = RegExp(r'\b(\d{1,2}):(\d{2})(?::\d{2})?\b');

  /// Linhas que costumam acompanhar a DATA DO GASTO (emissão da venda).
  static final RegExp _dateHints = RegExp(
    r'(data|emiss|exped|venda|cupom|sat|nfce|nf-e|nfe|autentic|movimento|'
    r'caixa|pedido|hora)',
  );

  /// Linhas com datas que NÃO são a do gasto (validade, vencimento...).
  static final RegExp _dateExclusions =
      RegExp(r'(valid|venc|fabric|promoc|sorteio)');

  /// "À VISTA" (com/sem acento ou espaço) = dinheiro na maioria dos cupons.
  static final RegExp _aVista = RegExp(r'\ba\s*vista\b');

  /// Minúsculas e sem acentos — base das comparações de palavras-chave.
  static String _fold(String text) {
    const accents = <String, String>{
      'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    final buffer = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      buffer.write(accents[char] ?? char);
    }
    return buffer.toString();
  }

  static ReceiptDraft parse(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return ReceiptDraft(
      estabelecimento: _merchant(lines),
      dataHora: _dateTimeFrom(lines),
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

  /// Tenta identificar a data do gasto no cupom.
  ///
  /// Cupons trazem mais de uma data (validade de promoção, vencimento de
  /// parcela, fabricação...), então cada data recebe uma pontuação e ganha a
  /// que está em uma linha típica da venda ("DATA", "EMISSÃO", "CUPOM",
  /// "SAT/NFC-e", "CAIXA"...) ou que tem hora junto (data de validade
  /// raramente tem). Empate: a primeira data válida do cupom.
  static DateTime? _dateTimeFrom(List<String> lines) {
    DateTime? firstDate;
    DateTime? bestDate;
    var bestScore = 0;

    for (var i = 0; i < lines.length; i++) {
      final dataHora = _dateInLine(lines, i);
      if (dataHora == null) continue;
      firstDate ??= dataHora;

      final line = _fold(lines[i]);
      var score = 0;
      if (_dateHints.hasMatch(line)) score += 2;
      if (_dateExclusions.hasMatch(line)) score -= 2;
      if (dataHora.hour != 0 || dataHora.minute != 0) score += 1;

      if (score > bestScore) {
        bestScore = score;
        bestDate = dataHora;
      }
    }
    return bestDate ?? firstDate;
  }

  /// Lê a data da linha [index]; a hora pode estar na mesma linha ou, como em
  /// vários cupons SAT/NFC-e, sozinha na linha seguinte.
  static DateTime? _dateInLine(List<String> lines, int index) {
    final match = _date.firstMatch(lines[index]);
    if (match == null) return null;

    Match? time = _time.firstMatch(lines[index].substring(match.end));
    if (time == null && index + 1 < lines.length) {
      time = _time.matchAsPrefix(lines[index + 1].trim());
    }

    return _buildDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      hour: time == null ? null : int.parse(time.group(1)!),
      minute: time == null ? null : int.parse(time.group(2)!),
    );
  }

  /// Monta a data validando os limites: o OCR às vezes troca dígitos
  /// ("32/13/2026") e o `DateTime` normalizaria isso em silêncio.
  static DateTime? _buildDate(int day, int month, int year,
      {int? hour, int? minute}) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (year < 100) year += 2000;
    if (year < 2000 || year > 2100) return null;

    final h = (hour != null && hour >= 0 && hour < 24) ? hour : 0;
    final m = (minute != null && minute >= 0 && minute < 60) ? minute : 0;
    final date = DateTime(year, month, day, h, m);
    if (date.day != day || date.month != month) return null; // 31/02, 29/02...
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
    final lower = _fold(text);
    // Ordem importa: "crédito" antes de "débito"; métodos explícitos antes de
    // "à vista" (ex.: "CRÉDITO A VISTA" é cartão) e "cartão" por último.
    if (lower.contains('pix')) return PaymentMethod.pix;
    if (lower.contains('credito')) return PaymentMethod.credito;
    if (lower.contains('debito')) return PaymentMethod.debito;
    if (lower.contains('dinheiro')) return PaymentMethod.dinheiro;
    if (_aVista.hasMatch(lower)) return PaymentMethod.dinheiro;
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
    final folded =
        _fold(merchant).replaceAll(RegExp(r'cnpj\s*:?\s*[\d.\-/]+'), '');
    return folded
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

}
