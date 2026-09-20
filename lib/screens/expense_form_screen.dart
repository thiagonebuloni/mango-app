import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
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

  const ExpenseFormScreen({super.key, this.expense}) : fromDraft = null;

  // ignore: prefer_const_constructors_in_immutables
  ExpenseFormScreen.fromReceipt({
    super.key,
    required ReceiptDraft draft,
    required Category categoria,
    required String fotoPath,
  })  : expense = null,
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
  DateTime _dataHora = DateTime.now();

  bool get _isEdit => widget.expense != null;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    final d = widget.fromDraft;
    final total = e?.valorCentavos ?? d?.draft.totalCentavos;
    _valor = TextEditingController(
      text: total != null
          ? (total / 100).toStringAsFixed(2).replaceAll('.', ',')
          : '',
    );
    _estabelecimento = TextEditingController(
        text: e?.estabelecimento ?? d?.draft.estabelecimento ?? '');
    _descricao = TextEditingController(text: e?.descricao ?? '');
    _categoria = e?.categoria ?? d?.categoria ?? Category.outros;
    _forma = e?.forma ?? d?.draft.pagamento ?? PaymentMethod.outros;
    _dataHora = e?.dataHora ?? d?.draft.dataHora ?? DateTime.now();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dataHora,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('pt', 'BR'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dataHora),
    );
    if (!mounted) return;
    setState(() {
      _dataHora = DateTime(date.year, date.month, date.day,
          time?.hour ?? 12, time?.minute ?? 0);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final centavos = parseMoneyInput(_valor.text)!;
    final novo = (widget.expense ?? _buildNew()).copyWith(
      valorCentavos: centavos,
      dataHora: _dataHora,
      categoria: _categoria,
      forma: _forma,
      descricao: _descricao.text.trim(),
      estabelecimento: _estabelecimento.text.trim(),
    );

    final notifier = ref.read(expensesProvider.notifier);
    if (_isEdit) {
      await notifier.edit(novo);
    } else {
      await notifier.add(novo);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Expense _buildNew() {
    final d = widget.fromDraft;
    return Expense(
      valorCentavos: 0,
      dataHora: _dataHora,
      categoria: _categoria,
      forma: _forma,
      origem: d != null ? ExpenseOrigin.ocr : ExpenseOrigin.manual,
      fotoPath: d?.fotoPath,
      rawText: d?.draft.textoOcr,
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.fromDraft;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar gasto' : 'Novo gasto'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (d != null) ...[
              Card(
                color: Colors.teal.withValues(alpha: 0.08),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long, color: Colors.teal),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Dados extraídos do cupom.\nConfira antes de salvar.',
                          style: TextStyle(color: Colors.teal),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextFormField(
              controller: _valor,
              decoration: const InputDecoration(
                labelText: 'Valor (R\$)',
                prefixText: 'R\$ ',
                hintText: '0,00',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              ],
              validator: (v) =>
                  parseMoneyInput(v ?? '') == null ? 'Informe o valor' : null,
              autofocus: !_isEdit && d == null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _estabelecimento,
              decoration: const InputDecoration(labelText: 'Estabelecimento'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descricao,
              decoration:
                  const InputDecoration(labelText: 'Descrição (opcional)'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Category>(
              initialValue: _categoria,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: [
                for (final c in Category.values)
                  DropdownMenuItem(value: c, child: Text(c.label)),
              ],
              onChanged: (c) => setState(() => _categoria = c!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PaymentMethod>(
              initialValue: _forma,
              decoration:
                  const InputDecoration(labelText: 'Forma de pagamento'),
              items: [
                for (final p in PaymentMethod.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: (p) => setState(() => _forma = p!),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Data e hora'),
              subtitle: Text(
                  DateFormat('dd/MM/yyyy  HH:mm', 'pt_BR').format(_dataHora)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: _pickDate,
            ),
            if (d != null)
              ExpansionTile(
                leading: const Icon(Icons.text_snippet),
                title: const Text('Texto lido do cupom'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(d.draft.textoOcr,
                        style: const TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_isEdit ? 'Salvar alterações' : 'Salvar gasto'),
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
