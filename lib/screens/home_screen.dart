import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../db/db.dart';
import '../l10n/app_locale.dart';
import '../l10n/l10n_format.dart';
import '../models/models.dart';
import '../screens/expense_form_screen.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Filtro rápido da lista de gastos pelos cards de resumo.
enum _FiltroRapido { dia, semana, mes }

class HomeScreen extends ConsumerStatefulWidget {
  /// Troca para a aba de Relatórios (vindo da navegação raiz). `null` quando
  /// a tela é usada fora dela: o item do menu apenas fecha.
  final VoidCallback? onVerRelatorios;

  /// Troca para a aba de Cartões; `null` fora da navegação raiz (aí o item
  /// de Cartões nem aparece no menu).
  final VoidCallback? onVerCartoes;

  const HomeScreen({super.key, this.onVerRelatorios, this.onVerCartoes});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Mês em exibição (dia 1). O valor mora em [mesGastosProvider] — fora do
  /// `State` da tela —, então sobrevive à troca de abas e a sair e voltar, e
  /// é independente do mês escolhido na tela de Cartões.
  DateTime get _visibleMonth => ref.read(mesGastosProvider);

  /// Filtro rápido ativo (Dia/Semana/Mês). `null` = mostra gastos do mês.
  _FiltroRapido? _filtro;

  /// Mês selecionado no diálogo ano→mês (passo 2 de [_pickMonth]).
  late int _dialogYear;
  late int _dialogMonth;

  bool get _isCurrentMonth {
    final mes = _visibleMonth;
    final now = DateTime.now();
    return mes.year == now.year && mes.month == now.month;
  }

  /// Mostra outro mês na tela e limpa o filtro rápido (que valia para o mês
  /// anterior).
  void _irParaMes(DateTime mes) {
    ref.read(mesGastosProvider.notifier).mostrar(mes);
    setState(() => _filtro = null);
  }

  void _previousMonth() {
    final mes = _visibleMonth;
    _irParaMes(DateTime(mes.year, mes.month - 1));
  }

  void _nextMonth() {
    if (_isCurrentMonth) return;
    final mes = _visibleMonth;
    _irParaMes(DateTime(mes.year, mes.month + 1));
  }

  /// Seletor de mês em 2 passos (só ano + mês, sem escolher dia):
  /// 1º mostra os anos, 2º mostra os 12 meses do ano escolhido.
  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final minYear = 2020;
    final maxYear = now.year;

    // ---- passo 1: ano ----
    _dialogYear = _visibleMonth.year;
    final year = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.strings.selecionarAno),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: maxYear - minYear + 1,
            itemBuilder: (context, i) {
              final y = maxYear - i;
              final selected = y == _dialogYear;
              return ListTile(
                title: Text(
                  '$y',
                  style: TextStyle(
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: selected ? const Icon(Icons.check) : null,
                selected: selected,
                onTap: () => Navigator.of(dialogContext).pop(y),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.strings.cancel),
          ),
        ],
      ),
    );
    if (year == null || !mounted) return;

    // ---- passo 2: mês do ano escolhido ----
    _dialogYear = year;
    _dialogMonth = (year == _visibleMonth.year) ? _visibleMonth.month : 1;
    final s = context.strings;
    final loc = Localizations.maybeLocaleOf(context);
    final monthNames = DateFormat('MMMM', intlLocaleName(loc!));
    final month = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(s.selecionarMesDe(year)),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.6,
              ),
              itemCount: 12,
              itemBuilder: (context, i) {
                final m = i + 1;
                final isFuture =
                    year == now.year && m > now.month;
                final selected = m == _dialogMonth;
                final raw = monthNames.format(DateTime(year, m));
                final label = raw.length <= 3
                    ? raw
                    : '${raw[0].toUpperCase()}${raw.substring(1, 3)}';
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: isFuture
                      ? null
                      : (_) => setDialogState(() => _dialogMonth = m),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(dialogContext.strings.voltar),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(_dialogMonth),
              child: Text(dialogContext.strings.ok),
            ),
          ],
        ),
      ),
    );
    if (month == null || !mounted) return;
    _irParaMes(DateTime(year, month));
  }

  /// Alterna o filtro rápido: tocar num card ativo o desmarca e volta a
  /// mostrar todos os gastos do mês; tocar em outro troca o filtro.
  void _toggleFiltro(_FiltroRapido filtro) {
    setState(() {
      _filtro = (_filtro == filtro) ? null : filtro;
    });
  }

  Future<void> _confirmDelete(BuildContext context, Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.strings.excluirGasto),
        content: Text(dialogContext.strings
            .excluirGastoMsg(formatMoney(expense.valorCentavos))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.strings.nao),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.strings.excluir),
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
        SnackBar(content: Text(context.strings.gastoExcluido)),
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
              title: Text(context.strings.excluirAcao,
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
    // Mês guardado no provedor: observá-lo faz a tela reconstruir quando o
    // período muda (setas, seletor) — inclusive ao voltar para a aba.
    final mes = ref.watch(mesGastosProvider);
    final monthStart = DateTime(mes.year, mes.month);
    final monthEnd = DateTime(mes.year, mes.month + 1);
    final expensesAsync = ref.watch(expensesProvider);
    final destaque = corDestaqueDoPerfil(ref.watch(profileProvider).value);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.strings.meusGastos),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: context.strings.menu,
            onPressed: () => showMenuApp(
              context,
              ref,
              abaAtual: AbaPrincipal.gastos,
              onIrParaRelatorios: widget.onVerRelatorios,
              onIrParaCartoes: widget.onVerCartoes,
            ),
          ),
        ],
      ),
      floatingActionButton: NewExpenseMenu(
        heroTag: 'fab',
        onAdded: () => ref.invalidate(expensesProvider),
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(context.strings.erroCarregar('$e'))),
        data: (expenses) {
          final now = DateTime.now();
          // Gastos do mês visível (contexto selecionado nas setas/seletor).
          final monthExpenses = expenses.where((e) {
            return !e.dataHora.isBefore(monthStart) &&
                e.dataHora.isBefore(monthEnd);
          }).toList();

          // Referência para Dia/Semana: "hoje" no mês atual; último dia do
          // mês visível nos meses passados. Assim os cards Dia/Semana/Mês
          // sempre representam o mês selecionado, e não o mês atual.
          final DateTime refNow = _isCurrentMonth
              ? now
              : monthEnd.subtract(const Duration(days: 1));
          final d0 = Periods.startOfDay(refNow);
          final w0 = Periods.startOfWeek(refNow);

          // Totais dos cards restritos ao mês visível (só despesas, como
          // antes): Dia = último dia (ou hoje), Semana = última semana
          // (ou semana atual), Mês = mês visível inteiro.
          final diaTotal = totalOf(
              monthExpenses.where((e) => !e.dataHora.isBefore(d0)));
          final semanaTotal = totalOf(
              monthExpenses.where((e) => !e.dataHora.isBefore(w0)));
          final mesTotal = totalOf(monthExpenses);
          final List<Expense> visibleExpenses;
          switch (_filtro) {
            case _FiltroRapido.dia:
              visibleExpenses =
                  monthExpenses.where((e) => !e.dataHora.isBefore(d0)).toList();
              break;
            case _FiltroRapido.semana:
              visibleExpenses =
                  monthExpenses.where((e) => !e.dataHora.isBefore(w0)).toList();
              break;
            case _FiltroRapido.mes:
            case null:
              visibleExpenses = monthExpenses;
              break;
          }
          final s = context.strings;
          final loc = Localizations.localeOf(context);
          String data(DateTime d) =>
              formatDate(d, (p) => p.shortDayMonth, loc);
          final String? filtroLabel = switch (_filtro) {
            _FiltroRapido.dia => s.gastosDoDia(data(d0)),
            _FiltroRapido.semana =>
              s.gastosDeSemana(data(w0), data(refNow)),
            _FiltroRapido.mes => s.gastosDeMes(
                formatDate(monthStart, (p) => p.monthName, loc)),
            null => null,
          };
          final monthLabel =
              formatDate(monthStart, (p) => p.monthYear, loc);
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
                        _SummaryCard(
                          label: s.dia,
                          value: diaTotal,
                          flex: 1,
                          selected: _filtro == _FiltroRapido.dia,
                          corDestaque: destaque,
                          onTap: () => _toggleFiltro(_FiltroRapido.dia),
                        ),
                        const SizedBox(width: 8),
                        _SummaryCard(
                          label: s.semana,
                          value: semanaTotal,
                          flex: 1,
                          selected: _filtro == _FiltroRapido.semana,
                          corDestaque: destaque,
                          onTap: () => _toggleFiltro(_FiltroRapido.semana),
                        ),
                        const SizedBox(width: 8),
                        _SummaryCard(
                          label: s.mes,
                          value: mesTotal,
                          flex: 1,
                          selected: _filtro == _FiltroRapido.mes,
                          corDestaque: destaque,
                          onTap: () => _toggleFiltro(_FiltroRapido.mes),
                        ),
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
                          tooltip: context.strings.mesAnterior,
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
                                    formatMoney(totalOf(monthExpenses),
                                        Localizations.localeOf(context)),
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
                          tooltip: context.strings.proximoMes,
                          icon: const Icon(Icons.chevron_right),
                          onPressed: _isCurrentMonth ? null : _nextMonth,
                        ),
                      ],
                    ),
                  ),
                ),
                if (visibleExpenses.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        _filtro == null
                            ? context.strings.nenhumGastoMes
                            : context.strings.nenhumGastoPeriodo,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else ...[
                  if (filtroLabel != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$filtroLabel (${visibleExpenses.length})',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _filtro = null),
                              child: Text(context.strings.limpar),
                            ),
                          ],
                        ),
                      ),
                    ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final e = visibleExpenses[i];
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
                      childCount: visibleExpenses.length,
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
  final bool selected;
  final Color? corDestaque;
  final VoidCallback onTap;

  const _SummaryCard(
      {required this.label,
      required this.value,
      required this.flex,
      required this.selected,
      this.corDestaque,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fundoCaixa = corDestaque ??
        (selected ? scheme.primaryContainer : null);
    final onCaixa = fundoCaixa == null ? null : onBackgroundColor(fundoCaixa);
    return Expanded(
      flex: flex,
      child: Card(
        color: fundoCaixa,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                onCaixa ?? scheme.onSurfaceVariant)),
                    if (selected) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.check_circle,
                          size: 14,
                          color: onCaixa ?? scheme.primary),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                FittedBox(
                  child: Text(
                    formatMoney(value, Localizations.localeOf(context)),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: onCaixa),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
