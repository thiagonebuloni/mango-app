import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../screens/expense_form_screen.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Mês em exibição (dia 1). Começa no mês atual; o usuário pode voltar
  /// para meses anteriores e avançar até o mês atual.
  late DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);

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
    });
  }

  void _nextMonth() {
    if (_isCurrentMonth) return;
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    });
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _isCurrentMonth
          ? now
          : DateTime(_visibleMonth.year, _visibleMonth.month, 1),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month + 1, 0),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Selecionar mês',
      cancelText: 'Cancelar',
      confirmText: 'OK',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _visibleMonth = DateTime(picked.year, picked.month);
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
          final summary = summarize(expenses, DateTime.now());
          final monthExpenses = expenses.where((e) {
            return !e.dataHora.isBefore(_monthStart) &&
                e.dataHora.isBefore(_monthEnd);
          }).toList();
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
                        _SummaryCard(label: 'Dia', value: summary.dia, flex: 1),
                        const SizedBox(width: 8),
                        _SummaryCard(label: 'Semana', value: summary.semana, flex: 1),
                        const SizedBox(width: 8),
                        _SummaryCard(label: 'Mês', value: summary.mes, flex: 1),
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
                if (monthExpenses.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'Nenhum gasto neste mês.\nUse o botão + para começar.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else ...[
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final e = monthExpenses[i];
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
                      childCount: monthExpenses.length,
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

  const _SummaryCard({required this.label, required this.value, required this.flex});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      flex: flex,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
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
    );
  }
}
