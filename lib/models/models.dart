// Modelos de domínio do app Mango.

/// Categorias de lançamento (pré-definidas para manter o app leve e simples).
///
/// Despesas: alimentação, transporte, mercado, saúde, lazer, moradia e outros.
/// Receitas: salário, investimentos, bonificação, freelance, renda extra,
/// aluguel e pensão.
enum Category {
  alimentacao,
  transporte,
  mercado,
  saude,
  lazer,
  moradia,
  outros,
  salario,
  investimentos,
  bonificacao,
  freelance,
  rendaExtra,
  aluguel,
  pensao,
}

extension CategoryX on Category {
  /// Categorias oferecidas no formulário de despesa.
  static const List<Category> despesas = [
    Category.alimentacao,
    Category.transporte,
    Category.mercado,
    Category.saude,
    Category.lazer,
    Category.moradia,
    Category.outros,
  ];

  /// Categorias oferecidas no formulário de receita.
  static const List<Category> receitas = [
    Category.salario,
    Category.investimentos,
    Category.bonificacao,
    Category.freelance,
    Category.rendaExtra,
    Category.aluguel,
    Category.pensao,
  ];

  /// `true` para categorias de receita, `false` para categorias de despesa.
  bool get isReceita => CategoryX.receitas.contains(this);

  /// Categorias válidas para o [tipo] de lançamento.
  static List<Category> paraTipo(EntryKind tipo) =>
      tipo == EntryKind.receita ? receitas : despesas;

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
      case Category.salario:
        return 'Salário';
      case Category.investimentos:
        return 'Investimentos';
      case Category.bonificacao:
        return 'Bonificação';
      case Category.freelance:
        return 'Freelance';
      case Category.rendaExtra:
        return 'Renda extra';
      case Category.aluguel:
        return 'Aluguel';
      case Category.pensao:
        return 'Pensão';
    }
  }

  static Category fromName(String? name, {EntryKind? tipo}) {
    final found = Category.values
        .where((c) => c.name == name)
        .cast<Category?>();
    final exact = found.isEmpty ? null : found.first;
    if (exact != null) return exact;
    // Migração de dados antigos: receita salva com categoria de despesa
    // ("Outros") vira Salário; despesa salva com categoria de receita
    // (não deveria acontecer) volta para Outros.
    if (tipo == EntryKind.receita) return Category.salario;
    return Category.outros;
  }
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

/// Tipo do lançamento: despesa ou receita.
enum EntryKind { despesa, receita }

extension EntryKindX on EntryKind {
  String get label => switch (this) {
        EntryKind.despesa => 'Despesa',
        EntryKind.receita => 'Receita',
      };

  static EntryKind fromName(String? name) =>
      EntryKind.values.firstWhere((k) => k.name == name,
          orElse: () => EntryKind.despesa);
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
  final EntryKind tipo;
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
    this.tipo = EntryKind.despesa,
    this.fotoPath,
    this.rawText,
  });

  /// Atalho de leitura: receitas somam, despesas subtraem.
  bool get isReceita => tipo == EntryKind.receita;

  /// Chave de duplicidade usada na importação de backup CSV: dois
  /// lançamentos com a mesma chave são o mesmo registro (independente do
  /// id gerado pelo banco). Todos os campos persistidos no CSV participam,
  /// e a data entra em milissegundos para sobreviver ao export/import.
  ///
  /// Os campos de texto entram como `tamanho:valor`: o prefixo de tamanho
  /// torna a codificação injetiva, então um `|` dentro da descrição ou do
  /// estabelecimento não consegue colidir com o separador (ex.: descrição
  /// "a" + estab "b|c" x descrição "a|b" + estab "c").
  String get chaveUnica => [
        tipo.name,
        valorCentavos,
        dataHora.millisecondsSinceEpoch,
        categoria.name,
        forma.name,
        _campoComTamanho(descricao),
        _campoComTamanho(estabelecimento),
        origem.name,
      ].join('|');

  /// Prefixa um campo de texto com o comprimento: codificação injetiva,
  /// imune a colisão com o separador `|` usado em [chaveUnica].
  static String _campoComTamanho(String valor) => '${valor.length}:$valor';

  Expense copyWith({
    int? id,
    int? valorCentavos,
    DateTime? dataHora,
    Category? categoria,
    PaymentMethod? forma,
    String? descricao,
    String? estabelecimento,
    ExpenseOrigin? origem,
    EntryKind? tipo,
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
        tipo: tipo ?? this.tipo,
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
        'tipo': tipo.name,
        'foto': fotoPath,
        'raw': rawText,
      };

  static Expense fromMap(Map<String, Object?> map) => Expense(
        id: map['id'] as int?,
        valorCentavos: map['valor'] as int,
        dataHora:
            DateTime.fromMillisecondsSinceEpoch(map['data_hora'] as int),
        categoria: CategoryX.fromName(
          map['categoria'] as String?,
          tipo: EntryKindX.fromName(map['tipo'] as String?),
        ),
        forma: PaymentMethodX.fromName(map['forma'] as String?),
        descricao: (map['descricao'] as String?) ?? '',
        estabelecimento: (map['estabelecimento'] as String?) ?? '',
        origem: (map['origem'] as String?) == 'ocr'
            ? ExpenseOrigin.ocr
            : ExpenseOrigin.manual,
        tipo: EntryKindX.fromName(map['tipo'] as String?),
        fotoPath: map['foto'] as String?,
        rawText: map['raw'] as String?,
      );

  @override
  String toString() =>
      'Expense(id: $id, tipo: ${tipo.name}, valor: $valorCentavos, categoria: ${categoria.name}, '
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

/// Perfil do usuário, exibido na tela inicial e salvo em uma única linha da
/// tabela `profile` (app local: sem login, sem servidor).
class UserProfile {
  final String nome;
  /// Emoticon escolhido (ex.: '🦊'). Usado quando não há foto
  /// ([avatarImagePath] == null) ou a foto não pode ser lida.
  final String avatar;
  final int corFundo; // cor de fundo da tela inicial, em ARGB
  /// `true` = tema claro; `false` = tema escuro (padrão do app).
  final bool temaClaro;
  /// Caminho local da foto do avatar (cópia dentro dos documentos do app).
  /// `null` = usar o emoticon [avatar].
  final String? avatarImagePath;
  /// Posição do recorte da foto (-1..1 em cada eixo, como [Alignment]).
  final double avatarAlignX;
  final double avatarAlignY;
  /// Zoom aplicado sobre a foto (1 = sem zoom).
  final double avatarZoom;

  const UserProfile({
    required this.nome,
    required this.avatar,
    required this.corFundo,
    this.temaClaro = false,
    this.avatarImagePath,
    this.avatarAlignX = 0,
    this.avatarAlignY = 0,
    this.avatarZoom = 1,
  });

  /// Valores usados quando o usuário ainda não escolheu nada.
  static const String avatarPadrao = '🐸';
  static const int corFundoPadrao = 0xFFE0F2F1;
  static const int corFundoEscuroPadrao = 0xFF33393B;
  /// Cor de fundo padrão do app (tema escuro).
  static const int corFundoInicialPadrao = corFundoEscuroPadrao;

  /// Limite de caracteres do nome (mesmo da tela de perfil, que usa
  /// [nomeMaxLength] no `maxLength` do campo).
  static const int nomeMaxLength = 24;

  /// Limite de caracteres do avatar (emoticon). A tela de perfil só oferece
  /// emoticons de um caractere; o teto protege o app de um backup editado à
  /// mão com um "avatar" de megabytes.
  static const int avatarMaxLength = 16;

  /// `true` quando [valor] pode ser cor de fundo: ARGB de 32 bits com
  /// **opacidade total**.
  ///
  /// `Color(v)` usa `v >> 24`, `v >> 16`, `v >> 8` e `v` (só os 8 bits de
  /// baixo de cada componente, sem avisar), então valores fora dessa faixa
  /// não quebram: viram outra cor. O caso ruim é a transparência —
  /// `cor=0`, `cor=4294967296` (2^32) e negativos dão fundo **invisível**, e
  /// o texto por cima (escolhido por contraste com o preto) some junto.
  static bool corFundoValida(int valor) =>
      valor >= 0 && valor <= 0xFFFFFFFF && (valor & 0xFF000000) == 0xFF000000;

  /// Nome no formato que o app aceita: sem caracteres de controle, com
  /// espaços colapsados e no máximo [nomeMaxLength] caracteres.
  ///
  /// A tela de perfil já limita o que o usuário digita; um backup editado à
  /// mão, porém, entrava inteiro (nome de centenas de milhares de
  /// caracteres), e a tela inicial refaz o layout desse texto a cada rebuild.
  ///
  /// O corte conta *runes* (pontos de código), não grafemas como o
  /// `maxLength` do campo: um nome só de emojis compostos (ex.: 🏳️‍🌈) pode
  /// sair um pouco mais curto que o digitado. Limitar demais é inofensivo —
  /// o que não pode é aceitar tamanho arbitrário de um arquivo de fora.
  static String sanitizarNome(String? bruto) => _textoCurto(bruto, nomeMaxLength);

  /// Avatar no formato que o app aceita (ver [avatarMaxLength]).
  static String sanitizarAvatar(String? bruto) =>
      _textoCurto(bruto, avatarMaxLength);

  static final RegExp _controle = RegExp(r'[\u0000-\u001F\u007F]');
  static final RegExp _espacos = RegExp(r'\s+');

  static String _textoCurto(String? bruto, int max) {
    if (bruto == null) return '';
    final colapsado = bruto
        .replaceAll(_controle, ' ')
        .replaceAll(_espacos, ' ')
        .trim();
    // Corta por *runes* (pontos de código), não por unidades UTF-16: cortar no
    // meio de um par substituto produziria um caractere inválido (�).
    final runes = colapsado.runes;
    return runes.length <= max
        ? colapsado
        : String.fromCharCodes(runes.take(max));
  }

  /// `true` quando há uma foto de avatar para exibir em vez do emoticon.
  bool get temFoto =>
      avatarImagePath != null && avatarImagePath!.trim().isNotEmpty;

  UserProfile copyWith({
    String? nome,
    String? avatar,
    int? corFundo,
    bool? temaClaro,
    String? Function()? avatarImagePath,
    double? avatarAlignX,
    double? avatarAlignY,
    double? avatarZoom,
  }) =>
      UserProfile(
        nome: nome ?? this.nome,
        avatar: avatar ?? this.avatar,
        corFundo: corFundo ?? this.corFundo,
        temaClaro: temaClaro ?? this.temaClaro,
        avatarImagePath:
            avatarImagePath != null ? avatarImagePath() : this.avatarImagePath,
        avatarAlignX: avatarAlignX ?? this.avatarAlignX,
        avatarAlignY: avatarAlignY ?? this.avatarAlignY,
        avatarZoom: avatarZoom ?? this.avatarZoom,
      );

  Map<String, Object?> toMap() => {
        'id': 1, // linha única
        'nome': nome,
        'avatar': avatar,
        'cor': corFundo,
        'tema_claro': temaClaro ? 1 : 0,
        'avatar_img': avatarImagePath,
        'avatar_ax': avatarAlignX,
        'avatar_ay': avatarAlignY,
        'avatar_zoom': avatarZoom,
      };

  static UserProfile fromMap(Map<String, Object?> map) => UserProfile(
        nome: (map['nome'] as String?) ?? '',
        avatar: (map['avatar'] as String?) ?? avatarPadrao,
        corFundo: (map['cor'] as int?) ?? corFundoInicialPadrao,
        temaClaro: switch (map['tema_claro']) {
          final int v => v != 0,
          final bool v => v,
          _ => false, // perfis antigos sem tema: passam ao padrão escuro
        },
        avatarImagePath: (map['avatar_img'] as String?)?.trim().isEmpty ?? true
            ? null
            : map['avatar_img'] as String?,
        avatarAlignX: switch (map['avatar_ax']) {
          final num v => v.toDouble().clamp(-1.0, 1.0),
          _ => 0,
        },
        avatarAlignY: switch (map['avatar_ay']) {
          final num v => v.toDouble().clamp(-1.0, 1.0),
          _ => 0,
        },
        avatarZoom: switch (map['avatar_zoom']) {
          final num v => v.toDouble().clamp(1.0, 3.0),
          _ => 1,
        },
      );

  @override
  String toString() =>
      'UserProfile(nome: $nome, avatar: $avatar, cor: $corFundo, '
      'temaClaro: $temaClaro, foto: $avatarImagePath)';
}
