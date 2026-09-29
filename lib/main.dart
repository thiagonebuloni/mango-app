import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'db/db.dart';
import 'screens/first_run_screen.dart';
import 'screens/landing_screen.dart';
import 'services/crash_log.dart';
import 'state/providers.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');
  // Registro de falhas local: ligado antes de tudo, para pegar também um erro
  // de abertura (banco/perfil) — que hoje sumiria só no logcat.
  await iniciarLogDeFalhas();
  instalarHandlersDeErro();
  await DBHelper.instance.init();
  // O perfil é lido antes do primeiro frame para o app já abrir com a cor de
  // fundo do usuário (ver [perfilInicialProvider]).
  final perfil = await DBHelper.instance.loadProfile();
  runApp(
    ProviderScope(
      overrides: [perfilInicialProvider.overrideWithValue(perfil)],
      child: const MangoApp(),
    ),
  );
}

/// Liga o registro de falhas local ao Flutter, antes do primeiro frame.
///
/// São três os pontos em que o framework engole um erro em release (viram um
/// quadro cinza e vão só para o logcat, onde ninguém lê):
///
/// - `FlutterError.onError` — erros reportados pelo próprio framework (build,
///   layout, imagem...);
/// - `PlatformDispatcher.onError` — exceções assíncronas sem `try/catch`;
/// - `ErrorWidget.builder` — o que aparece no lugar da parte da tela que
///   falhou (o erro em si já é registrado pelo primeiro item; aqui só se
///   troca a tela).
///
/// Em **debug** mantém o comportamento padrão (tela vermelha + detalhe no
/// console), que é o que se quer ao desenvolver; a tela amigável é só para
/// release — [telaAmigavel] existe para o teste conseguir exercitá-la.
///
/// [dir] aponta o arquivo de log (em produção fica `null` e o diretório é o
/// dos documentos do app).
void instalarHandlersDeErro({Directory? dir, bool? telaAmigavel}) {
  final amigavel = telaAmigavel ?? kReleaseMode;
  FlutterError.onError = (detalhes) {
    registrarFalha(
      detalhes.exception,
      detalhes.stack,
      contexto: detalhes.library,
      dir: dir,
    );
    FlutterError.presentError(detalhes);
  };
  ui.PlatformDispatcher.instance.onError = (erro, pilha) {
    registrarFalha(erro, pilha, contexto: 'não tratado', dir: dir);
    // `true` = tratado: o detalhe está no log local, não precisa derrubar o
    // app — e deixar escapar causaria um erro ainda não tratado, em cadeia.
    return true;
  };
  if (amigavel) {
    ErrorWidget.builder = (_) => const _ErroAmigavel();
  }
}

class MangoApp extends ConsumerWidget {
  const MangoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Enquanto o profileProvider carrega, usa o perfil lido em `main()`: sem
    // isso o app abriria com a cor padrão e depois "piscaria" para a do
    // usuário.
    final perfil =
        ref.watch(profileProvider).value ?? ref.watch(perfilInicialProvider);

    return MaterialApp(
      title: 'Mango',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(
        corFundoDoPerfil(perfil),
        temaClaro: temaClaroDoPerfil(perfil),
        corAcento: corAcentoDoPerfil(perfil),
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
/// - **primeiro acesso** (nenhum perfil salvo) → pergunta se o usuário tem
///   um arquivo de backup para restaurar ou se quer criar um perfil novo;
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
              ? const FirstRunScreen()
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

/// Parte da tela que falhou, em release.
///
/// No lugar do quadro cinza padrão, uma frase curta dizendo o que houve e
/// onde achar o detalhe — que já está gravado pelo `FlutterError.onError` e
/// aparece na tela *Diagnóstico*. Sem cor própria: herda o estilo do tema
/// ambiente (escuro ou claro), que é sempre legível.
class _ErroAmigavel extends StatelessWidget {
  const _ErroAmigavel();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Esta parte da tela não pôde ser desenhada.\n'
            'Menu → Diagnóstico mostra o detalhe da falha.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}
