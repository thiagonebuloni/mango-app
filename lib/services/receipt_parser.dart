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
//   - Parcelas: "PARCELA x/y", "x DE y", "EM Nx" (ex.: 2/10, 2 DE 10,
//     10X). Quando detectadas, o estabelecimento sai como "LOJA 2/10" e
//     a forma de pagamento é forçada para CRÉDITO (parcelado é cartão).

import '../models/models.dart';

/// Parcela detectada num cupom: [atual] de [total] (ex.: 2 de 10).
class ParcelaInfo {
  final int atual;
  final int total;

  const ParcelaInfo(this.atual, this.total);

  @override
  String toString() => '$atual/$total';
}

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

    final parcela = parcelas(text);
    var merchant = _merchant(lines);
    if (parcela != null && merchant != null) {
      merchant = withParcelaSuffix(merchant, parcela);
    }
    var pagamento = _paymentMethod(text);
    // Compra parcelada é sempre no cartão de crédito: força o valor mesmo
    // que o cupom não traga a palavra "crédito" de forma legível.
    if (parcela != null) pagamento = PaymentMethod.credito;

    return ReceiptDraft(
      estabelecimento: merchant,
      dataHora: _dateTimeFrom(lines),
      totalCentavos: _total(lines),
      pagamento: pagamento,
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

  /// Total máximo de parcelas aceito (trava contra leitura errada do OCR).
  static const maxParcelas = 60;

  /// Detecta compra parcelada no texto do cupom (ex.: "PARCELA 2/10",
  /// "PARCELA 2 DE 10", "EM 10X"). Retorna `null` quando não há parcelamento.
  static ParcelaInfo? parcelas(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    ParcelaInfo? best;
    for (var i = 0; i < lines.length; i++) {
      final found = _parcelaInLine(lines, i);
      if (found == null) continue;
      if (best == null || found.total > best.total) best = found;
    }
    return best;
  }

  static final RegExp _parcelaXY = RegExp(r'\b(\d{1,3})\s*/\s*(\d{1,3})\b');
  static final RegExp _parcelaDe = RegExp(r'\b(\d{1,3})\s+de\s+(\d{1,3})\b');
  static final RegExp _parcelaVezes =
      RegExp(r'\bem\s+(\d{1,3})\s*x\b|\b(\d{1,3})\s*x\b|\b(\d{1,3})\s*vezes\b');

  /// Palavras que caracterizam parcelamento (texto já sem acento).
  static final RegExp _parcelaHints =
      RegExp(r'(parc|prest|vezes|credito|cartao)');

  static ParcelaInfo? _parcelaInLine(List<String> lines, int index) {
    final raw = lines[index];
    final folded = _fold(raw);
    // 1) "PARCELA 2/10" ou "2/10" com contexto de parcela por perto.
    for (final m in _parcelaXY.allMatches(raw)) {
      final x = int.tryParse(m.group(1)!);
      final y = int.tryParse(m.group(2)!);
      if (!_parcelaValida(x, y)) continue;
      if (_pareceData(raw, m)) continue;
      if (_temContextoParcela(lines, index, folded)) {
        return ParcelaInfo(x!, y!);
      }
    }
    // 2) "PARCELA 2 DE 10" / "PRESTACAO 2 DE 10" (busca no texto dobrado:
    // cupons vêm em maiúsculas e o "DE" precisa casar sem case).
    for (final m in _parcelaDe.allMatches(folded)) {
      final x = int.tryParse(m.group(1)!);
      final y = int.tryParse(m.group(2)!);
      if (!_parcelaValida(x, y)) continue;
      if (_parcelaHints.hasMatch(folded) || folded.contains('de')) {
        return ParcelaInfo(x!, y!);
      }
    }
    // 3) "EM 10X" / "10 VEZES": total sem parcela atual — assume a 1ª.
    final mv = _parcelaVezes.firstMatch(folded);
    if (mv != null) {
      final y = int.tryParse(mv.group(1) ?? mv.group(2) ?? mv.group(3)!);
      if (_parcelaValida(1, y)) return ParcelaInfo(1, y!);
    }
    return null;
  }

  static bool _parcelaValida(int? x, int? y) {
    if (x == null || y == null) return false;
    if (y < 2 || y > maxParcelas) return false;
    if (x < 1 || x > y) return false;
    return true;
  }

  /// `true` se o match `x/y` parece parte de uma data (ano logo depois ou
  /// data válida na linha sem palavra de parcela explícita).
  static bool _pareceData(String line, Match m) {
    final after = line.substring(m.end);
    // Ano colado: "20/03/2026" → after começa com "/2026".
    if (RegExp(r'^\s*[/.\-]\s*\d{2,4}\b').hasMatch(after)) return true;
    if (_date.hasMatch(line)) {
      final folded = _fold(line);
      if (!folded.contains('parc') && !folded.contains('prest')) return true;
    }
    return false;
  }

  /// Contexto de parcela: palavra-chave na mesma linha ou nas vizinhas
  /// (o OCR às vezes quebra "PARCELA" e "2/10" em linhas distintas).
  static bool _temContextoParcela(
      List<String> lines, int index, String foldedLine) {
    if (_parcelaHints.hasMatch(foldedLine) || foldedLine.contains(' x')) {
      return true;
    }
    for (final j in [index - 1, index + 1]) {
      if (j < 0 || j >= lines.length) continue;
      if (_parcelaHints.hasMatch(_fold(lines[j]))) return true;
    }
    return false;
  }

  /// Sufixo canônico de parcela: "LOJA XYZ 2/10" (não duplica se já houver).
  static String withParcelaSuffix(String merchant, ParcelaInfo parcela) {
    final base = merchant.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (parseParcelaSuffix(base) != null) return base;
    return '$base ${parcela.atual}/${parcela.total}';
  }

  /// Lê o sufixo "x/y" do fim do estabelecimento ("LOJA XYZ 2/10").
  static ParcelaInfo? parseParcelaSuffix(String estabelecimento) {
    final m =
        RegExp(r'\b(\d{1,3})\s*/\s*(\d{1,3})\s*$').firstMatch(estabelecimento);
    if (m == null) return null;
    final x = int.tryParse(m.group(1)!);
    final y = int.tryParse(m.group(2)!);
    if (!_parcelaValida(x, y)) return null;
    return ParcelaInfo(x!, y!);
  }

  /// Nome base sem o sufixo "x/y" (memória de categoria e cópias futuras).
  static String stripParcelaSuffix(String estabelecimento) {
    return estabelecimento
        .replaceAll(RegExp(r'\s*\b\d{1,3}\s*/\s*\d{1,3}\s*$'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
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
  /// (tabela `merchants`): minúsculas, sem sufixo de parcela "x/y",
  /// sem pontuação/CNPJ/acentos.
  static String normalizeMerchant(String merchant) {
    final semParcela = stripParcelaSuffix(merchant);
    final folded =
        _fold(semParcela).replaceAll(RegExp(r'cnpj\s*:?\s*[\d.\-/]+'), '');
    return folded
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

}
