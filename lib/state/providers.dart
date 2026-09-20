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
    // Aprende: estabelecimento → categoria usada.
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
