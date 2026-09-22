import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/expense_form_screen.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

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
                else
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
                        );
                      },
                      childCount: monthExpenses.length,
                    ),
                  ),
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
