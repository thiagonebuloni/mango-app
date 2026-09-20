// Modelos de domínio do app Financ.

/// Categorias de gasto (pré-definidas para manter o app leve e simples).
enum Category {
  alimentacao,
  transporte,
  mercado,
  saude,
  lazer,
  moradia,
  outros,
}

extension CategoryX on Category {
  String get label {
    switch (this) {
      case Category.alimentacao:
        return 'Alimentação';
      case Category.transporte:
        return 'Transporte';
      case Category.mercado:
        return 'Mercado';
      case Category.saude:
        return 'Saúde';
      case Category.lazer:
        return 'Lazer';
      case Category.moradia:
        return 'Moradia';
      case Category.outros:
        return 'Outros';
    }
  }

  static Category fromName(String? name) =>
      Category.values.firstWhere((c) => c.name == name,
          orElse: () => Category.outros);
}

/// Formas de pagamento suportadas (vocábulo dos cupons brasileiros).
enum PaymentMethod {
  dinheiro,
  debito,
  credito,
  pix,
  outros,
}

extension PaymentMethodX on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.dinheiro:
        return 'Dinheiro';
      case PaymentMethod.debito:
        return 'Débito';
      case PaymentMethod.credito:
        return 'Crédito';
      case PaymentMethod.pix:
        return 'PIX';
      case PaymentMethod.outros:
        return 'Outros';
    }
  }

  static PaymentMethod fromName(String? name) =>
      PaymentMethod.values.firstWhere((p) => p.name == name,
          orElse: () => PaymentMethod.outros);
}

/// Origem do lançamento.
enum ExpenseOrigin { manual, ocr }

/// Um gasto registrado. Valores são armazenados em centavos (int) para
/// evitar erros de ponto flutuante.
class Expense {
  final int? id;
  final int valorCentavos;
  final DateTime dataHora;
  final Category categoria;
  final PaymentMethod forma;
  final String descricao;
  final String estabelecimento;
  final ExpenseOrigin origem;
  final String? fotoPath; // caminho da foto do cupom (opcional)
  final String? rawText; // texto OCR bruto (opcional)

  const Expense({
    this.id,
    required this.valorCentavos,
    required this.dataHora,
    required this.categoria,
    required this.forma,
    this.descricao = '',
    this.estabelecimento = '',
    this.origem = ExpenseOrigin.manual,
    this.fotoPath,
    this.rawText,
  });

  Expense copyWith({
    int? id,
    int? valorCentavos,
    DateTime? dataHora,
    Category? categoria,
    PaymentMethod? forma,
    String? descricao,
    String? estabelecimento,
    ExpenseOrigin? origem,
    String? fotoPath,
    String? rawText,
  }) =>
      Expense(
        id: id ?? this.id,
        valorCentavos: valorCentavos ?? this.valorCentavos,
        dataHora: dataHora ?? this.dataHora,
        categoria: categoria ?? this.categoria,
        forma: forma ?? this.forma,
        descricao: descricao ?? this.descricao,
        estabelecimento: estabelecimento ?? this.estabelecimento,
        origem: origem ?? this.origem,
        fotoPath: fotoPath ?? this.fotoPath,
        rawText: rawText ?? this.rawText,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'valor': valorCentavos,
        'data_hora': dataHora.millisecondsSinceEpoch,
        'categoria': categoria.name,
        'forma': forma.name,
        'descricao': descricao,
        'estabelecimento': estabelecimento,
        'origem': origem.name,
        'foto': fotoPath,
        'raw': rawText,
      };

  static Expense fromMap(Map<String, Object?> map) => Expense(
        id: map['id'] as int?,
        valorCentavos: map['valor'] as int,
        dataHora:
            DateTime.fromMillisecondsSinceEpoch(map['data_hora'] as int),
        categoria: CategoryX.fromName(map['categoria'] as String?),
        forma: PaymentMethodX.fromName(map['forma'] as String?),
        descricao: (map['descricao'] as String?) ?? '',
        estabelecimento: (map['estabelecimento'] as String?) ?? '',
        origem: (map['origem'] as String?) == 'ocr'
            ? ExpenseOrigin.ocr
            : ExpenseOrigin.manual,
        fotoPath: map['foto'] as String?,
        rawText: map['raw'] as String?,
      );

  @override
  String toString() =>
      'Expense(id: $id, valor: $valorCentavos, categoria: ${categoria.name}, '
      'data: $dataHora, estabelecimento: $estabelecimento)';
}

/// Item extraído de um cupom fiscal (apenas informativo, por enquanto).
class ReceiptItem {
  final String nome;
  final int qtd;
  final int valorCentavos;

  const ReceiptItem({required this.nome, this.qtd = 1, required this.valorCentavos});

  @override
  String toString() => 'ReceiptItem($nome x$qtd = $valorCentavos)';
}

/// Rascunho estruturado extraído de um cupom via OCR + parser.
class ReceiptDraft {
  final String? estabelecimento;
  final DateTime? dataHora;
  final int? totalCentavos;
  final PaymentMethod? pagamento;
  final List<ReceiptItem> itens;
  final String textoOcr;

  const ReceiptDraft({
    this.estabelecimento,
    this.dataHora,
    this.totalCentavos,
    this.pagamento,
    this.itens = const [],
    required this.textoOcr,
  });

  @override
  String toString() =>
      'ReceiptDraft(estabelecimento: $estabelecimento, data: $dataHora, '
      'total: $totalCentavos, pagamento: ${pagamento?.name}, itens: ${itens.length})';
}
