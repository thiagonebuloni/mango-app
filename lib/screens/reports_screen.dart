import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../db/db.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Relatorio por periodo, categoria e forma de pagamento.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

enum _Period { mes, ultimos30, ano, custom }

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _Period _period = _Period.mes;
  // Armazena o dia inicial e final do periodo custom (sem hora)
  DateTime? _customStart;
  DateTime? _customEnd;

  PeriodRange get periodRange {
    final now = DateTime.now();
    switch (_period) {
      case _Period.mes:
        final m0 = DateTime(now.year, now.month);
        return PeriodRange(start: m0, end: now);
      case _Period.ultimos30:
        final start = Periods.startOfDay(now).subtract(const Duration(days: 29));
        return PeriodRange(start: start, end: now);
      case _Period.ano:
        final y0 = DateTime(now.year);
        return PeriodRange(start: y0, end: now);
      case _Period.custom:
        return PeriodRange(
          start: _customStart ?? DateTime(now.year, now.month),
          end: _customEnd ?? now,
        );
    }
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final pr = periodRange;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: pr.start,
        end: pr.end,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _period = _Period.custom;
      _customStart = picked.start;
      _customEnd = picked.end;
    });
  }

  void _invalidate() => ref.invalidate(expensesForReportsProvider);

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesForReportsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: () => showMenuApp(context, ref),
          ),
        ],
      ),
      floatingActionButton: NewExpenseMenu(
        heroTag: 'fab_reports',
        onAdded: () => ref.invalidate(expensesProvider),
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro ao carregar dados: $e')),
        data: (expenses) {
          final pr = periodRange;
          // Os relatórios resumem apenas despesas: receitas ficam de fora
          // dos totais (categoria/pagamento/dia) e das listas expansíveis,
          // senão os cartões de detalhe não fecham com o total do período.
          final inPeriod = expenses
              .where((e) => pr.contains(e.dataHora) && !e.isReceita)
              .toList();
          final byCategory = sumByCategory(inPeriod);
          final byPayment = sumByPayment(inPeriod);
          final total = totalOf(inPeriod);
          final byDay = sumByDay(inPeriod);

          return RefreshIndicator(
            onRefresh: () async => _invalidate(),
            child: ListView(
              // Reserva o espaço do FAB grande no fim da página: sem isso o
              // botão cobre os últimos gráficos/cartões e a lista não rola o
              // bastante para deixá-los acima dele.
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                12 + newExpenseFabClearance(context),
              ),
              children: [
                // Barra de períodos centralizada. O ToggleButtons monta um
                // Row com mainAxisSize.min, mas dentro de um ListView a
                // largura chega "tight" (min == max) e a linha ocuparia a tela
                // toda, alinhando os botões à esquerda. O Center devolve
                // restrição "loose" (shrink-wrap) e a rolagem horizontal evita
                // overflow quando a fonte do sistema é grande.
                Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ToggleButtons(
                      isSelected: [
                        _period == _Period.mes,
                        _period == _Period.ultimos30,
                        _period == _Period.ano,
                        _period == _Period.custom,
                      ],
                      onPressed: (i) {
                        if (i == _Period.custom.index) {
                          // Custom: sempre abre o date picker, mesmo se já
                          // estiver selecionado.
                          _pickCustom();
                        } else {
                          setState(() => _period = _Period.values[i]);
                        }
                      },
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      selectedColor: Colors.white,
                      fillColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.2),
                      splashColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.4),
                      hoverColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.15),
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('Mês'),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('30 dias'),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('Ano'),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('Custom'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '${DateFormat('dd/MM/yyyy', 'pt_BR').format(pr.start)} — '
                    '${DateFormat('dd/MM/yyyy', 'pt_BR').format(pr.end)}',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(formatBRL(total),
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 16),
                if (byDay.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Sem gastos no periodo.')),
                  )
                else
                  _DaySummaryCard(dayMap: byDay, expenses: inPeriod),
                const SizedBox(height: 16),
                if (byCategory.isEmpty && byPayment.isEmpty)
                  const Center(child: Text('Sem dados para visualização.'))
                else ...[
                  if (byCategory.isNotEmpty)
                    _CategoryCard(data: byCategory),
                  const SizedBox(height: 16),
                  if (byPayment.isNotEmpty)
                    _PaymentCard(data: byPayment, expenses: inPeriod),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DaySummaryCard extends StatelessWidget {
  final Map<DateTime, int> dayMap;
  final List<Expense> expenses;

  const _DaySummaryCard({required this.dayMap, required this.expenses});

  List<Expense> _expensesOfDay(DateTime day) {
    final list = expenses.where((e) {
      return e.dataHora.year == day.year &&
          e.dataHora.month == day.month &&
          e.dataHora.day == day.day;
    }).toList()
      ..sort((a, b) => b.dataHora.compareTo(a.dataHora));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final days = sortedDays(dayMap);
    final df = DateFormat('EEE, dd/MM', 'pt_BR');

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Gastos por dia',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ...days.map((day) {
            final dayExpenses = _expensesOfDay(day);
            return ExpansionTile(
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                child: Text(
                  DateFormat('dd', 'pt_BR').format(day),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
              ),
              title: Text(
                df.format(day),
                style: const TextStyle(fontSize: 13),
              ),
              trailing: Text(formatBRL(dayMap[day]!),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15)),
              children: [
                for (final e in dayExpenses) ExpenseTile(expense: e),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final Map<Category, int> data;

  const _CategoryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold<int>(0, (a, b) => a + b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 150,
              height: 150,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 30,
                  sections: [
                    for (final entry in data.entries)
                      PieChartSectionData(
                        color: entry.key.color,
                        value: entry.value.toDouble(),
                        title: '${(entry.value * 100 / total).round()}%',
                        titleStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in data.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 12, color: entry.key.color),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(entry.key.label,
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Text(formatBRL(entry.value),
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final Map<PaymentMethod, int> data;
  final List<Expense> expenses;

  const _PaymentCard({required this.data, required this.expenses});

  List<Expense> _expensesOf(PaymentMethod forma) {
    final list = expenses.where((e) => e.forma == forma).toList()
      ..sort((a, b) => b.dataHora.compareTo(a.dataHora));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    const icons = {
      PaymentMethod.dinheiro: Icons.payments,
      PaymentMethod.debito: Icons.credit_score,
      PaymentMethod.credito: Icons.credit_card,
      PaymentMethod.pix: Icons.qr_code,
      PaymentMethod.outros: Icons.more_horiz,
    };
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Por forma de pagamento',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          for (final entry in data.entries)
            ExpansionTile(
              leading: Icon(icons[entry.key]),
              title: Text(entry.key.label),
              trailing: Text(formatBRL(entry.value)),
              children: [
                for (final e in _expensesOf(entry.key))
                  ExpenseTile(expense: e),
              ],
            ),
        ],
      ),
    );
  }
}
