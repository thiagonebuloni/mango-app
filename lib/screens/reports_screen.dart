import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../db/db.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Relatório por período, categoria e forma de pagamento.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

enum _Period { mes, ultimos30, ano, custom }

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _Period _period = _Period.mes;
  DateTimeRange? _custom;

  DateTimeRange get range {
    final now = DateTime.now();
    switch (_period) {
      case _Period.mes:
        final m0 = DateTime(now.year, now.month);
        return DateTimeRange(start: m0, end: now);
      case _Period.ultimos30:
        final start = Periods.startOfDay(now).subtract(const Duration(days: 29));
        return DateTimeRange(start: start, end: now);
      case _Period.ano:
        final y0 = DateTime(now.year);
        return DateTimeRange(start: y0, end: now);
      case _Period.custom:
        return _custom ?? DateTimeRange(start: Periods.startOfMonth(now), end: now);
    }
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: range,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _period = _Period.custom;
      _custom = picked;
    });
  }

  void _invalidate() => ref.invalidate(expensesForReportsProvider);

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesForReportsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Relatórios')),
      floatingActionButton: NewExpenseMenu(heroTag: 'fab_reports', onAdded: _invalidate),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro ao carregar dados: $e')),
        data: (expenses) {
          final pr = periodRange(DateTime.now(), _period.index, _custom);
          final inPeriod = expenses.where((e) => pr.contains(e.dataHora)).toList();
          final byCategory = sumByCategory(inPeriod);
          final byPayment = sumByPayment(inPeriod);
          final total = totalOf(inPeriod);
          final byDay = sumByDay(inPeriod);

          return RefreshIndicator(
            onRefresh: () async => _invalidate(),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                SegmentedButton<_Period>(
                  segments: const [
                    ButtonSegment(value: _Period.mes, label: Text('Mês')),
                    ButtonSegment(value: _Period.ultimos30, label: Text('30 dias')),
                    ButtonSegment(value: _Period.ano, label: Text('Ano')),
                    ButtonSegment(value: _Period.custom, label: Text('Custom')),
                  ],
                  selected: {_period},
                  onSelectionChanged: (s) {
                    if (s.first == _Period.custom) {
                      _pickCustom();
                    } else {
                      setState(() => _period = s.first);
                    }
                  },
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
                    child: Center(child: Text('Sem gastos no período.')),
                  )
                else
                  _DaySummaryCard(dayMap: byDay),
                const SizedBox(height: 16),
                if (byCategory.isEmpty && byPayment.isEmpty)
                  const Center(child: Text('Sem dados para visualização.'))
                else ...[
                  if (byCategory.isNotEmpty) _CategoryCard(data: byCategory),
                  const SizedBox(height: 16),
                  if (byPayment.isNotEmpty) _PaymentCard(data: byPayment),
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

  const _DaySummaryCard({required this.dayMap});

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
          ...days.map((day) => ListTile(
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
              )),
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

  const _PaymentCard({required this.data});

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
        children: [
          for (final entry in data.entries)
            ListTile(
              leading: Icon(icons[entry.key]),
              title: Text(entry.key.label),
              trailing: Text(formatBRL(entry.value)),
            ),
        ],
      ),
    );
  }
}
