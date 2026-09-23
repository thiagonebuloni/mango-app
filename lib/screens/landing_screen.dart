import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/db.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'profile_setup_screen.dart';
import 'root_nav.dart';

/// Largura dos botões principais da tela inicial (centralizados).
const double kLandingActionWidth = 260;

/// Primeira tela do app: avatar + nome do usuário e os botões "Meus gastos"
/// e "Menu", tudo centralizado sobre a cor de fundo escolhida no cadastro.
class LandingScreen extends ConsumerWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(profileProvider).value;
    final cor = corFundoDoPerfil(perfil);
    final onCor = onBackgroundColor(cor);
    final nome = perfil?.nome.trim() ?? '';

    return Scaffold(
      backgroundColor: cor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 168, // 3x o tamanho original (56)
                  backgroundColor: onCor.withValues(alpha: 0.08),
                  child: Text(
                    perfil?.avatar ?? UserProfile.avatarPadrao,
                    style: const TextStyle(fontSize: 168),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  nome.isEmpty ? 'Olá!' : 'Olá, $nome!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: onCor,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: kLandingActionWidth,
                  child: FilledButton.icon(
                    onPressed: () => _abrirApp(context, 0),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Meus gastos'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: kLandingActionWidth,
                  child: OutlinedButton.icon(
                    onPressed: () => _abrirMenu(context, ref),
                    icon: const Icon(Icons.menu),
                    label: const Text('Menu'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Abre a navegação principal (Gastos na aba [index]).
  void _abrirApp(BuildContext context, int index) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RootNav(initialIndex: index)));
  }

  /// Menu da tela inicial: atalhos e opções do perfil.
  void _abrirMenu(BuildContext context, WidgetRef ref) {
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
              ListTile(
                leading: const Icon(Icons.pie_chart_outline),
                title: const Text('Relatórios'),
                subtitle: const Text(
                  'Totais por período, categoria e pagamento',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _abrirApp(context, 1);
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
                title: const Text('Sobre o Financ'),
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
        '${dir.path}/financ_backup_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      await file.writeAsString(csv, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          title: 'Backup Financ',
          text: 'Backup com ${expenses.length} lançamento(s) do Financ.',
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
      applicationName: 'Financ',
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
}
