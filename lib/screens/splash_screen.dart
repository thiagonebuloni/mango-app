import 'package:flutter/material.dart';

/// Splash/tela de entrada do Mango (identidade da manga).
///
/// Usada em dois momentos:
/// - em `main.dart` ([ProfileGate] e [LockGate]) enquanto o perfil e a
///   configuração de segurança ainda estão carregando — evita um frame em
///   branco ou um spinner solto antes de saber a primeira tela;
/// - como referência visual do splash nativo (fundo laranja + manga
///   centralizada em `launch_background.xml` no Android e no
///   `LaunchScreen.storyboard` no iOS, exibidos antes do primeiro frame).
///
/// Sem assets: o gradiente replica o do ícone (`tool/generate_icon.py`,
/// laranja da manga -> amarelo quente) e a manga é o emoticon U+1F96D, então
/// não precisa declarar nada em `pubspec.yaml`.
class MangoSplash extends StatelessWidget {
  const MangoSplash({super.key});

  /// Laranja da manga (topo do gradiente, igual ao do ícone).
  static const Color laranjaTopo = Color(0xFFFF9E1F);

  /// Amarelo quente (base do gradiente, igual ao do ícone).
  static const Color amareloBase = Color(0xFFFFD140);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [laranjaTopo, amareloBase],
          ),
        ),
        child: const SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('🥭', style: TextStyle(fontSize: 96)),
                SizedBox(height: 16),
                Text(
                  'Mango',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        offset: Offset(0, 1),
                        blurRadius: 4,
                        color: Color(0x66000000),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 32),
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
