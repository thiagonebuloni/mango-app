import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_locale.dart';
import '../models/models.dart';
import '../services/notificacoes.dart';
import '../state/providers.dart';
import '../widgets/cartao_visual.dart';
import '../widgets/common.dart';
import 'cartao_detalhe_screen.dart';
import 'cartao_form_screen.dart';

/// Tela de cartões de crédito: lista com a arte do cartão, total da fatura do
/// mês selecionado e botão para cadastrar um cartão novo. O toque abre o
/// detalhe (total, por categoria e por dia, como nos Relatórios).
class CartoesScreen extends ConsumerStatefulWidget {
  /// Troca para a aba Gastos/Relatórios quando vindo da navegação raiz;
  /// `null` fora dela (o item do menu apenas fecha).
  final VoidCallback? onVerGastos;
  final VoidCallback? onVerRelatorios;

  const CartoesScreen({super.key, this.onVerGastos, this.onVerRelatorios});

  @override
  ConsumerState<CartoesScreen> createState() => _CartoesScreenState();
}

class _CartoesScreenState extends ConsumerState<CartoesScreen> {
  /// Troca o mês exibido (dia 1).
  ///
  /// O período da tela mora em [mesCartoesProvider], fora do `State`: assim
  /// ele sobrevive à troca de abas e a sair e voltar, e continua
  /// independente do mês escolhido na tela de Gastos.
  void _mudarMes(int delta) =>
      ref.read(mesCartoesProvider.notifier).mudarPor(delta);

  Future<void> _abrirForm({CartaoCredito? cartao}) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CartaoFormScreen(cartao: cartao)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    // Mês guardado no provedor: observá-lo faz a tela reconstruir quando o
    // período muda — e ele não afeta o mês da tela de Gastos.
    final mes = ref.watch(mesCartoesProvider);
    final expensesAsync = ref.watch(expensesForReportsProvider);
    final cartoesAsync = ref.watch(cartoesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.cartoes),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: s.menu,
            onPressed: () => showMenuApp(
              context,
              ref,
              abaAtual: AbaPrincipal.cartoes,
              onIrParaGastos: widget.onVerGastos,
              onIrParaRelatorios: widget.onVerRelatorios,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_cartoes',
        onPressed: _abrirForm,
        icon: const Icon(Icons.add),
        label: Text(s.adicionarCartao),
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(context.strings.erroCarregar('$e'))),
        data: (expenses) => cartoesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              Center(child: Text(context.strings.erroCarregar('$e'))),
          data: (cartoes) => _buildLista(context, cartoes, expenses, mes),
        ),
      ),
    );
  }

  Widget _buildLista(
    BuildContext context,
    List<CartaoCredito> cartoes,
    List<Expense> gastos,
    DateTime mes,
  ) {
    final s = context.strings;
    if (cartoes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.credit_card_off, size: 56),
              const SizedBox(height: 12),
              Text(
                s.nenhumCartao,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(s.nenhumCartaoMsg, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + newExpenseFabClearance(context),
      ),
      children: [
        Center(
          child: SeletorMes(mes: mes, aoTrocar: _mudarMes),
        ),
        const SizedBox(height: 12),
        for (final cartao in cartoes) ...[
          _CartaoComTotal(
            cartao: cartao,
            gastos: gastosDoCartao(gastos, cartao.id!, mes),
            aoAbrir: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    CartaoDetalheScreen(cartaoId: cartao.id!, mes: mes),
              ),
            ),
            aoEditar: () => _abrirForm(cartao: cartao),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Linha de navegação de mês (‹ fevereiro de 2026 ›), travada no mês atual
/// para não "prever" faturas que ainda não existem.
class SeletorMes extends StatelessWidget {
  final DateTime mes;
  final ValueChanged<int> aoTrocar;

  const SeletorMes({super.key, required this.mes, required this.aoTrocar});

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final agora = DateTime.now();
    final eOMesAtual = mes.year == agora.year && mes.month == agora.month;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: s.mesAnterior,
          onPressed: () => aoTrocar(-1),
        ),
        Text(
          formatDateOf(context, mes, (p) => p.monthYear),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: s.proximoMes,
          onPressed: eOMesAtual ? null : () => aoTrocar(1),
        ),
      ],
    );
  }
}

/// Cartão na lista: arte + total da fatura do mês e as datas de
/// fechamento/pagamento (próximas ocorrências). Toque abre o detalhe.
class _CartaoComTotal extends StatelessWidget {
  final CartaoCredito cartao;
  final List<Expense> gastos;
  final VoidCallback aoAbrir;
  final VoidCallback aoEditar;

  const _CartaoComTotal({
    required this.cartao,
    required this.gastos,
    required this.aoAbrir,
    required this.aoEditar,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final total = totalOf(gastos);
    final fechamento = proximoLembrete(cartao.diaFechamento, DateTime.now());
    final pagamento = proximoLembrete(cartao.diaPagamento, DateTime.now());
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: aoAbrir,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CartaoVisual(cartao: cartao, altura: 140),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.totalFatura,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        Text(
                          formatMoneyOf(context, total),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (gastos.isEmpty)
                          Text(
                            s.semGastosCartao,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        s.fechamentoEm(
                          formatDateOf(context, fechamento, (p) => p.dayMonth),
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        s.pagamentoEm(
                          formatDateOf(context, pagamento, (p) => p.dayMonth),
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: s.editarCartao,
                    onPressed: aoEditar,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
