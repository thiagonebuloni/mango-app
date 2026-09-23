import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../screens/capture_screen.dart';
import '../screens/expense_form_screen.dart';

final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);

String formatBRL(int centavos) => _brl.format(centavos / 100);

/// Formata texto digitado ("1.234,56" ou "1234,5") em centavos.
int? parseMoneyInput(String input) {
  final cleaned = input
      .replaceAll(RegExp(r'[^0-9,.]'), '')
      .replaceAll('.', '')
      .replaceAll(',', '.')
      .trim();
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || value <= 0) return null;
  return (value * 100).round();
}

/// Cor de texto/ícone legível sobre [background] (usada nas telas em que o
/// usuário escolhe a cor de fundo).
Color onBackgroundColor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black87;

extension CategoryVisual on Category {
  IconData get icon {
    switch (this) {
      case Category.alimentacao:
        return Icons.bakery_dining;
      case Category.transporte:
        return Icons.directions_car;
      case Category.mercado:
        return Icons.shopping_cart;
      case Category.saude:
        return Icons.local_pharmacy;
      case Category.lazer:
        return Icons.celebration;
      case Category.moradia:
        return Icons.home;
      case Category.outros:
        return Icons.category;
    }
  }

  Color get color {
    switch (this) {
      case Category.alimentacao:
        return const Color(0xFFF59E0B);
      case Category.transporte:
        return const Color(0xFF3B82F6);
      case Category.mercado:
        return const Color(0xFF10B981);
      case Category.saude:
        return const Color(0xFFEF4444);
      case Category.lazer:
        return const Color(0xFF8B5CF6);
      case Category.moradia:
        return const Color(0xFF0EA5E9);
      case Category.outros:
        return const Color(0xFF6B7280);
    }
  }
}

class ExpenseTile extends StatelessWidget {
  final Expense expense;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ExpenseTile({super.key, required this.expense, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final e = expense;
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: CircleAvatar(
        backgroundColor: e.categoria.color.withValues(alpha: 0.15),
        foregroundColor: e.categoria.color,
        child: Icon(e.categoria.icon),
      ),
      title: Text(
        e.descricao.isNotEmpty ? e.descricao : e.estabelecimento,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${DateFormat('dd MMM', 'pt_BR').format(e.dataHora)} · ${e.categoria.label}'
        '${e.origem == ExpenseOrigin.ocr ? ' · 📷 cupom' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        e.isReceita ? '+ ${formatBRL(e.valorCentavos)}' : formatBRL(e.valorCentavos),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: e.isReceita ? const Color(0xFF059669) : null,
        ),
      ),
    );
  }
}

/// Altura do FAB usado por [NewExpenseMenu] (`FloatingActionButton.large`).
/// O Material define 96x96 tanto no M2 quanto no M3.
const double kNewExpenseFabSize = 96;

/// Espaço vertical que o [NewExpenseMenu] ocupa sobre o conteúdo: altura do
/// FAB + margem de respiro acima/abaixo + área segura do aparelho.
///
/// Use como padding inferior (ou espaçador final) de listas roláveis, senão o
/// botão cobre o último item e a página não rola o suficiente para vê-lo.
double newExpenseFabClearance(BuildContext context) =>
    kNewExpenseFabSize +
    kFloatingActionButtonMargin * 2 +
    MediaQuery.paddingOf(context).bottom;

/// Seções do menu de novo lançamento: nível inicial (Despesas / Receita) e
/// opções de despesa (foto do cupom ou lançamento manual).
enum _SecaoLancamento { inicial, despesas }

/// Widget reutilizável: FAB + bottom sheet para iniciar um novo lançamento.
///
/// Primeiro nível com **Despesas** e **Receita**; ao escolher Despesas
/// aparecem as opções de foto do cupom ou lançamento manual. Usado por
/// [HomeScreen] e [ReportsScreen]. O [heroTag] deve ser único por tela para
/// evitar conflitos entre FABs no mesmo Navigator.
class NewExpenseMenu extends StatelessWidget {
  final String heroTag;
  final VoidCallback? onAdded;

  const NewExpenseMenu({super.key, required this.heroTag, this.onAdded});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.large(
      heroTag: heroTag,
      onPressed: () => _showAddMenu(context),
      child: const Icon(Icons.add),
    );
  }

  void _showAddMenu(BuildContext pageContext) {
    // Nível 1: Despesas | Receita. Nível 2 (despesas): foto ou manual.
    var secao = _SecaoLancamento.inicial;
    showModalBottomSheet<void>(
      context: pageContext,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (secao == _SecaoLancamento.inicial) ...[
                ListTile(
                  leading: const Icon(Icons.shopping_cart_outlined),
                  title: const Text('Despesas'),
                  subtitle: const Text('Foto do cupom ou lançamento manual'),
                  onTap: () =>
                      setSheetState(() => secao = _SecaoLancamento.despesas),
                ),
                ListTile(
                  leading: const Icon(Icons.attach_money),
                  title: const Text('Receita'),
                  subtitle: const Text('Lançamento manual de entrada'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(pageContext)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => const ExpenseFormScreen(
                              tipoInicial: EntryKind.receita,
                            ),
                          ),
                        )
                        .then((_) => onAdded?.call());
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.arrow_back),
                  title: const Text('Despesas'),
                  subtitle: const Text('Foto do cupom ou lançamento manual'),
                  onTap: () =>
                      setSheetState(() => secao = _SecaoLancamento.inicial),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Foto do cupom fiscal'),
                  subtitle: const Text('O app lê e preenche os dados'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(pageContext)
                        .push(
                          MaterialPageRoute(builder: (_) => const CaptureScreen()),
                        )
                        .then((_) => onAdded?.call());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Lançamento manual'),
                  subtitle: const Text('Digite o gasto à mão'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(pageContext)
                        .push(
                          MaterialPageRoute(
                              builder: (_) => const ExpenseFormScreen()),
                        )
                        .then((_) => onAdded?.call());
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
