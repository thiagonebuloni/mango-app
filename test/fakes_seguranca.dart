import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mango/l10n/app_locale.dart';
import 'package:mango/models/models.dart';
import 'package:mango/services/seguranca.dart';
import 'package:mango/state/providers.dart';

/// Iterações reduzidas para os testes: o PBKDF2 é caro de propósito e aqui
/// isso só deixaria a suíte lenta. O custo real é coberto em
/// `seguranca_test.dart`.
const int kIteracoesDeTeste = 500;

/// PIN de teste com hash **de verdade** (só mais barato): as telas conferem
/// o PIN pelas funções reais do app, não por um atalho.
Future<SegurancaConfig> configDeTeste(String pin, {bool biometria = false}) =>
    criarConfigPin(pin, biometria: biometria, iteracoes: kIteracoesDeTeste);

/// Notificador de segurança que guarda tudo em memória — os testes de widget
/// não abrem o SQLite de verdade.
class FakeSegurancaNotifier extends SegurancaNotifier {
  FakeSegurancaNotifier([this._config]);

  SegurancaConfig? _config;

  /// Configuração atual, para as asserções dos testes.
  SegurancaConfig? get config => _config;

  @override
  Future<SegurancaConfig?> build() async => _config;

  @override
  Future<void> ativar({required String pin, required bool biometria}) async {
    _config = await configDeTeste(pin, biometria: biometria);
    state = AsyncData(_config);
  }

  @override
  Future<void> alterarPin({
    required String atual,
    required String novo,
  }) async {
    final atualConfig = _config;
    if (atualConfig == null) throw StateError('O bloqueio não está ativo.');
    if (!await verificarPin(atual, atualConfig)) {
      throw const FormatException('PIN atual incorreto.');
    }
    _config = await rehashearPin(
      atualConfig,
      novo,
      iteracoes: kIteracoesDeTeste,
    );
    state = AsyncData(_config);
  }

  @override
  Future<void> setBiometria(bool valor) async {
    final atualConfig = _config;
    if (atualConfig == null) throw StateError('O bloqueio não está ativo.');
    _config = atualConfig.copyWith(biometria: valor);
    state = AsyncData(_config);
  }

  @override
  Future<void> desativar({required String atual}) async {
    final atualConfig = _config;
    if (atualConfig == null) return;
    if (!await verificarPin(atual, atualConfig)) {
      throw const FormatException('PIN incorreto.');
    }
    _config = null;
    state = const AsyncData(null);
  }
}

/// Biometria de mentira: responde o que o teste mandar, sem plugin nenhum.
class FakeBiometrico implements AutenticadorBiometrico {
  FakeBiometrico({this.temBiometria = true, this.responde = true});

  /// O que [disponivel] responde.
  bool temBiometria;

  /// O que [autenticar] responde.
  bool responde;

  /// Quantas vezes o app pediu autenticação.
  int autenticacoes = 0;

  /// Motivos pedidos (o texto que o sistema mostraria ao usuário).
  final List<String> motivos = [];

  @override
  Future<bool> disponivel() async => temBiometria;

  @override
  Future<bool> autenticar(String motivo) async {
    autenticacoes++;
    motivos.add(motivo);
    return responde;
  }
}

/// Relógio de mentira: a trava por tentativas e a contagem regressiva da tela
/// leem o mesmo [relogioProvider], e o teste avança o tempo na mão — nada de
/// esperar de verdade (nem de depender do relógio da máquina).
class RelogioFalso {
  RelogioFalso([DateTime? inicio]) : agora = inicio ?? DateTime(2026, 1, 1, 12);

  /// Instante que o app enxerga como "agora".
  DateTime agora;

  /// Para o provedor: `relogioProvider.overrideWithValue(relogio.ler)`.
  DateTime ler() => agora;

  void avancar(Duration tempo) => agora = agora.add(tempo);
}

/// "Linha da tabela `seguranca`" em memória.
///
/// O que persiste entre montagens é este objeto — e não o notificador. Assim
/// cada `ProviderScope` cria um [FakeTentativasNotifier] novo (como o app real,
/// que relê a linha ao abrir) sem reaproveitar um `Notifier` já descartado.
class BancoTentativas {
  TentativasBloqueio estado = const TentativasBloqueio();
}

/// Trava por tentativas em memória: as regras são as reais
/// ([registrarFalhaDePin]), só a gravação no SQLite é que fica de fora — igual
/// ao que [FakeSegurancaNotifier] faz com o PIN.
class FakeTentativasNotifier extends TentativasNotifier {
  FakeTentativasNotifier([BancoTentativas? banco])
      : banco = banco ?? BancoTentativas();

  /// Onde o estado "persiste" entre montagens da tela.
  final BancoTentativas banco;

  /// Estado atual, para as asserções dos testes.
  TentativasBloqueio get tentativas => banco.estado;

  @override
  Future<TentativasBloqueio> build() async => banco.estado;

  @override
  Future<TentativasBloqueio> registrarFalha() async {
    banco.estado = registrarFalhaDePin(banco.estado, ref.read(relogioProvider)());
    state = AsyncData(banco.estado);
    return banco.estado;
  }

  @override
  Future<void> limpar() async {
    banco.estado = const TentativasBloqueio();
    state = const AsyncData(TentativasBloqueio());
  }
}

/// Escopo com o bloqueio em memória e a biometria falsa.
///
/// Devolve o [ProviderScope] inteiro (e não a lista de overrides) para não
/// depender do tipo `Override`, que o `flutter_riverpod` não exporta.
ProviderScope escopoDeSeguranca({
  required Widget child,
  SegurancaConfig? config,
  FakeSegurancaNotifier? notifier,
  FakeBiometrico? biometrico,
  FakeTentativasNotifier? tentativas,
  RelogioFalso? relogio,
}) =>
    ProviderScope(
      overrides: [
        segurancaProvider
            .overrideWith(() => notifier ?? FakeSegurancaNotifier(config)),
        autenticadorBiometricoProvider
            .overrideWithValue(biometrico ?? FakeBiometrico()),
        tentativasProvider
            .overrideWith(() => tentativas ?? FakeTentativasNotifier()),
        relogioProvider.overrideWithValue((relogio ?? RelogioFalso()).ler),
      ],
      child: child,
    );

/// App de teste no mesmo idioma por omissão do app (pt-BR).
///
/// O [locale] sozinho não basta: sem `supportedLocales` o MaterialApp
/// considera o locale pedido não suportado e cai no seu padrão (`en_US`) —
/// e as frases do app saem em inglês. Aqui o app de teste usa os mesmos
/// locales e delegates de `main.dart`, com o idioma explícito.
Widget appDeTeste(Widget home, {Locale locale = const Locale('pt', 'BR')}) =>
    MaterialApp(
      home: home,
      locale: locale,
      supportedLocales: supportedAppLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
