import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db.dart';
import '../l10n/app_locale.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'profile_setup_screen.dart';

/// Primeiro acesso (sem perfil): pergunta se o usuario tem backup.
///
/// - Restaurar: file picker -> salva perfil + lancamentos -> abre a
///   [ProfileSetupScreen] com o perfil restaurado para conferencia.
/// - Criar novo: abre a [ProfileSetupScreen] em branco, como antes.
class FirstRunScreen extends ConsumerStatefulWidget {
  const FirstRunScreen({super.key});

  @override
  ConsumerState<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends ConsumerState<FirstRunScreen> {
  bool _restaurando = false;

  Future<void> _restaurarBackup() async {
    if (_restaurando) return;
    setState(() => _restaurando = true);
    final messenger = ScaffoldMessenger.of(context);
    final s = context.strings;
    try {
      List<PlatformFile> files;
      try {
        files = await FilePicker.pickFiles(
          dialogTitle: s.escolherBackup,
          type: FileType.custom,
          allowedExtensions: const ['csv'],
        );
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(s.erroAbrirSeletor('$e'))));
        return;
      }
      if (files.isEmpty) return;
      final arquivo = files.first;
      // Tamanho conferido antes de ler (A2): arquivo absurdo não entra na
      // memória e o usuário recebe o motivo em vez de um app travado.
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
        messenger.showSnackBar(SnackBar(content: Text(s.erroLerArquivo('$e'))));
        return;
      }
      CsvImportResult result;
      try {
        result = CsvBackup.import(texto);
      } on CsvImportException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
      if (result.perfil == null &&
          result.expenses.isEmpty &&
          result.cartoes.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(s.nenhumDadoBackup)));
        return;
      }
      if (!mounted) return;
      final perfil = result.perfil;
      if (perfil == null) {
        final confirmado = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(s.backupSemPerfil),
            content: Text(s.backupSemPerfilMsg(result.expenses.length)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(d).pop(false),
                  child: Text(s.nao)),
              FilledButton(
                  onPressed: () => Navigator.of(d).pop(true),
                  child: Text(s.importar)),
            ],
          ),
        );
        if (confirmado != true) return;
        final cartoesAtuais =
            await ref.read(cartoesProvider.notifier).mergeAll(result.cartoes);
        final idsPorNome = <String, int>{
          for (final c in cartoesAtuais)
            if (c.id != null) c.nome.trim().toLowerCase(): c.id!,
        };
        await ref.read(expensesProvider.notifier).mergeAll(religarCartoes(
            result.expenses, result.vinculosCartao, idsPorNome));
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(
            content: Text(
                '${s.lancamentosImportados(result.expenses.length)}${result.cartoes.isEmpty ? '' : s.cartoesImportados(result.cartoes.length)}')));
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileSetupScreen()));
        return;
      }
      if (!mounted) return;
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(s.restaurarBackupTitulo),
          content: Text(s.restaurarBackupMsg(
              perfil.nome,
              perfil.temaClaro ? s.temaClaro : s.temaEscuro,
              result.expenses.length)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(d).pop(false),
                child: Text(s.nao)),
            FilledButton(
                onPressed: () => Navigator.of(d).pop(true),
                child: Text(s.restaurar)),
          ],
        ),
      );
      if (confirmado != true) return;
      await ref.read(profileProvider.notifier).save(perfil);
      final cartoesAtuais =
          await ref.read(cartoesProvider.notifier).mergeAll(result.cartoes);
      final idsPorNome = <String, int>{
        for (final c in cartoesAtuais)
          if (c.id != null) c.nome.trim().toLowerCase(): c.id!,
      };
      final adicionados = await ref.read(expensesProvider.notifier).mergeAll(
          religarCartoes(result.expenses, result.vinculosCartao, idsPorNome));
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text(
              '${s.backupRestaurado(adicionados)}${result.cartoes.isEmpty ? '' : s.cartoesImportados(result.cartoes.length)}')));
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileSetupScreen(existing: perfil)));
    } finally {
      if (mounted) setState(() => _restaurando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cor = corFundoDoPerfil(null);
    final onCor = onBackgroundColor(cor);
    final s = context.strings;
    return Scaffold(
      backgroundColor: cor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_balance_wallet, size: 72, color: onCor.withValues(alpha: 0.8)),
                const SizedBox(height: 16),
                Text(s.bemVindoMango,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: onCor)),
                const SizedBox(height: 8),
                Text(s.temBackup,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: onCor)),
                const SizedBox(height: 24),
                SizedBox(
                  width: 260,
                  child: FilledButton.icon(
                    onPressed: _restaurando ? null : _restaurarBackup,
                    icon: _restaurando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.restore),
                    label: Text(s.restaurarBackup),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 260,
                  child: OutlinedButton.icon(
                    onPressed: _restaurando ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileSetupScreen())),
                    icon: const Icon(Icons.person_add),
                    label: Text(s.criarPerfilNovo),
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
