import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../db/db.dart';
import '../l10n/app_locale.dart';
import '../l10n/l10n_format.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Relatorio por periodo, categoria e forma de pagamento.
class ReportsScreen extends ConsumerStatefulWidget {
  /// Troca para a aba de Gastos (vindo da navegação raiz). `null` quando a
  /// tela é usada fora dela: o item do menu apenas fecha.
  final VoidCallback? onVerGastos;

  const ReportsScreen({super.key, this.onVerGastos});

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
    final destaque = corDestaqueDoPerfil(ref.watch(profileProvider).value);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.strings.relatorios),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: context.strings.menu,
            onPressed: () => showMenuApp(
              context,
              ref,
              abaAtual: AbaPrincipal.relatorios,
              onIrParaGastos: widget.onVerGastos,
            ),
          ),
        ],
      ),
      floatingActionButton: NewExpenseMenu(
        heroTag: 'fab_reports',
        onAdded: () => ref.invalidate(expensesProvider),
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(context.strings.erroCarregar('$e'))),
        data: (expenses) {
          final pr = periodRange;
          final inPeriodAll =
              expenses.where((e) => pr.contains(e.dataHora)).toList();
          // Os relatórios resumem apenas despesas: receitas ficam de fora
          // dos totais (categoria/pagamento/dia) e das listas expansíveis,
          // senão os cartões de detalhe não fecham com o total do período.
          final inPeriod = inPeriodAll.where((e) => !e.isReceita).toList();
          final byCategory = sumByCategory(inPeriod);
          final byPayment = sumByPayment(inPeriod);
          final total = totalOf(inPeriodAll);
          final totalReceitasPeriodo = totalReceitas(inPeriodAll);
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
                      borderRadius: const BorderRadius.all(Radius.circular(14)),
                      selectedColor: destaque == null
                          ? Colors.white
                          : onBackgroundColor(destaque),
                      fillColor: destaque ??
                          Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.2),
                      splashColor: (destaque ??
                              Theme.of(context).colorScheme.primary)
                          .withValues(alpha: 0.4),
                      hoverColor: (destaque ??
                              Theme.of(context).colorScheme.primary)
                          .withValues(alpha: 0.15),
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(context.strings.periodoMes),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(context.strings.periodo30),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(context.strings.periodoAno),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(context.strings.periodoCustom),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '${formatDate(pr.start, (p) => p.dayMonthYear)} — '
                    '${formatDate(pr.end, (p) => p.dayMonthYear)}',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 8),
                _BalanceBarCard(
                  totalDespesas: total,
                  totalReceitas: totalReceitasPeriodo,
                  corDestaque: destaque,
                ),
                const SizedBox(height: 16),
                if (byDay.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text(context.strings.semGastosPeriodo)),
                  )
                else
                  _DaySummaryCard(
                    dayMap: byDay,
                    expenses: inPeriod,
                    corDestaque: destaque,
                  ),
                const SizedBox(height: 16),
                if (byCategory.isEmpty && byPayment.isEmpty)
                  Center(child: Text(context.strings.semDados))
                else ...[
                  if (byCategory.isNotEmpty)
                    _CategoryCard(
                      data: byCategory,
                      corDestaque: destaque,
                    ),
                  const SizedBox(height: 16),
                  if (byPayment.isNotEmpty)
                    _PaymentCard(
                      data: byPayment,
                      expenses: inPeriod,
                      corDestaque: destaque,
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

/// Compara o total de despesas com o total de receitas do período em um
/// gráfico de barras (uma barra para cada total), com o saldo
/// (receitas − despesas) em destaque no topo do cartão.
class _BalanceBarCard extends StatelessWidget {
  final int totalDespesas;
  final int totalReceitas;
  final Color? corDestaque;

  const _BalanceBarCard({
    required this.totalDespesas,
    required this.totalReceitas,
    this.corDestaque,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onCard = corDestaque == null ? null : onBackgroundColor(corDestaque!);
    final despesaColor = Colors.red.shade400;
    final receitaColor = Colors.green.shade500;
    // Saldo do período: receitas − despesas. Negativo usa "-" em vermelho,
    // zero/positivo usa "+" em verde.
    final saldo = totalReceitas - totalDespesas;
    final saldoNegativo = saldo < 0;
    final saldoColor = saldoNegativo ? despesaColor : receitaColor;
    final s = context.strings;
    final loc = Localizations.localeOf(context);
    String moeda(int centavos) => formatMoney(centavos, loc);
    final saldoTexto = '${saldoNegativo ? '-' : '+'} ${moeda(saldo.abs())}';
    final maxValor =
        totalDespesas > totalReceitas ? totalDespesas : totalReceitas;
    // O fl_chart não renderiza barras com toY == maxY == 0: garante uma
    // escala mínima para o gráfico vazio continuar visível/legível.
    final maxY = maxValor <= 0 ? 100.0 : maxValor.toDouble() * 1.2;

    double barValue(int centavos) {
      if (maxValor <= 0) return 0;
      // Barra zerada fica invisível: usa uma altura mínima só visual. O
      // valor exibido no rótulo continua sendo o real (R$ 0,00).
      if (centavos <= 0) return maxY * 0.02;
      return centavos.toDouble();
    }

    Widget bottomTitle(double value, TitleMeta meta) {
      final label = value.toInt() == 0 ? s.despesas : s.receitas;
      return SideTitleWidget(
        meta: meta,
        child: Text(label, style: const TextStyle(fontSize: 13)),
      );
    }

    return Card(
      color: corDestaque,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.despesasXReceitas,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16, color: onCard)),
            const SizedBox(height: 4),
            Text(s.totalPeriodo,
                style: TextStyle(
                    fontSize: 13,
                    color: onCard?.withValues(alpha: 0.7) ?? Colors.grey)),
            const SizedBox(height: 8),
            Center(
              child: Column(
                children: [
                  Text(s.saldo,
                      style: TextStyle(
                          fontSize: 13,
                          color:
                              onCard?.withValues(alpha: 0.7) ?? Colors.grey)),
                  const SizedBox(height: 2),
                  Text(saldoTexto,
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: saldoColor)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: s.graficoAcessivel(
                  moeda(totalDespesas), moeda(totalReceitas), saldoTexto),
              child: SizedBox(
                height: 220,
                child: BarChart(
                  BarChartData(
                    maxY: maxY,
                    minY: 0,
                    alignment: BarChartAlignment.spaceEvenly,
                    groupsSpace: 24,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, _, rod, __) {
                          final centavos = group.x.toInt() == 0
                              ? totalDespesas
                              : totalReceitas;
                          final label =
                              group.x.toInt() == 0 ? 'Despesas' : 'Receitas';
                          return BarTooltipItem(
                            '$label\n${formatBRL(centavos)}',
                            TextStyle(
                              color: rod.color,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: bottomTitle,
                          reservedSize: 28,
                        ),
                      ),
                    ),
                    barGroups: [
                      BarChartGroupData(
                        x: 0,
                        barRods: [
                          BarChartRodData(
                            toY: barValue(totalDespesas),
                            color: despesaColor,
                            width: 56,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6)),
                          ),
                        ],
                      ),
                      BarChartGroupData(
                        x: 1,
                        barRods: [
                          BarChartRodData(
                            toY: barValue(totalReceitas),
                            color: receitaColor,
                            width: 56,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BalanceLegend(
                  color: despesaColor,
                  label: 'Despesas',
                  value: formatBRL(totalDespesas),
                  textColor:
                      (onCard ?? theme.textTheme.bodyMedium?.color)?.withValues(
                          alpha: 0.8),
                  valueSize: 13,
                ),
                _BalanceLegend(
                  color: receitaColor,
                  label: 'Receitas',
                  value: formatBRL(totalReceitas),
                  textColor:
                      (onCard ?? theme.textTheme.bodyMedium?.color)?.withValues(
                          alpha: 0.8),
                  valueSize: 13,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceLegend extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final Color? textColor;

  /// Tamanho do valor (padrão 15). No cartão despesas x receitas usa-se 13
  /// para dar mais destaque ao saldo, que é o número principal do cartão.
  final double valueSize;

  const _BalanceLegend({
    required this.color,
    required this.label,
    required this.value,
    this.textColor,
    this.valueSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: textColor)),
            Text(value,
                style: TextStyle(
                    fontSize: valueSize,
                    fontWeight: FontWeight.w600,
                    color: textColor)),
          ],
        ),
      ],
    );
  }
}

class _DaySummaryCard extends StatelessWidget {
  final Map<DateTime, int> dayMap;
  final List<Expense> expenses;
  final Color? corDestaque;

  const _DaySummaryCard({
    required this.dayMap,
    required this.expenses,
    this.corDestaque,
  });

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
    final s = context.strings;
    String dataCurta(DateTime d) =>
        formatDate(d, (p) => p.weekdayDayMonth);

    return Card(
      color: corDestaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(s.gastosPorDia,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: corDestaque == null
                        ? null
                        : onBackgroundColor(corDestaque!))),
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
                dataCurta(day),
                style: const TextStyle(fontSize: 13),
              ),
              trailing: Text(
                  formatMoney(dayMap[day]!,
                      Localizations.localeOf(context)),
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
  final Color? corDestaque;

  const _CategoryCard({required this.data, this.corDestaque});

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold<int>(0, (a, b) => a + b);
    return Card(
      color: corDestaque,
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
                            child: Text(categoryLabelOf(context, entry.key),
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Text(
                              formatMoney(entry.value,
                                  Localizations.localeOf(context)),
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
  final Color? corDestaque;

  const _PaymentCard({
    required this.data,
    required this.expenses,
    this.corDestaque,
  });

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
      color: corDestaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(context.strings.porPagamento,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: corDestaque == null
                        ? null
                        : onBackgroundColor(corDestaque!))),
          ),
          for (final entry in data.entries)
            ExpansionTile(
              leading: Icon(icons[entry.key]),
              title: Text(paymentLabelOf(context, entry.key)),
              trailing: Text(formatMoney(entry.value,
                  Localizations.localeOf(context))),
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
