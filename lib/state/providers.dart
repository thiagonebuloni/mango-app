import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db.dart';
import '../models/models.dart';
import '../services/receipt_parser.dart';

/// Estado reativo dos gastos: carrega do SQLite e re-carrega após mutações.
class ExpensesNotifier extends AsyncNotifier<List<Expense>> {
  @override
  Future<List<Expense>> build() => DBHelper.instance.allExpenses();

  Future<void> _reload() async {
    state = AsyncData(await DBHelper.instance.allExpenses());
  }

  Future<void> add(Expense expense) async {
    await DBHelper.instance.insertExpense(expense);
    if (expense.estabelecimento.trim().isNotEmpty) {
      await DBHelper.instance.memorizeMerchant(
              ReceiptParser.normalizeMerchant(expense.estabelecimento),
              expense.categoria);
    }
    await _reload();
  }

  /// Edita um gasto existente ("update" colide com a API do AsyncNotifier).
  Future<void> edit(Expense expense) async {
    await DBHelper.instance.updateExpense(expense);
    if (expense.estabelecimento.trim().isNotEmpty) {
      await DBHelper.instance.memorizeMerchant(
              ReceiptParser.normalizeMerchant(expense.estabelecimento),
              expense.categoria);
    }
    await _reload();
  }

  Future<void> delete(int id) async {
    await DBHelper.instance.deleteExpense(id);
    await _reload();
  }
}

final expensesProvider =
    AsyncNotifierProvider<ExpensesNotifier, List<Expense>>(
        ExpensesNotifier.new);

/// Sumários diário/semanal/mensal derivados da lista carregada.
class PeriodSummary {
  final int dia;
  final int semana;
  final int mes;

  const PeriodSummary({required this.dia, required this.semana, required this.mes});
}

PeriodSummary summarize(List<Expense> expenses, DateTime now) {
  final d0 = Periods.startOfDay(now);
  final w0 = Periods.startOfWeek(now);
  final m0 = Periods.startOfMonth(now);
  int dia = 0, semana = 0, mes = 0;
  for (final e in expenses) {
    if (!e.dataHora.isBefore(d0)) dia += e.valorCentavos;
    if (!e.dataHora.isBefore(w0)) semana += e.valorCentavos;
    if (!e.dataHora.isBefore(m0)) mes += e.valorCentavos;
  }
  return PeriodSummary(dia: dia, semana: semana, mes: mes);
}

/// Relatórios: gastos do período em aberto, reativos ao expensesProvider.
class ExpensesForReports extends AsyncNotifier<List<Expense>> {
  @override
  Future<List<Expense>> build() => DBHelper.instance.allExpenses();
}

final expensesForReportsProvider =
    AsyncNotifierProvider<ExpensesForReports, List<Expense>>(
        ExpensesForReports.new);

PeriodRange periodRange(DateTime now, dynamic period, DateTimeRange? custom) {
  final m0 = DateTime(now.year, now.month);
  final w0 = Periods.startOfDay(now).subtract(const Duration(days: 29));
  final y0 = DateTime(now.year);
  switch (period) {
    case 0:
      return PeriodRange(start: m0, end: now);
    case 1:
      return PeriodRange(start: w0, end: now);
    case 2:
      return PeriodRange(start: y0, end: now);
    case 3:
      final c = custom ?? DateTimeRange(start: m0, end: now);
      return PeriodRange(start: c.start, end: c.end);
  }
  return PeriodRange(start: m0, end: now);
}

Map<Category, int> sumByCategory(Iterable<Expense> expenses) {
  final map = <Category, int>{};
  for (final e in expenses) {
    map[e.categoria] = (map[e.categoria] ?? 0) + e.valorCentavos;
  }
  return map;
}

Map<PaymentMethod, int> sumByPayment(Iterable<Expense> expenses) {
  final map = <PaymentMethod, int>{};
  for (final e in expenses) {
    map[e.forma] = (map[e.forma] ?? 0) + e.valorCentavos;
  }
  return map;
}

int totalOf(Iterable<Expense> expenses) {
  int t = 0;
  for (final e in expenses) {
    t += e.valorCentavos;
  }
  return t;
}

/// Agrupa gastos por dia, retornando um mapa onde a chave é a data (sem hora)
/// e o valor é o total em centavos daquele dia.
Map<DateTime, int> sumByDay(Iterable<Expense> expenses) {
  final map = <DateTime, int>{};
  for (final e in expenses) {
    final day = DateTime(e.dataHora.year, e.dataHora.month, e.dataHora.day);
    map[day] = (map[day] ?? 0) + e.valorCentavos;
  }
  return map;
}

/// Retorna uma lista de [DateTime] chaveados por dia, ordenados do mais
/// recente para o mais antigo.
List<DateTime> sortedDays(Map<DateTime, int> dayMap) {
  return dayMap.keys.toList()
    ..sort((a, b) => b.compareTo(a));
}

class PeriodRange {
  final DateTime start;
  final DateTime end;
  const PeriodRange({required this.start, required this.end});

  DateTime get endExclusive => end.add(const Duration(days: 1));

  bool contains(DateTime dt) => !dt.isBefore(start) && dt.isBefore(endExclusive);
}
