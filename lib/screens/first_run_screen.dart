import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db.dart';
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
    try {
      List<PlatformFile> files;
      try {
        files = await FilePicker.pickFiles(
          dialogTitle: 'Escolher arquivo de backup',
          type: FileType.custom,
          allowedExtensions: const ['csv'],
        );
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Erro ao abrir o seletor: $e')));
        return;
      }
      if (files.isEmpty) return;
      String texto;
      try {
        texto = utf8.decode(await files.first.readAsBytes());
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Erro ao ler o arquivo: $e')));
        return;
      }
      final result = CsvBackup.import(texto);
      if (result.perfil == null && result.expenses.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('Nenhum dado valido encontrado no arquivo de backup')));
        return;
      }
      if (!mounted) return;
      final perfil = result.perfil;
      if (perfil == null) {
        final confirmado = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Backup sem perfil'),
            content: Text('O arquivo tem ${result.expenses.length} lancamento(s), mas sem os dados do perfil. Importar e continuar o cadastro?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Nao')),
              FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Importar')),
            ],
          ),
        );
        if (confirmado != true) return;
        await ref.read(expensesProvider.notifier).mergeAll(result.expenses);
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text('${result.expenses.length} lancamento(s) importado(s). Complete seu perfil.')));
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileSetupScreen()));
        return;
      }
      if (!mounted) return;
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Restaurar backup?'),
          content: Text('Perfil de ${perfil.nome.isEmpty ? "usuario" : perfil.nome} (tema ${perfil.temaClaro ? "claro" : "escuro"}) com ${result.expenses.length} lancamento(s). Restaurar?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Nao')),
            FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Restaurar')),
          ],
        ),
      );
      if (confirmado != true) return;
      await ref.read(profileProvider.notifier).save(perfil);
      final adicionados = await ref.read(expensesProvider.notifier).mergeAll(result.expenses);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Backup restaurado: $adicionados lancamento(s) novo(s). Confira seu perfil.')));
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileSetupScreen(existing: perfil)));
    } finally {
      if (mounted) setState(() => _restaurando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cor = corFundoDoPerfil(null);
    final onCor = onBackgroundColor(cor);
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
                Text('Bem-vindo ao Mango!', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: onCor)),
                const SizedBox(height: 8),
                Text('Voce ja tem um arquivo de backup?', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: onCor)),
                const SizedBox(height: 24),
                SizedBox(
                  width: 260,
                  child: FilledButton.icon(
                    onPressed: _restaurando ? null : _restaurarBackup,
                    icon: _restaurando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.restore),
                    label: const Text('Restaurar backup'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 260,
                  child: OutlinedButton.icon(
                    onPressed: _restaurando ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileSetupScreen())),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Criar perfil novo'),
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
