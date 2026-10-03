import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_locale.dart';
import '../l10n/l10n_format.dart';
import '../models/models.dart';
import '../services/receipt_parser.dart';
import '../services/receipt_photo.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Dados do OCR já com categoria sugerida.
class ReceiptDraftData {
  final ReceiptDraft draft;
  final Category categoria;
  final String fotoPath;

  const ReceiptDraftData(this.draft, this.categoria, this.fotoPath);
}

/// Formulário de lançamento: usado para entrada manual e também como etapa
/// de CONFIRMAÇÃO do que o OCR extraiu (o app nunca grava direto da foto).
class ExpenseFormScreen extends ConsumerStatefulWidget {
  final Expense? expense; // edição
  final ReceiptDraftData? fromDraft; // pré-preenchido pelo OCR
  final EntryKind tipoInicial; // despesa ou receita (novo lançamento)

  const ExpenseFormScreen({super.key, this.expense, this.tipoInicial = EntryKind.despesa})
      : fromDraft = null;

  // ignore: prefer_const_constructors_in_immutables
  ExpenseFormScreen.fromReceipt({
    super.key,
    required ReceiptDraft draft,
    required Category categoria,
    required String fotoPath,
  })  : expense = null,
        tipoInicial = EntryKind.despesa,
        fromDraft = ReceiptDraftData(draft, categoria, fotoPath);

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _valor;
  late final TextEditingController _estabelecimento;
  late final TextEditingController _descricao;
  late Category _categoria;
  late PaymentMethod _forma;
  late EntryKind _tipo;
  DateTime _dataHora = DateTime.now();

  /// Cartão de crédito vinculado ao lançamento (`null` = sem cartão); só
  /// aparece/preenche quando a forma de pagamento é Crédito.
  int? _cartaoId;

  bool get _isEdit => widget.expense != null;
  bool get _isReceita => _tipo == EntryKind.receita;

  /// Categoria padrão quando o tipo troca ou não há valor inicial válido.
  static Category _padraoPara(EntryKind tipo) =>
      tipo == EntryKind.receita ? Category.salario : Category.outros;

  /// Opções de categoria do formulário: só as do tipo atual.
  /// Em edição de lançamentos antigos (ex.: receita salva como "Outros"),
  /// mantém o valor atual como item extra para não quebrar o Dropdown.
  List<Category> get _opcoesCategoria {
    final opcoes = CategoryX.paraTipo(_tipo).toList();
    if (!opcoes.contains(_categoria)) opcoes.add(_categoria);
    return opcoes;
  }

  Category _categoriaInicial() {
    final e = widget.expense;
    if (e != null) return e.categoria;
    final d = widget.fromDraft;
    if (d != null) return d.categoria;
    return _padraoPara(widget.tipoInicial);
  }
  bool _saving = false;

  /// Caminho da foto do cupom **existente no aparelho**, para a miniatura da
  /// edição. `null` quando o lançamento não tem foto ou quando o arquivo já não
  /// está mais lá (cache limpo por uma versão antiga do app, backup restaurado
  /// sem a foto).
  String? _fotoExistente;

  /// `true` quando o lançamento foi salvo sem a foto do cupom porque a cópia
  /// falhou — a tela avisa depois de fechar o formulário.
  bool _fotoNaoGuardada = false;

  /// Estado dos campos no momento da abertura da tela: referência de
  /// [hasUnsavedChanges]. Um snapshot no `initState` evita comparar com
  /// `DateTime.now()`, que mudaria a cada chamada e marcaria todo form novo
  /// intocado como "com alterações não salvas".
  late final String _valorAbertura;
  late final String _estabelecimentoAbertura;
  late final String _descricaoAbertura;
  late final Category _categoriaAbertura;
  late final PaymentMethod _formaAbertura;
  late final EntryKind _tipoAbertura;
  late final DateTime _dataHoraAbertura;
  late final int? _cartaoIdAbertura;

  /// Aviso sob o campo estabelecimento quando há sufixo "x/y": quantos
  /// lançamentos mensais serão criados e com qual valor. Exibido em caixa
  /// própria (largura total, texto centralizado e com quebra de linha) para
  /// nunca ser cortado pelo fim da tela.
  String? get _parcelaAviso {
    // Editar um lançamento que já era parcelado só atualiza a linha (não
    // recria o grupo), então não há lançamento novo a avisar.
    if (_isEdit && _tinhaParcelaOriginal) return null;
    final parcela =
        ReceiptParser.parseParcelaSuffix(_estabelecimento.text.trim());
    if (parcela == null || parcela.total <= 1) return null;
    // No cadastro a última parcela (y/y) não gera cópias; na edição o grupo
    // inteiro é recriado, então "y/y" também vale.
    if (!_isEdit && parcela.atual >= parcela.total) return null;
    // Nº de linhas NOVAS: no cadastro criam-se de `atual` até `total`; na
    // edição o grupo 1..total (a linha editada já existe e vira a parcela
    // informada). O valor de cada parcela divide o total por todas as que
    // compõem o grupo (todas no cadastro a partir de `atual`; as `total` na
    // edição).
    final divisor = _isEdit ? parcela.total : parcela.total - parcela.atual + 1;
    final novos = _isEdit ? parcela.total - 1 : divisor;
    if (novos <= 0) return null;
    final s = context.strings;
    final de = _isEdit
        ? '1/${parcela.total}'
        : '${parcela.atual}/${parcela.total}';
    final ate = '${parcela.total}/${parcela.total}';
    final centavos = parseMoneyInput(_valor.text);
    if (centavos == null) {
      return s.parcelaAvisoSemValor(novos, de, ate);
    }
    final porParcela = centavos ~/ divisor;
    return s.parcelaAvisoComValor(novos,
        formatMoney(porParcela, Localizations.maybeLocaleOf(context)), de, ate);
  }

  /// Cartões cadastrados: alimenta o dropdown de vínculo quando a forma de
  /// pagamento é Crédito.
  List<CartaoCredito> get _cartoes =>
      ref.watch(cartoesProvider).value ?? const <CartaoCredito>[];

  /// Valor do dropdown de cartão: `null` quando nada foi escolhido ou quando
  /// o cartão escolhido já foi apagado (evita item fora das opções).
  int? _cartaoEfetivo(List<CartaoCredito> cartoes) =>
      cartoes.any((c) => c.id == _cartaoId) ? _cartaoId : null;

  /// `true` quando o lançamento aberto para edição já trazia um sufixo "x/y"
  /// no estabelecimento. Nesse caso a edição só atualiza a linha (não recria
  /// o grupo de parcelas) — é o oposto de "incluir o parcelamento".
  bool get _tinhaParcelaOriginal {
    final e = widget.expense;
    return e != null &&
        ReceiptParser.parseParcelaSuffix(e.estabelecimento.trim()) != null;
  }

  /// `true` quando o usuário alterou algo desde a abertura da tela.
  ///
  /// Compara com o snapshot salvo no [initState]; nunca com `DateTime.now()`
  /// (que mudaria a cada chamada e faria um form novo intocado ser sempre
  /// tratado como sujo, pedindo confirmação ao sair sem nenhuma alteração).
  bool get hasUnsavedChanges =>
      _valor.text != _valorAbertura ||
      _estabelecimento.text != _estabelecimentoAbertura ||
      _descricao.text != _descricaoAbertura ||
      _categoria != _categoriaAbertura ||
      _forma != _formaAbertura ||
      _tipo != _tipoAbertura ||
      _dataHora != _dataHoraAbertura ||
      _cartaoId != _cartaoIdAbertura;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    final d = widget.fromDraft;
    final total = e?.valorCentavos ?? d?.draft.totalCentavos;
    // Começa em "0,00": a máscara preenche dos centavos para cima, então o
    // campo nunca abre vazio nem aceita valor formatado "na mão".
    _valor = TextEditingController(text: formatMoneyInput(total ?? 0));
    _estabelecimento = TextEditingController(
        text: e?.estabelecimento ?? d?.draft.estabelecimento ?? '');
    _descricao = TextEditingController(text: e?.descricao ?? '');
    _tipo = e?.tipo ?? widget.tipoInicial;
    final inicial = _categoriaInicial();
    // Garante que a categoria inicial pertence ao tipo (ex.: trocar o tipo
    // reinicia para um valor válido; OCR sempre cai em despesa).
    _categoria =
        CategoryX.paraTipo(_tipo).contains(inicial) ? inicial : _padraoPara(_tipo);
    _forma = e?.forma ?? d?.draft.pagamento ?? PaymentMethod.outros;
    _dataHora = e?.dataHora ?? d?.draft.dataHora ?? DateTime.now();
    _cartaoId = e?.cartaoId;
    _valorAbertura = _valor.text;
    _estabelecimentoAbertura = _estabelecimento.text;
    _descricaoAbertura = _descricao.text;
    _categoriaAbertura = _categoria;
    _formaAbertura = _forma;
    _tipoAbertura = _tipo;
    _dataHoraAbertura = _dataHora;
    _cartaoIdAbertura = _cartaoId;
    _carregarFotoExistente();
  }

  /// Confere se a foto do cupom do lançamento em edição ainda existe no
  /// aparelho antes de montar a miniatura: evita `Image.file` apontando para
  /// arquivo que não está mais lá.
  Future<void> _carregarFotoExistente() async {
    final path = widget.expense?.fotoPath;
    if (path == null || path.trim().isEmpty) return;
    try {
      if (await File(path).exists() && mounted) {
        setState(() => _fotoExistente = path);
      }
    } catch (_) {
      // Foto ilegível não impede a edição: a tela segue sem a miniatura.
    }
  }

  @override
  void dispose() {
    _valor.dispose();
    _estabelecimento.dispose();
    _descricao.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final first = DateTime(2020);
    final last = DateTime.now().add(const Duration(days: 1));
    // Garante initialDate dentro do intervalo: fora dele o
    // showDatePicker falha em assertion e o seletor "não abre".
    final initial = _dataHora.isBefore(first)
        ? first
        : (_dataHora.isAfter(last) ? last : _dataHora);
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dataHora),
    );
    if (!mounted) return;
    // Ao cancelar o seletor de hora, mantém a hora/minuto originais em vez
    // de forçar 12:00 (o `_dataHora` só é trocado no setState abaixo).
    setState(() {
      _dataHora = DateTime(date.year, date.month, date.day,
          time?.hour ?? _dataHora.hour, time?.minute ?? _dataHora.minute);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final centavos = parseMoneyInput(_valor.text)!;
    // A foto do cupom (quando veio do OCR) é copiada para os documentos do app
    // só agora: cancelar o formulário não deixa arquivo órfão.
    final base = widget.expense ?? await _buildNew();
    final novo = base.copyWith(
      valorCentavos: centavos,
      dataHora: _dataHora,
      categoria: _categoria,
      forma: _forma,
      tipo: _tipo,
      descricao: _descricao.text.trim(),
      estabelecimento: _estabelecimento.text.trim(),
      cartaoId: _forma == PaymentMethod.credito ? _cartaoId : null,
    );

    final notifier = ref.read(expensesProvider.notifier);
    int criados = 1;
    if (_isEdit) {
      // Incluir o parcelamento num gasto já lançado recria o grupo (parcelas
      // passadas e futuras); se ele já era parcelado, só atualiza a linha.
      criados = await notifier.edit(novo,
          expandirParcelamento: !_tinhaParcelaOriginal);
    } else {
      criados = await notifier.add(novo);
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final s = context.strings;
    Navigator.of(context).pop();
    // Avisos aparecem na tela anterior (Home).
    if (_fotoNaoGuardada) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.lancamentoSalvoFotoNao)),
      );
    }
    // Aviso de parcelamento vale no cadastro e ao incluir o parcelamento numa
    // edição (nos dois casos `criados > 1`).
    if (criados > 1) {
      final parcela = ReceiptParser.parseParcelaSuffix(novo.estabelecimento);
      messenger.showSnackBar(
        SnackBar(
          content: Text(s.parcelaSalva(
              parcela!.atual, parcela.total, criados)),
        ),
      );
    }
  }

  Future<Expense> _buildNew() async {
    final d = widget.fromDraft;
    return Expense(
      valorCentavos: 0,
      dataHora: _dataHora,
      categoria: _categoria,
      forma: _forma,
      tipo: _tipo,
      origem: d != null ? ExpenseOrigin.ocr : ExpenseOrigin.manual,
      fotoPath: await _guardarFotoDoCupom(),
      rawText: d?.draft.textoOcr,
    );
  }

  /// Copia a foto do cupom do cache do `image_picker` para os documentos do
  /// app e devolve o caminho definitivo — `null` quando não há foto (lançamento
  /// manual) ou quando a cópia falha.
  ///
  /// A cópia temporária só é apagada depois que a definitiva existe: o OCR já
  /// rodou e, a partir daqui, a foto oficial é a dos documentos do app
  /// (`lib/services/receipt_photo.dart`).
  Future<String?> _guardarFotoDoCupom() async {
    final origem = widget.fromDraft?.fotoPath;
    if (origem == null || origem.trim().isEmpty) return null;
    try {
      final destino =
          await salvarFotoCupom(File(origem), await pastaFotosCupom());
      await apagarCopiaTemporaria(origem);
      return destino;
    } catch (_) {
      _fotoNaoGuardada = true;
      return null;
    }
  }

  Future<bool> _showCancelConfirmation() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(context.strings.cancelarLancamento),
        content: Text(context.strings.cancelarLancamentoMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.strings.continuarEditando),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.strings.simCancelar),
          ),
        ],
      ),
    ).then<bool>((value) => value ?? false);
  }


  @override
  Widget build(BuildContext context) {
    final d = widget.fromDraft;
    final s = context.strings;
    return PopScope(
      canPop: !hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // O usuário tentou voltar com mudanças não salvas — pedir confirmação.
        if (!hasUnsavedChanges) {
          Navigator.of(this.context).pop();
          return;
        }
        final confirmed = await _showCancelConfirmation();
        if (confirmed == true && mounted) {
          Navigator.of(this.context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit
              ? (_isReceita ? s.editarReceita : s.editarGasto)
              : (_isReceita ? s.novaReceita : s.novaDespesa)),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!_isEdit && d == null)
                SegmentedButton<EntryKind>(
                  segments: [
                    ButtonSegment(
                      value: EntryKind.despesa,
                      icon: const Icon(Icons.shopping_cart_outlined),
                      label: Text(s.despesa),
                    ),
                    ButtonSegment(
                      value: EntryKind.receita,
                      icon: const Icon(Icons.attach_money),
                      label: Text(s.receita),
                    ),
                  ],
                  selected: {_tipo},
                  onSelectionChanged: (sel) {
                    final novo = sel.first;
                    setState(() {
                      _tipo = novo;
                      // Trocar despesa ↔ receita reinicia para uma categoria
                      // válida do novo tipo (listas são disjuntas).
                      _categoria = _padraoPara(novo);
                    });
                  },
                ),
              if (!_isEdit && d == null) const SizedBox(height: 8),
              if (d != null) ...[
                Builder(
                  builder: (context) {
                    final primary = Theme.of(context).colorScheme.primary;
                    return Card(
                      color: primary.withValues(alpha: 0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.receipt_long, color: primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.dadosExtraidos,
                                style: TextStyle(color: primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
              TextFormField(
                controller: _valor,
                decoration: InputDecoration(
                  labelText: s.valorLabel(s.currencySymbol),
                  prefixText: '${s.currencySymbol} ',
                  hintText: s.valorHint,
                ),
                // Sem decimal no teclado: a vírgula é colocada pela máscara,
                // não digitada (a máscara descarta ponto e vírgula de
                // qualquer forma).
                keyboardType: TextInputType.number,
                inputFormatters: const [CurrencyInputFormatter()],
                validator: (v) => parseMoneyInput(v ?? '') == null
                    ? s.informeValor
                    : null,
                autofocus: !_isEdit && d == null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _estabelecimento,
                decoration: InputDecoration(
                    labelText:
                        _isReceita ? s.origem : s.estabelecimento),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
              ),
              if (_parcelaAviso != null) ...[
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final primary = Theme.of(context).colorScheme.primary;
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _parcelaAviso!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: primary),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _descricao,
                decoration:
                    InputDecoration(labelText: s.descricaoOpcional),
                textCapitalization: TextCapitalization.sentences,
                // Precisa de setState: sem rebuild, o canPop do PopScope não
                // atualiza e a saída perderia o texto digitado sem perguntar.
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Category>(
                key: ValueKey(_tipo),
                initialValue: _categoria,
                decoration: InputDecoration(labelText: s.categoria),
                items: [
                  for (final c in _opcoesCategoria)
                    DropdownMenuItem(
                        value: c, child: Text(categoryLabelOf(context, c))),
                ],
                onChanged: (c) => setState(() => _categoria = c!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PaymentMethod>(
                initialValue: _forma,
                decoration:
                    InputDecoration(labelText: s.formaPagamento),
                items: [
                  for (final p in PaymentMethod.values)
                    DropdownMenuItem(
                        value: p, child: Text(paymentLabelOf(context, p))),
                ],
                onChanged: (p) => setState(() {
                  _forma = p!;
                  // Fora do crédito o vínculo com cartão não faz sentido.
                  if (_forma != PaymentMethod.credito) _cartaoId = null;
                }),
              ),
              if (_forma == PaymentMethod.credito && _cartoes.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: _cartaoEfetivo(_cartoes),
                  decoration: InputDecoration(labelText: s.campoCartao),
                  items: [
                    DropdownMenuItem<int?>(
                        value: null, child: Text(s.semCartao)),
                    for (final c in _cartoes)
                      DropdownMenuItem<int?>(
                        value: c.id,
                        child: Text('${c.nome} · ${c.banco}'),
                      ),
                  ],
                  onChanged: (id) => setState(() => _cartaoId = id),
                ),
              ],
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(s.dataHora),
                subtitle: Text(
                  formatDate(_dataHora, (p) => p.dayMonthYearTime),
                ),
                trailing: const Icon(Icons.edit_calendar),
                onTap: _pickDate,
              ),
              if (d != null)
                ExpansionTile(
                  leading: const Icon(Icons.text_snippet),
                  title: Text(s.textoCupom),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(d.draft.textoOcr,
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              if (_fotoExistente != null) ...[
                const SizedBox(height: 8),
                _FotoCupomCard(_fotoExistente!),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(_isEdit
                    ? s.salvarAlteracoes
                    : (_isReceita ? s.salvarReceita : s.salvarGasto)),
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Miniatura da foto do cupom no formulário de edição: toque para ampliar.
///
/// A foto foi copiada para os documentos do app quando o lançamento do OCR foi
/// salvo (`lib/services/receipt_photo.dart`); o `errorBuilder` cobre o caso do
/// arquivo existir mas não poder ser decodificado (imagem corrompida, por
/// exemplo), em vez de derrubar o build da tela.
class _FotoCupomCard extends StatelessWidget {
  final String caminho;

  const _FotoCupomCard(this.caminho);

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.file(
                File(caminho),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(context.strings.fotoCupomErro),
                ),
              ),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 160,
              width: double.infinity,
              child: Image.file(
                File(caminho),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(context.strings.fotoCupomErro),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(context.strings.fotoCupom),
              subtitle: Text(context.strings.toqueAmpliar),
            ),
          ],
        ),
      ),
    );
  }
}
