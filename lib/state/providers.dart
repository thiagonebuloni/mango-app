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

  /// Agrega um backup CSV importado aos lançamentos já existentes.
  ///
  /// Por segurança **não apaga nada**: só insere o que ainda não está no
  /// app — duplicatas vindas do arquivo ou já cadastradas (mesma
  /// [Expense.chaveUnica]) são ignoradas, e registros únicos do aparelho
  /// são preservados. Retorna quantos lançamentos novos foram inseridos.
  Future<int> mergeAll(List<Expense> imported) async {
    final existentes = await DBHelper.instance.allExpenses();
    final chaves = existentes.map((e) => e.chaveUnica).toSet();
    final novos = <Expense>[];
    for (final e in imported) {
      if (chaves.add(e.chaveUnica)) novos.add(e);
    }
    if (novos.isNotEmpty) {
      await DBHelper.instance.insertExpensesBatch(novos);
    }
    await _reload();
    return novos.length;
  }
}

final expensesProvider =
    AsyncNotifierProvider<ExpensesNotifier, List<Expense>>(
        ExpensesNotifier.new);

/// Perfil já lido do banco em `main()`, antes do primeiro frame.
///
/// Serve de valor inicial enquanto o [profileProvider] carrega: sem ele o app
/// abriria com a cor de fundo padrão e só depois mudaria para a do usuário.
final perfilInicialProvider = Provider<UserProfile?>((ref) => null);

/// Perfil do usuário (nome, avatar e cor de fundo do app).
///
/// `null` = primeiro acesso: o app abre a tela de cadastro do perfil.
class ProfileNotifier extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() async {
    final inicial = ref.read(perfilInicialProvider);
    if (inicial != null) return inicial;
    return DBHelper.instance.loadProfile();
  }

  Future<void> save(UserProfile profile) async {
    await DBHelper.instance.saveProfile(profile);
    state = AsyncData(profile);
  }
}

final profileProvider =
    AsyncNotifierProvider<ProfileNotifier, UserProfile?>(ProfileNotifier.new);

/// Sumários diário/semanal/mensal derivados da lista carregada.
///
/// [dia]/[semana]/[mes] somam só despesas; [receitasDia]/[receitasSemana]/
/// [receitasMes] somam só receitas e [saldo*] = receitas − despesas.
class PeriodSummary {
  final int dia;
  final int semana;
  final int mes;
  final int receitasDia;
  final int receitasSemana;
  final int receitasMes;

  const PeriodSummary({
    required this.dia,
    required this.semana,
    required this.mes,
    this.receitasDia = 0,
    this.receitasSemana = 0,
    this.receitasMes = 0,
  });

  int get saldoDia => receitasDia - dia;
  int get saldoSemana => receitasSemana - semana;
  int get saldoMes => receitasMes - mes;
}

PeriodSummary summarize(List<Expense> expenses, DateTime now) {
  final d0 = Periods.startOfDay(now);
  final w0 = Periods.startOfWeek(now);
  final m0 = Periods.startOfMonth(now);
  int dia = 0, semana = 0, mes = 0;
  int rDia = 0, rSemana = 0, rMes = 0;
  for (final e in expenses) {
    if (!e.dataHora.isBefore(d0)) {
      if (e.isReceita) {
        rDia += e.valorCentavos;
      } else {
        dia += e.valorCentavos;
      }
    }
    if (!e.dataHora.isBefore(w0)) {
      if (e.isReceita) {
        rSemana += e.valorCentavos;
      } else {
        semana += e.valorCentavos;
      }
    }
    if (!e.dataHora.isBefore(m0)) {
      if (e.isReceita) {
        rMes += e.valorCentavos;
      } else {
        mes += e.valorCentavos;
      }
    }
  }
  return PeriodSummary(
    dia: dia,
    semana: semana,
    mes: mes,
    receitasDia: rDia,
    receitasSemana: rSemana,
    receitasMes: rMes,
  );
}

/// Relatórios: gastos do período em aberto, reativos ao expensesProvider.
class ExpensesForReports extends AsyncNotifier<List<Expense>> {
  @override
  Future<List<Expense>> build() {
    // Observa os lançamentos: despesa/receita inserida, editada, excluída ou
    // importada recarrega os relatórios na hora, sem depender de FAB ou
    // pull-to-refresh (os lançamentos sempre passam pelo expensesProvider).
    ref.watch(expensesProvider);
    return DBHelper.instance.allExpenses();
  }
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

Map<Category, int> sumByCategory(Iterable<Expense> expenses,
    {bool receitas = false}) {
  final map = <Category, int>{};
  for (final e in expenses) {
    if (e.isReceita != receitas) continue;
    map[e.categoria] = (map[e.categoria] ?? 0) + e.valorCentavos;
  }
  return map;
}

Map<PaymentMethod, int> sumByPayment(Iterable<Expense> expenses,
    {bool receitas = false}) {
  final map = <PaymentMethod, int>{};
  for (final e in expenses) {
    if (e.isReceita != receitas) continue;
    map[e.forma] = (map[e.forma] ?? 0) + e.valorCentavos;
  }
  return map;
}

/// Soma só despesas (receitas entram separadas via [totalReceitas]).
int totalOf(Iterable<Expense> expenses) {
  int t = 0;
  for (final e in expenses) {
    if (!e.isReceita) t += e.valorCentavos;
  }
  return t;
}

/// Soma só receitas no iterável.
int totalReceitas(Iterable<Expense> expenses) {
  int t = 0;
  for (final e in expenses) {
    if (e.isReceita) t += e.valorCentavos;
  }
  return t;
}

/// Saldo = receitas − despesas.
int saldoOf(Iterable<Expense> expenses) =>
    totalReceitas(expenses) - totalOf(expenses);

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
