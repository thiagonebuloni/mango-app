import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'db/db.dart';
import 'screens/landing_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'state/providers.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');
  await DBHelper.instance.init();
  // O perfil é lido antes do primeiro frame para o app já abrir com a cor de
  // fundo do usuário (ver [perfilInicialProvider]).
  final perfil = await DBHelper.instance.loadProfile();
  runApp(
    ProviderScope(
      overrides: [perfilInicialProvider.overrideWithValue(perfil)],
      child: const FinancApp(),
    ),
  );
}

class FinancApp extends ConsumerWidget {
  const FinancApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Enquanto o profileProvider carrega, usa o perfil lido em `main()`: sem
    // isso o app abriria com a cor padrão e depois "piscaria" para a do
    // usuário.
    final perfil =
        ref.watch(profileProvider).value ?? ref.watch(perfilInicialProvider);

    return MaterialApp(
      title: 'Financ',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(
        corFundoDoPerfil(perfil),
        temaClaro: temaClaroDoPerfil(perfil),
      ),
      home: const ProfileGate(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

/// Decide a primeira tela do app:
///
/// - **primeiro acesso** (nenhum perfil salvo) → cadastro do nome, avatar e
///   cor de fundo;
/// - **demais aberturas** → tela inicial com avatar, nome e os botões
///   "Meus gastos" e "Menu".
class ProfileGate extends ConsumerWidget {
  const ProfileGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(profileProvider).when(
          loading: () => const _CarregandoScreen(),
          error: (e, _) => Scaffold(
            body: Center(child: Text('Erro ao carregar o perfil: $e')),
          ),
          data: (perfil) => perfil == null
              ? const ProfileSetupScreen()
              : const LandingScreen(),
        );
  }
}

class _CarregandoScreen extends StatelessWidget {
  const _CarregandoScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
