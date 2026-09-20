import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Relatório por período, categoria e forma de pagamento.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

enum _Period { mes, ultimos30, ano, custom }

class _ReportsScreenState extends State<ReportsScreen> {
  _Period _period = _Period.mes;
  DateTimeRange? _custom;

  DateTimeRange get range {
    final now = DateTime.now();
    switch (_period) {
      case _Period.mes:
        final m0 = DateTime(now.year, now.month);
        return DateTimeRange(start: m0, end: now);
      case _Period.ultimos30:
        final start =
            Periods.startOfDay(now).subtract(const Duration(days: 29));
        return DateTimeRange(start: start, end: now);
      case _Period.ano:
        final y0 = DateTime(now.year);
        return DateTimeRange(start: y0, end: now);
      case _Period.custom:
        return _custom ??
            DateTimeRange(start: Periods.startOfMonth(now), end: now);
    }
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: range,
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null) return;
    setState(() {
      _period = _Period.custom;
      _custom = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = range;
    // end exclusivo: cobre o dia inteiro da data final
    final endEx = r.end.add(const Duration(days: 1));
    final categoriesFuture = DBHelper.instance.sumByCategory(r.start, endEx);
    final paymentsFuture = DBHelper.instance.sumByPayment(r.start, endEx);
    final totalFuture = DBHelper.instance.totalBetween(r.start, endEx);

    final label = DateFormat('dd/MM/yyyy', 'pt_BR');
    return Scaffold(
      appBar: AppBar(title: const Text('Relatórios')),
      body: ListView(
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
              '${label.format(r.start)} – ${label.format(r.end)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
          const Text('Total do período',
              style: TextStyle(fontWeight: FontWeight.bold)),
          FutureBuilder<int>(
            future: totalFuture,
            builder: (context, snap) => Text(
              formatBRL(snap.data ?? 0),
              style:
                  const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Por categoria',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FutureBuilder<Map<Category, int>>(
            future: categoriesFuture,
            builder: (context, snap) {
              final data = snap.data ?? const {};
              if (data.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('Sem gastos no período.')),
                );
              }
              return _CategoryCard(data: data);
            },
          ),
          const SizedBox(height: 8),
          const Text('Por forma de pagamento',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FutureBuilder<Map<PaymentMethod, int>>(
            future: paymentsFuture,
            builder: (context, snap) {
              final data = snap.data ?? const {};
              if (data.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('Sem gastos no período.')),
                );
              }
              return _PaymentList(data: data);
            },
          ),
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

class _PaymentList extends StatelessWidget {
  final Map<PaymentMethod, int> data;

  const _PaymentList({required this.data});

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
