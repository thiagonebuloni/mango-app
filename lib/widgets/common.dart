import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/db.dart';
import '../models/models.dart';
import '../screens/capture_screen.dart';
import '../screens/diagnostico_screen.dart';
import '../screens/expense_form_screen.dart';
import '../screens/profile_setup_screen.dart';
import '../screens/seguranca_screen.dart';
import '../services/app_info.dart';
import '../state/providers.dart';

import '../l10n/app_locale.dart';
import '../l10n/app_strings.dart';
import '../l10n/l10n_format.dart';

/// Moeda no locale vigente (compat: sem locale = pt-BR, igual a antes).
String formatBRL(int centavos, [Locale? locale]) =>
    formatMoney(centavos, locale ?? const Locale('pt', 'BR'));

/// Moeda no locale do [context] (telas devem preferir esta).
String formatMoneyOf(BuildContext context, int centavos) =>
    formatMoney(centavos, Localizations.localeOf(context));

/// Data no locale do [context] usando o padrão escolhido.
String formatDateOf(BuildContext context, DateTime date,
        String Function(DatePatterns p) pick) =>
    formatDate(date, pick, Localizations.localeOf(context));

/// Locale intl (pt_BR/en_US) do [context] para DateFormat direto.
String intlOf(BuildContext context) =>
    intlLocaleName(Localizations.localeOf(context));

/// Rótulos localizados (categoria/pagamento/tipo) no [context].
String categoryLabelOf(BuildContext context, Category c) =>
    context.strings.categoriaLabel(c.name);
String paymentLabelOf(BuildContext context, PaymentMethod p) =>
    context.strings.pagamentoLabel(p.name);
String entryKindLabelOf(BuildContext context, EntryKind k) =>
    context.strings.tipoLabel(k.name);

/// Formata texto digitado ("1.234,56" ou "1234,5") em centavos.
///
/// Limita a faixa a R$ 1 tri (`1e12`): valores maiores vêm de entrada
/// absurda (ex.: 307+ dígitos colados) e `Infinity.round()` lançaria
/// `UnsupportedError` quebrando o build do formulário.
int? parseMoneyInput(String input) {
  final cleaned = input
      .replaceAll(RegExp(r'[^0-9,.]'), '')
      .replaceAll('.', '')
      .replaceAll(',', '.')
      .trim();
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || !value.isFinite || value <= 0 || value > 1e12) {
    return null;
  }
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
    final loc = Localizations.localeOf(context);
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
        '${DateFormat(loc.languageCode == 'en' ? 'MMM dd' : 'dd MMM', intlLocaleName(loc)).format(e.dataHora)} · ${context.strings.categoriaLabel(e.categoria.name)}'
        '${e.origem == ExpenseOrigin.ocr ? (loc.languageCode == 'en' ? ' · receipt' : ' · 📷 cupom') : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        e.isReceita ? '+ ${formatMoney(e.valorCentavos, loc)}' : formatMoney(e.valorCentavos, loc),
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
                  title: Text(context.strings.despesas),
                  subtitle: Text(context.strings.fotoOuManual),
                  onTap: () =>
                      setSheetState(() => secao = _SecaoLancamento.despesas),
                ),
                ListTile(
                  leading: const Icon(Icons.attach_money),
                  title: Text(context.strings.receita),
                  subtitle: Text(context.strings.receitaManual),
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
                  title: Text(context.strings.despesas),
                  subtitle: Text(context.strings.fotoOuManual),
                  onTap: () =>
                      setSheetState(() => secao = _SecaoLancamento.inicial),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: Text(context.strings.fotoCupomFiscal),
                  subtitle: Text(context.strings.appLePreenche),
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
                  title: Text(context.strings.lancamentoManual),
                  subtitle: Text(context.strings.digiteGasto),
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
                title: Text(context.strings.gastos),
                subtitle: Text(context.strings.lancamentosSub),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onIrParaGastos?.call();
                },
              ),
            if (abaAtual != AbaPrincipal.relatorios)
              ListTile(
                leading: const Icon(Icons.pie_chart_outline),
                title: Text(context.strings.relatorios),
                subtitle: Text(context.strings.totaisSub),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onIrParaRelatorios?.call();
                },
              ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: Text(context.strings.editarPerfil),
              subtitle: Text(context.strings.editarPerfilSub),
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
              leading: const Icon(Icons.lock_outline),
              title: Text(context.strings.seguranca),
              subtitle: Text(context.strings.segurancaSub),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SegurancaScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: Text(context.strings.exportar),
              subtitle: Text(context.strings.exportarSub),
              onTap: () {
                Navigator.pop(sheetContext);
                _exportarCsv(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(context.strings.importarBackup),
              subtitle: Text(context.strings.importarBackupSub),
              onTap: () {
                Navigator.pop(sheetContext);
                _importarCsv(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: Text(context.strings.diagnostico),
              subtitle: Text(context.strings.diagnosticoMsg),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DiagnosticoScreen(),
                  ),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(context.strings.sobre),
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

/// Nome do arquivo de backup CSV: `mango_backup_DDMMYYYYHHmmSS.csv`,
/// onde a numeração é dia/mês/ano/hora/minuto/segundo (ex.:
/// `mango_backup_27092026084157.csv` = 27/09/2026 08:41:57).
String mangoBackupFileName([DateTime? when]) {
  final now = when ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final dd = two(now.day);
  final mm = two(now.month);
  final yyyy = now.year.toString().padLeft(4, '0');
  final hh = two(now.hour);
  final mi = two(now.minute);
  final ss = two(now.second);
  return 'mango_backup_$dd$mm$yyyy$hh$mi$ss.csv';
}

/// Lê um backup CSV a partir de um fluxo de bytes, com teto de memória (A2).
///
/// Ler com `readAsBytes()` carrega o arquivo inteiro de uma vez: um arquivo
/// escolhido por engano (backup gigante, vídeo renomeado para `.csv`) derruba
/// o app por falta de memória. Aqui os blocos são acumulados e a leitura é
/// **interrompida** assim que o total passa de [CsvBackup.maxBytes], lançando
/// [CsvImportException] com a mensagem pronta para o usuário. A decodificação
/// só acontece no fim, então um caractere UTF-8 partido entre dois blocos é
/// lido corretamente.
Future<String> lerBackupCsv(Stream<List<int>> bytes) async {
  final acumulado = BytesBuilder(copy: false);
  await for (final bloco in bytes) {
    acumulado.add(bloco);
    if (acumulado.length > CsvBackup.maxBytes) {
      // `validateImportSize` só devolve null dentro do limite, e aqui o
      // limite já foi ultrapassado.
      throw CsvImportException(
        CsvBackup.validateImportSize(acumulado.length)!,
      );
    }
  }
  return utf8.decode(acumulado.takeBytes());
}

/// Exporta os lançamentos em CSV e abre a folha de compartilhamento do
/// sistema (salvar em arquivos, enviar por e-mail/mensageiro etc.).
///
/// Antes de gerar o arquivo, confirma com o usuário: o backup é **texto puro,
/// sem senha**, e sai do app pela folha de compartilhamento (nuvem, mensageiro,
/// e-mail...). O mesmo aviso vai gravado no topo do arquivo
/// ([CsvBackup.csvAviso]), para quem abri-lo depois.
Future<void> _exportarCsv(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  // Frases capturadas antes dos awaits: o context não cruza gap assíncrono.
  final s = context.strings;
  if (!await _confirmarExportacao(context)) return;
  if (!context.mounted) return;
  try {
    final expenses = ref.read(expensesProvider).value ?? const <Expense>[];
    final perfil = ref.read(profileProvider).value;
    final csv = CsvBackup.export(expenses, perfil: perfil);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/${mangoBackupFileName()}',
    );
    await file.writeAsString(csv, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        title: 'Backup Mango',
        text: s.backupCom(expenses.length, perfil?.nome),
      ),
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(s.backupAviso),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(s.falhaExportar('$e'))));
  }
}

/// Pergunta se o usuário quer mesmo exportar, explicando que o CSV é texto
/// puro (sem senha) e vai para onde ele escolher na folha de compartilhamento.
/// `true` = seguir com a exportação.
Future<bool> _confirmarExportacao(BuildContext context) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.strings.exportar),
      content: Text(context.strings.backupAviso),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(context.strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(context.strings.exportar),
        ),
      ],
    ),
  );
  return confirmado == true;
}

/// Escolhe um CSV e agrega os lançamentos ao app, sem apagar nada.
Future<void> _importarCsv(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  // Frases capturadas antes dos awaits: o context não cruza gap assíncrono.
  final s = context.strings;
  List<PlatformFile> files;
  try {
    files = await FilePicker.pickFiles(
      dialogTitle: s.importarBackup,
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(s.erroAbrirSeletor('$e'))),
    );
    return;
  }
  if (files.isEmpty) return; // usuário cancelou
  final arquivo = files.first;
  // Confere o tamanho informado pelo seletor antes de ler qualquer byte: um
  // arquivo absurdo nem chega a ser carregado na memória (A2).
  final tamanho = arquivo.lengthSync() ?? await arquivo.length();
  if (tamanho != null) {
    final recusa = CsvBackup.validateImportSize(tamanho);
    if (recusa != null) {
      messenger.showSnackBar(SnackBar(content: Text(recusa)));
      return;
    }
  }
  String texto;
  try {
    texto = await lerBackupCsv(arquivo.readAsByteStream());
  } on CsvImportException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(s.erroLerArquivo('$e'))),
    );
    return;
  }
  CsvImportResult result;
  try {
    result = CsvBackup.import(texto);
  } on CsvImportException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (result.expenses.isEmpty && result.perfil == null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(s.nenhumLancamentoArquivo),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  final tema = result.perfil!.temaClaro ? s.temaClaro : s.temaEscuro;
  final perfilMsg = result.perfil == null
      ? ''
      : s.perfilTambemRestaurado(result.perfil!.nome, tema);
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(s.importarBackupTitulo),
      content: Text(s.importarBackupMsg(result.expenses.length, perfilMsg)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(s.nao),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(s.importar),
        ),
      ],
    ),
  );
  if (confirmado != true) return;
  if (result.perfil != null) {
    await ref.read(profileProvider.notifier).save(result.perfil!);
  }
  final adicionados =
      await ref.read(expensesProvider.notifier).mergeAll(result.expenses);
  final duplicados = result.expenses.length - adicionados;
  final ignoradas =
      result.skipped > 0 ? s.ignoradasLines(result.skipped) : '';
  messenger.showSnackBar(
    SnackBar(
      content: Text(s.importacaoOk(adicionados, duplicados, ignoradas)),
    ),
  );
}

/// Janela "Sobre o Mango".
///
/// A versão é lida do próprio app ([versaoDoApp]): o valor já esteve fixo no
/// código e passaria a mentir na primeira subida de versão. Quando ela não
/// pode ser lida, a linha da versão simplesmente não aparece.
Future<void> _sobre(BuildContext context) async {
  final versao = await versaoDoApp();
  if (!context.mounted) return;
  showAboutDialog(
    context: context,
    applicationName: 'Mango',
    applicationVersion: versao,
    applicationIcon: const Icon(Icons.account_balance_wallet, size: 40),
    children: [
      Text(
        context.strings.sobreTexto,
      ),
    ],
  );
}

