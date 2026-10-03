import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db.dart';
import '../l10n/app_locale.dart';
import '../models/models.dart';
import '../services/notificacoes.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/cartao_visual.dart';
import '../widgets/common.dart';
import 'cartao_form_screen.dart';
import 'cartoes_screen.dart';
import 'reports_screen.dart';

/// Detalhe de um cartão no mês escolhido: total da fatura, próximas datas de
/// fechamento/pagamento e os gastos **por categoria e por dia** — os mesmos
/// cartões de relatório da tela de Relatórios.
class CartaoDetalheScreen extends ConsumerStatefulWidget {
  final int cartaoId;

  /// Mês aberto inicialmente (vem da tela de cartões).
  final DateTime mes;

  const CartaoDetalheScreen({
    super.key,
    required this.cartaoId,
    required this.mes,
  });

  @override
  ConsumerState<CartaoDetalheScreen> createState() =>
      _CartaoDetalheScreenState();
}

class _CartaoDetalheScreenState extends ConsumerState<CartaoDetalheScreen> {
  late DateTime _mes = Periods.startOfMonth(widget.mes);

  void _mudarMes(int delta) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + delta));
  }

  Future<void> _editar(CartaoCredito cartao) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CartaoFormScreen(cartao: cartao)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final cartoesAsync = ref.watch(cartoesProvider);
    final expensesAsync = ref.watch(expensesForReportsProvider);
    final destaque = corDestaqueDoPerfil(ref.watch(profileProvider).value);

    return cartoesAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(child: Text(context.strings.erroCarregar('$e'))),
      ),
      data: (cartoes) {
        CartaoCredito? cartao;
        for (final c in cartoes) {
          if (c.id == widget.cartaoId) cartao = c;
        }
        if (cartao == null) {
          // Cartão apagado em outra tela: sai sem quebrar.
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(s.nenhumCartao)),
          );
        }
        final alvo = cartao;
        return Scaffold(
          appBar: AppBar(
            title: Text(alvo.nome),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: s.editarCartao,
                onPressed: () => _editar(alvo),
              ),
            ],
          ),
          body: expensesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text(context.strings.erroCarregar('$e'))),
            data: (expenses) => _buildCorpo(context, alvo, expenses, destaque),
          ),
        );
      },
    );
  }

  Widget _buildCorpo(
    BuildContext context,
    CartaoCredito cartao,
    List<Expense> expenses,
    Color? destaque,
  ) {
    final s = context.strings;
    final gastos = gastosDoCartao(expenses, cartao.id!, _mes);
    final total = totalOf(gastos);
    final agora = DateTime.now();
    final fechamento = proximoLembrete(cartao.diaFechamento, agora);
    final pagamento = proximoLembrete(cartao.diaPagamento, agora);

    // Corpo em uma coluna rolável (não `ListView`): o conteúdo é curto e
    // precisa estar todo montado — inclusive o que começa abaixo da primeira
    // tela, que a lista preguiçosa só constrói ao rolar.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CartaoVisual(cartao: cartao),
          const SizedBox(height: 8),
          Center(
            child: SeletorMes(mes: _mes, aoTrocar: _mudarMes),
          ),
          const SizedBox(height: 8),
          Card(
            color: destaque,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.faturaDe(formatDateOf(context, _mes, (p) => p.monthYear)),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color:
                          destaque == null ? null : onBackgroundColor(destaque),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.totalFatura,
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          destaque == null ? null : onBackgroundColor(destaque),
                    ),
                  ),
                  Text(
                    formatMoneyOf(context, total),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color:
                          destaque == null ? null : onBackgroundColor(destaque),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${s.fechamentoEm(formatDateOf(context, fechamento, (p) => p.dayMonth))}'
                    '  ·  '
                    '${s.pagamentoEm(formatDateOf(context, pagamento, (p) => p.dayMonth))}',
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          destaque == null ? null : onBackgroundColor(destaque),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (gastos.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(s.semGastosCartao),
              ),
            )
          else ...[
            CategoryCard(data: sumByCategory(gastos), corDestaque: destaque),
            const SizedBox(height: 16),
            DaySummaryCard(
              dayMap: sumByDay(gastos),
              expenses: gastos,
              corDestaque: destaque,
            ),
          ],
        ],
      ),
    );
  }
}
