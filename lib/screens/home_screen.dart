import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../screens/expense_form_screen.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Expense expense) async {
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

  void _showDeleteOption(
      BuildContext context, WidgetRef ref, Expense expense) {
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
                _confirmDelete(context, ref, expense);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            final m0 = DateTime(DateTime.now().year, DateTime.now().month);
            return !e.dataHora.isBefore(m0);
          }).toList();

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
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('Gastos do mês',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                if (monthExpenses.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'Nenhum gasto registrado.\nUse o botão + para começar.',
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
                          onLongPress: () =>
                              _showDeleteOption(context, ref, e),
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
