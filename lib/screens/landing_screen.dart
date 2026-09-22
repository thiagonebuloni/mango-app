import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                  radius: 56,
                  backgroundColor: onCor.withValues(alpha: 0.08),
                  child: Text(
                    perfil?.avatar ?? UserProfile.avatarPadrao,
                    style: const TextStyle(fontSize: 56),
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RootNav(initialIndex: index)),
    );
  }

  /// Menu da tela inicial: atalhos e opções do perfil.
  void _abrirMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.pie_chart_outline),
              title: const Text('Relatórios'),
              subtitle: const Text('Totais por período, categoria e pagamento'),
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
    );
  }

  void _sobre(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Financ',
      applicationVersion: '1.0.0',
      applicationIcon:
          const Icon(Icons.account_balance_wallet, size: 40),
      children: const [
        Text(
          'Controle de gastos com leitura de cupom fiscal por OCR, 100% '
          'offline. Os dados ficam somente no seu aparelho.',
        ),
      ],
    );
  }
}
