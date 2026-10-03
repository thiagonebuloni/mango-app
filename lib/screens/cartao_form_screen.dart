import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_locale.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../widgets/cartao_visual.dart';

/// Cadastro/edição de cartão de crédito — só dados não sensíveis: banco,
/// bandeira, nome escolhido pelo usuário, dia de fechamento e dia de
/// pagamento. Número, validade e nome do titular **nunca** são pedidos.
class CartaoFormScreen extends ConsumerStatefulWidget {
  /// `null` = cartão novo; preenchido = edição.
  final CartaoCredito? cartao;

  const CartaoFormScreen({super.key, this.cartao});

  @override
  ConsumerState<CartaoFormScreen> createState() => _CartaoFormScreenState();
}

class _CartaoFormScreenState extends ConsumerState<CartaoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final TextEditingController _banco;
  late BandeiraCartao _bandeira;
  late int _fechamento;
  late int _pagamento;
  bool _saving = false;

  bool get _edicao => widget.cartao != null;

  /// Bancos sugeridos abaixo do campo: preenchem o texto e escolhem a cor.
  static const List<String> _bancosSugeridos = [
    'Itaú',
    'Nubank',
    'Bradesco',
    'Santander',
    'Banco do Brasil',
    'Caixa',
    'Inter',
    'C6 Bank',
    'Banco Pan',
    'PicPay',
    'Sicredi',
    'Sicoob',
    'BTG Pactual',
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.cartao;
    _nome = TextEditingController(text: c?.nome ?? '');
    _banco = TextEditingController(text: c?.banco ?? '');
    _bandeira = c?.bandeira ?? BandeiraCartao.visa;
    _fechamento = c?.diaFechamento ?? 20;
    _pagamento = c?.diaPagamento ?? 27;
  }

  @override
  void dispose() {
    _nome.dispose();
    _banco.dispose();
    super.dispose();
  }

  /// Cartão com os valores atuais do formulário (alimenta a prévia).
  CartaoCredito get _atual => CartaoCredito(
        id: widget.cartao?.id,
        banco: _banco.text.trim(),
        bandeira: _bandeira,
        nome: _nome.text.trim(),
        diaFechamento: _fechamento,
        diaPagamento: _pagamento,
      );

  List<DropdownMenuItem<int>> _dias() => [
        for (var d = 1; d <= 31; d++)
          DropdownMenuItem(value: d, child: Text(d.toString().padLeft(2, '0'))),
      ];

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final notifier = ref.read(cartoesProvider.notifier);
    final cartao = _atual;
    if (_edicao) {
      await notifier.edit(cartao);
    } else {
      await notifier.add(cartao);
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text(context.strings.cartaoSalvo)),
    );
  }

  Future<void> _excluir() async {
    final cartao = widget.cartao;
    if (cartao == null || cartao.id == null) return;
    final s = context.strings;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.excluirCartao),
        content: Text(s.excluirCartaoMsg(cartao.nome)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.cancelar),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.excluir),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    await ref.read(cartoesProvider.notifier).delete(cartao.id!);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text(context.strings.cartaoExcluido)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(_edicao ? s.editarCartao : s.novoCartao),
        actions: [
          if (_edicao)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: s.excluir,
              onPressed: _saving ? null : _excluir,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Prévia ao vivo: muda conforme o usuário digita/escolhe.
            CartaoVisual(cartao: _atual, altura: 150),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nome,
              decoration: InputDecoration(
                labelText: s.nomeCartao,
                hintText: s.nomeCartaoHint,
              ),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? s.informeNomeCartao : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _banco,
              decoration: InputDecoration(
                labelText: s.banco,
                hintText: s.informeBanco,
              ),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? s.informeBanco : null,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in _bancosSugeridos)
                  ActionChip(
                    label: Text(b, style: const TextStyle(fontSize: 12)),
                    onPressed: () => setState(() => _banco.text = b),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(s.bandeira, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in BandeiraCartao.values)
                  ChoiceChip(
                    label: Text(s.bandeiraLabel(b.name)),
                    selected: _bandeira == b,
                    onSelected: (_) => setState(() => _bandeira = b),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _fechamento,
              decoration: InputDecoration(labelText: s.diaFechamento),
              items: _dias(),
              validator: (v) =>
                  (v == null || v < 1 || v > 31) ? s.diaInvalido : null,
              onChanged: (v) => setState(() => _fechamento = v ?? _fechamento),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _pagamento,
              decoration: InputDecoration(labelText: s.diaPagamento),
              items: _dias(),
              validator: (v) =>
                  (v == null || v < 1 || v > 31) ? s.diaInvalido : null,
              onChanged: (v) => setState(() => _pagamento = v ?? _pagamento),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.notifications_none, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.permissaoNotificacoes,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(s.salvarCartao),
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
