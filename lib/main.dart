import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'db/db.dart';
import 'l10n/app_locale.dart';
import 'screens/first_run_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/splash_screen.dart';
import 'services/crash_log.dart';
import 'services/notificacoes.dart';
import 'state/providers.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Idioma do sistema: inglês (qualquer en_*) abre em en-US; o resto abre
  // em pt-BR (comportamento atual). O MaterialApp resolve de novo via
  // [localeResolutionCallback] quando o sistema troca com o app aberto.
  final system = WidgetsBinding.instance.platformDispatcher.locale;
  final initial = resolveAppLocale(system);
  Intl.defaultLocale = intlLocaleName(initial);
  await initializeDateFormatting('pt_BR');
  await initializeDateFormatting('en_US');
  // Registro de falhas local: ligado antes de tudo, para pegar também um erro
  // de abertura (banco/perfil) — que hoje sumiria só no logcat.
  await iniciarLogDeFalhas();
  instalarHandlersDeErro();
  await DBHelper.instance.init();
  // O perfil é lido antes do primeiro frame para o app já abrir com a cor de
  // fundo do usuário (ver [perfilInicialProvider]).
  final perfil = await DBHelper.instance.loadProfile();
  // Lembretes de fechamento/pagamento dos cartões: o serviço nasce aqui e
  // entra escopado para as telas agendarem/cancelarem pelo mesmo objeto.
  final notificacoes = NotificacoesService();
  await notificacoes.inicializar(initial);
  await notificacoes.agendarTodos(await DBHelper.instance.allCartoes());
  runApp(
    ProviderScope(
      overrides: [
        perfilInicialProvider.overrideWithValue(perfil),
        notificacoesProvider.overrideWithValue(notificacoes),
      ],
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
  const MangoApp({super.key, this.localeTest});

  /// Fixa o idioma do app, ignorando o do sistema.
  ///
  /// Só para teste: o ambiente do `flutter_test` resolve sempre para `en_US`,
  /// então um teste que espera as frases em pt-BR precisa dizer qual é o
  /// idioma do "aparelho" por outro caminho que não o `localeTestValue` da
  /// plataforma (que não chega ao `localeResolutionCallback`). Em produção o
  /// parâmetro fica `null` e vale o idioma do sistema.
  final Locale? localeTest;

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
      home: const LockGate(child: ProfileGate()),
      supportedLocales: supportedAppLocales,
      locale: localeTest,
      localeResolutionCallback: (locale, supported) =>
          localeTest ?? resolveAppLocale(locale),
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
///
/// Enquanto o perfil carrega, mostra o [MangoSplash] (tela de entrada com a
/// identidade do app) em vez de um spinner solto — a mesma arte do splash
/// nativo, então a abertura é contínua do ícone até o conteúdo.
class ProfileGate extends ConsumerWidget {
  const ProfileGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(profileProvider).when(
          loading: () => const MangoSplash(),
          error: (e, _) => Scaffold(
            body: Center(child: Text(context.strings.erroPerfil('$e'))),
          ),
          data: (perfil) => perfil == null
              ? const FirstRunScreen()
              : const LandingScreen(),
        );
  }
}

/// Portão de segurança do app.
///
/// Com um PIN configurado, o [child] fica **desmontado** atrás da
/// [LockScreen]: o conteúdo real nem é construído, então nada dele aparece
/// no "app recentes" do Android. Sem PIN, é um pass-through.
///
/// A tranca volta em toda ida ao segundo plano (`paused` → `resumed`); a
/// janela de alguns segundos do [BloqueioNotifier] cobre o retorno que a
/// própria chamada de biometria provoca em algumas OEMs.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});

  /// O app propriamente dito (em geral o [ProfileGate]).
  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Ler (e não escutar) o provedor: aqui só interessa o valor de agora —
    // o `resumed` pode chegar antes de a configuração terminar de carregar.
    final config = ref.read(segurancaProvider).value;
    ref.read(bloqueioProvider.notifier).reaoVoltar(config);
  }

  @override
  Widget build(BuildContext context) {
    return ref.watch(segurancaProvider).when(
          loading: () => const MangoSplash(),
          error: (e, _) => Scaffold(
            body: Center(
              child: Text(context.strings.erroSegurancaApp('$e')),
            ),
          ),
          data: (config) {
            if (config == null || !ref.watch(bloqueioProvider)) {
              return widget.child;
            }
            return LockScreen(config: config);
          },
        );
  }
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
