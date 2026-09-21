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

  const ExpenseTile({super.key, required this.expense, this.onTap});

  @override
  Widget build(BuildContext context) {
    final e = expense;
    return ListTile(
      onTap: onTap,
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
        formatBRL(e.valorCentavos),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    );
  }
}

/// Widget reutilizável: FAB + bottom sheet para iniciar um novo lançamento.
///
/// Usado por [HomeScreen] e [ReportsScreen] para garantir que o botão
/// "Novo Gasto" esteja acessível em todas as telas. O [heroTag] deve ser
/// único por tela para evitar conflitos entre FABs no mesmo Navigator.
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
    showModalBottomSheet<void>(
      context: pageContext,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Foto do cupom fiscal'),
              subtitle: const Text('O app lê e preenche os dados'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(pageContext).push(
                  MaterialPageRoute(builder: (_) => const CaptureScreen()),
                ).then((_) => onAdded?.call());
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Lançamento manual'),
              subtitle: const Text('Digite o gasto à mão'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(pageContext).push(
                  MaterialPageRoute(builder: (_) => const ExpenseFormScreen()),
                ).then((_) => onAdded?.call());
              },
            ),
          ],
        ),
      ),
    );
  }
}
