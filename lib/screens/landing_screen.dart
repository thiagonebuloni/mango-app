import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
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
                  radius: 118, // 70% de 168 (3x) — redução de 30%
                  backgroundColor: onCor.withValues(alpha: 0.08),
                  child: Text(
                    perfil?.avatar ?? UserProfile.avatarPadrao,
                    style: const TextStyle(fontSize: 118),
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
                    onPressed: () => showMenuApp(
                      context,
                      ref,
                      onIrParaRelatorios: () => _abrirApp(context, 1),
                    ),
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
}
