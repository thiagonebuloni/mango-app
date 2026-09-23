import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../db/db.dart';
import '../models/models.dart';
import '../screens/expense_form_screen.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Filtro rápido da lista de gastos pelos cards de resumo.
enum _FiltroRapido { dia, semana, mes }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Mês em exibição (dia 1). Começa no mês atual; o usuário pode voltar
  /// para meses anteriores e avançar até o mês atual.
  late DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);

  /// Filtro rápido ativo (Dia/Semana/Mês). `null` = mostra gastos do mês.
  _FiltroRapido? _filtro;

  /// Mês selecionado no diálogo ano→mês (passo 2 de [_pickMonth]).
  late int _dialogYear;
  late int _dialogMonth;

  DateTime get _monthStart => DateTime(_visibleMonth.year, _visibleMonth.month);
  DateTime get _monthEnd =>
      DateTime(_visibleMonth.year, _visibleMonth.month + 1);

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _visibleMonth.year == now.year && _visibleMonth.month == now.month;
  }

  void _previousMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
      _filtro = null;
    });
  }

  void _nextMonth() {
    if (_isCurrentMonth) return;
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
      _filtro = null;
    });
  }

  /// Seletor de mês em 2 passos (só ano + mês, sem escolher dia):
  /// 1º mostra os anos, 2º mostra os 12 meses do ano escolhido.
  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final minYear = 2020;
    final maxYear = now.year;

    // ---- passo 1: ano ----
    _dialogYear = _visibleMonth.year;
    final year = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Selecionar ano'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: maxYear - minYear + 1,
            itemBuilder: (context, i) {
              final y = maxYear - i;
              final selected = y == _dialogYear;
              return ListTile(
                title: Text(
                  '$y',
                  style: TextStyle(
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: selected ? const Icon(Icons.check) : null,
                selected: selected,
                onTap: () => Navigator.of(dialogContext).pop(y),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (year == null || !mounted) return;

    // ---- passo 2: mês do ano escolhido ----
    _dialogYear = year;
    _dialogMonth = (year == _visibleMonth.year) ? _visibleMonth.month : 1;
    final monthNames = DateFormat('MMMM', 'pt_BR');
    final month = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Selecionar mês de $year'),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.6,
              ),
              itemCount: 12,
              itemBuilder: (context, i) {
                final m = i + 1;
                final isFuture =
                    year == now.year && m > now.month;
                final selected = m == _dialogMonth;
                final raw = monthNames.format(DateTime(year, m));
                final label =
                    '${raw[0].toUpperCase()}${raw.substring(1, 3)}';
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: isFuture
                      ? null
                      : (_) => setDialogState(() => _dialogMonth = m),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(_dialogMonth),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (month == null || !mounted) return;
    setState(() {
      _visibleMonth = DateTime(year, month);
      _filtro = null;
    });
  }

  /// Alterna o filtro rápido: tocar num card ativo o desmarca e volta a
  /// mostrar todos os gastos do mês; tocar em outro troca o filtro.
  void _toggleFiltro(_FiltroRapido filtro) {
    setState(() {
      _filtro = (_filtro == filtro) ? null : filtro;
    });
  }

  Future<void> _confirmDelete(BuildContext context, Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir gasto?'),
        content: Text(
          'Deseja excluir este gasto de ${formatBRL(expense.valorCentavos)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Não'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final id = expense.id;
    if (id == null) return;
    await ref.read(expensesProvider.notifier).delete(id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gasto excluído')),
      );
    }
  }

  void _showDeleteOption(BuildContext context, Expense expense) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Excluir',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete(context, expense);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meus gastos')),
      floatingActionButton: NewExpenseMenu(
        heroTag: 'fab',
        onAdded: () => ref.invalidate(expensesProvider),
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro ao carregar: $e')),
        data: (expenses) {
          final now = DateTime.now();
          final summary = summarize(expenses, now);
          final monthExpenses = expenses.where((e) {
            return !e.dataHora.isBefore(_monthStart) &&
                e.dataHora.isBefore(_monthEnd);
          }).toList();

          // Lista exibida: mês visível, refinada pelo filtro rápido.
          // O filtro Dia/Semana é relativo a "hoje" no mês atual; ao navegar
          // para meses passados ele ancora no último dia daquele mês, para
          // que Semana/Mês continuem mostrando algo útil.
          final DateTime refNow = _isCurrentMonth
              ? now
              : DateTime(_monthEnd.year, _monthEnd.month, _monthEnd.day)
                  .subtract(const Duration(days: 1));
          final d0 = Periods.startOfDay(refNow);
          final w0 = Periods.startOfWeek(refNow);
          final List<Expense> visibleExpenses;
          switch (_filtro) {
            case _FiltroRapido.dia:
              visibleExpenses =
                  monthExpenses.where((e) => !e.dataHora.isBefore(d0)).toList();
              break;
            case _FiltroRapido.semana:
              visibleExpenses =
                  monthExpenses.where((e) => !e.dataHora.isBefore(w0)).toList();
              break;
            case _FiltroRapido.mes:
            case null:
              visibleExpenses = monthExpenses;
              break;
          }
          final String? filtroLabel = switch (_filtro) {
            _FiltroRapido.dia =>
              'Gastos do dia ${DateFormat('dd/MM', 'pt_BR').format(d0)}',
            _FiltroRapido.semana =>
              'Gastos de ${DateFormat('dd/MM', 'pt_BR').format(w0)} a ${DateFormat('dd/MM', 'pt_BR').format(refNow)}',
            _FiltroRapido.mes =>
              'Gastos de ${DateFormat('MMMM yyyy', 'pt_BR').format(_monthStart)}',
            null => null,
          };
          final monthLabel =
              DateFormat('MMMM yyyy', 'pt_BR').format(_monthStart);
          final monthTitle =
              '${monthLabel[0].toUpperCase()}${monthLabel.substring(1)}';

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(expensesProvider),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        _SummaryCard(
                          label: 'Dia',
                          value: summary.dia,
                          flex: 1,
                          selected: _filtro == _FiltroRapido.dia,
                          onTap: () => _toggleFiltro(_FiltroRapido.dia),
                        ),
                        const SizedBox(width: 8),
                        _SummaryCard(
                          label: 'Semana',
                          value: summary.semana,
                          flex: 1,
                          selected: _filtro == _FiltroRapido.semana,
                          onTap: () => _toggleFiltro(_FiltroRapido.semana),
                        ),
                        const SizedBox(width: 8),
                        _SummaryCard(
                          label: 'Mês',
                          value: summary.mes,
                          flex: 1,
                          selected: _filtro == _FiltroRapido.mes,
                          onTap: () => _toggleFiltro(_FiltroRapido.mes),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          tooltip: 'Mês anterior',
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _previousMonth,
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: _pickMonth,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 4),
                              child: Column(
                                children: [
                                  Text(
                                    monthTitle,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    formatBRL(totalOf(monthExpenses)),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Próximo mês',
                          icon: const Icon(Icons.chevron_right),
                          onPressed: _isCurrentMonth ? null : _nextMonth,
                        ),
                      ],
                    ),
                  ),
                ),
                if (visibleExpenses.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        _filtro == null
                            ? 'Nenhum gasto neste mês.\nUse o botão + para começar.'
                            : 'Nenhum gasto neste período.\nToque no filtro para ver o mês.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else ...[
                  if (filtroLabel != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$filtroLabel (${visibleExpenses.length})',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _filtro = null),
                              child: const Text('Limpar'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final e = visibleExpenses[i];
                        return ExpenseTile(
                          expense: e,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ExpenseFormScreen(expense: e),
                            ),
                          ),
                          onLongPress: () => _showDeleteOption(context, e),
                        );
                      },
                      childCount: visibleExpenses.length,
                    ),
                  ),
                  // Espaço para o FAB grande não esconder o último gasto.
                  SliverToBoxAdapter(
                    child: SizedBox(height: newExpenseFabClearance(context)),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final int value;
  final int flex;
  final bool selected;
  final VoidCallback onTap;

  const _SummaryCard(
      {required this.label,
      required this.value,
      required this.flex,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      flex: flex,
      child: Card(
        color: selected ? scheme.primaryContainer : null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                    if (selected) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.check_circle,
                          size: 14, color: scheme.primary),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                FittedBox(
                  child: Text(
                    formatBRL(value),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
