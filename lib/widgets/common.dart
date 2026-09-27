import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/db.dart';
import '../models/models.dart';
import '../screens/capture_screen.dart';
import '../screens/expense_form_screen.dart';
import '../screens/profile_setup_screen.dart';
import '../state/providers.dart';

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
      case Category.salario:
        return Icons.work;
      case Category.investimentos:
        return Icons.trending_up;
      case Category.bonificacao:
        return Icons.card_giftcard;
      case Category.freelance:
        return Icons.laptop_mac;
      case Category.rendaExtra:
        return Icons.savings;
      case Category.aluguel:
        return Icons.key;
      case Category.pensao:
        return Icons.family_restroom;
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
      case Category.salario:
        return const Color(0xFF16A34A);
      case Category.investimentos:
        return const Color(0xFF0D9488);
      case Category.bonificacao:
        return const Color(0xFFCA8A04);
      case Category.freelance:
        return const Color(0xFF7C3AED);
      case Category.rendaExtra:
        return const Color(0xFF059669);
      case Category.aluguel:
        return const Color(0xFF0284C7);
      case Category.pensao:
        return const Color(0xFFDB2777);
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

/// Aba da navegação principal em que o menu foi aberto.
///
/// Define qual item de navegação o menu exibe: sempre a aba oposta à atual.
enum AbaPrincipal { gastos, relatorios, inicial }

/// Menu compartilhado do app: tela inicial (botão "Menu") e o ícone de menu
/// no canto superior direito das telas Gastos e Relatórios.
///
/// Sempre oferece a aba oposta à [abaAtual]: aberto na aba Gastos mostra
/// "Relatórios" e aberto em Relatórios mostra "Gastos". Na tela inicial
/// ([AbaPrincipal.inicial]), que contém as duas abas, o menu mostra as duas.
/// Os callbacks `onIrPara*` são opcional: sem eles (tela fora da navegação
/// raiz ou já nela) o item apenas fecha o menu.
void showMenuApp(
  BuildContext context,
  WidgetRef ref, {
  AbaPrincipal abaAtual = AbaPrincipal.inicial,
  VoidCallback? onIrParaGastos,
  VoidCallback? onIrParaRelatorios,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      // Rolável: com Exportar/Importar CSV o menu passou a ter mais itens
      // do que a altura do sheet em telas/aparelhos pequenos.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (abaAtual != AbaPrincipal.gastos)
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Gastos'),
                subtitle: const Text('Lançamentos de despesas e receitas'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onIrParaGastos?.call();
                },
              ),
            if (abaAtual != AbaPrincipal.relatorios)
              ListTile(
                leading: const Icon(Icons.pie_chart_outline),
                title: const Text('Relatórios'),
                subtitle: const Text(
                  'Totais por período, categoria e pagamento',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onIrParaRelatorios?.call();
                },
              ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Editar perfil'),
              subtitle: const Text('Nome, avatar e cor de fundo'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfileSetupScreen(
                      existing: ref.read(profileProvider).value,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Exportar em CSV'),
              subtitle: const Text('Salvar backup dos lançamentos'),
              onTap: () {
                Navigator.pop(sheetContext);
                _exportarCsv(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Importar em CSV'),
              subtitle: const Text('Soma o CSV sem apagar registros'),
              onTap: () {
                Navigator.pop(sheetContext);
                _importarCsv(context, ref);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Sobre o Mango'),
              onTap: () {
                Navigator.pop(sheetContext);
                _sobre(context);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Exporta os lançamentos em CSV e abre a folha de compartilhamento do
/// sistema (salvar em arquivos, enviar por e-mail/mensageiro etc.).
Future<void> _exportarCsv(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final expenses = ref.read(expensesProvider).value ?? const <Expense>[];
    final csv = CsvBackup.export(expenses);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/mango_backup_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(csv, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        title: 'Backup Mango',
        text: 'Backup com ${expenses.length} lançamento(s) do Mango.',
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Erro ao exportar: $e')));
  }
}

/// Escolhe um CSV e agrega os lançamentos ao app, sem apagar nada.
Future<void> _importarCsv(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  List<PlatformFile> files;
  try {
    files = await FilePicker.pickFiles(
      dialogTitle: 'Importar backup CSV',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Erro ao abrir o seletor: $e')),
    );
    return;
  }
  if (files.isEmpty) return; // usuário cancelou
  String texto;
  try {
    texto = utf8.decode(await files.first.readAsBytes());
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Erro ao ler o arquivo: $e')),
    );
    return;
  }
  final result = CsvBackup.import(texto);
  if (result.expenses.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Nenhum lançamento válido encontrado no arquivo'),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Importar backup?'),
      content: Text(
        'Os ${result.expenses.length} lançamento(s) do CSV serão somados '
        'aos já existentes. Duplicatas são ignoradas e nenhum registro '
        'do aparelho é apagado.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Não'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Importar'),
        ),
      ],
    ),
  );
  if (confirmado != true) return;
  final adicionados =
      await ref.read(expensesProvider.notifier).mergeAll(result.expenses);
  final duplicados = result.expenses.length - adicionados;
  final ignoradas = result.skipped > 0
      ? ' ${result.skipped} linha(s) inválida(s) ignorada(s).'
      : '';
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        'Importação concluída: $adicionados lançamento(s) novo(s), '
        '$duplicados duplicado(s) ignorado(s).$ignoradas',
      ),
    ),
  );
}

void _sobre(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: 'Mango',
    applicationVersion: '1.0.0',
    applicationIcon: const Icon(Icons.account_balance_wallet, size: 40),
    children: const [
      Text(
        'Controle de gastos com leitura de cupom fiscal por OCR, 100% '
        'offline. Os dados ficam somente no seu aparelho.',
      ),
    ],
  );
}

