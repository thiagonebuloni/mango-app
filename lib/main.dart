import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'db/db.dart';
import 'screens/landing_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');
  await DBHelper.instance.init();
  runApp(const ProviderScope(child: FinancApp()));
}

class FinancApp extends StatelessWidget {
  const FinancApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Financ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
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
