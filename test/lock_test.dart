import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mango/main.dart';
import 'package:mango/models/models.dart';
import 'package:mango/screens/lock_screen.dart';
import 'package:mango/services/seguranca.dart';
import 'package:mango/state/providers.dart';

import 'fakes_seguranca.dart';

/// Monta o [LockGate] — o caminho real de abertura do app — por cima de um
/// conteúdo de mentira, para ver quando ele aparece.
///
/// A janela de corrida vem zerada: o teste quer ver a re-tranca na hora, e
/// quem cobre a janela é o teste específico dela.
///
/// [assentar] desliga o `pumpAndSettle` do fim: com a espera por tentativas já
/// ligada existe um cronômetro de 1 s rodando, e "settle" nunca chegaria (o
/// relógio do teste só anda quando o teste manda).
Future<void> _montarGate(
  WidgetTester tester, {
  required SegurancaConfig? config,
  FakeBiometrico? biometrico,
  FakeTentativasNotifier? tentativas,
  RelogioFalso? relogio,
  Duration janelaCorrida = Duration.zero,
  bool assentar = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bloqueioProvider.overrideWith(
          () => BloqueioNotifier(janelaCorrida: janelaCorrida),
        ),
      ],
      child: escopoDeSeguranca(
        config: config,
        biometrico: biometrico,
        tentativas: tentativas,
        relogio: relogio,
        child: appDeTeste(
          const LockGate(child: Scaffold(body: Text('conteúdo do app'))),
        ),
      ),
    ),
  );
  if (assentar) {
    await tester.pumpAndSettle();
  } else {
    await _assentar(tester);
  }
}

/// Toca os dígitos de [pin] no teclado da tela de bloqueio e deixa a
/// verificação (PBKDF2) terminar.
Future<void> _digitar(WidgetTester tester, String pin) async {
  for (final digito in pin.split('')) {
    await tester.tap(find.text(digito));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Digita um PIN sem `pumpAndSettle` — para os casos em que a espera por
/// tentativas (ou o acerto, que a zera) pode estar com o cronômetro rodando.
Future<void> _errar(WidgetTester tester, String pin) async {
  for (final digito in pin.split('')) {
    await tester.tap(find.text(digito));
    await tester.pump();
  }
  await _assentar(tester);
}

/// Deixa as futures pendentes (PBKDF2, carga do provedor) concluírem sem
/// depender de "settle": `elapse` de 1 ms não chega a disparar o cronômetro.
Future<void> _assentar(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

/// Avança o relógio da trava **e** o do teste juntos: a contagem regressiva é
/// desenhada a partir do [RelogioFalso], então andar só um dos dois deixaria a
/// tela travada para sempre.
Future<void> _passarTempo(
  WidgetTester tester,
  RelogioFalso relogio,
  Duration tempo,
) async {
  relogio.avancar(tempo);
  await tester.pump(tempo);
  await tester.pump();
}

/// Derruba a árvore — e, com ela, o cronômetro da contagem regressiva. Sem
/// isso, um teste que termina durante a espera deixaria um `Timer` pendente,
/// o que o `flutter_test` reprova.
Future<void> _fecharApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  group('LockGate', () {
    testWidgets('sem PIN configurado, o app abre direto', (tester) async {
      await _montarGate(tester, config: null);

      expect(find.text('conteúdo do app'), findsOneWidget);
      expect(find.byType(LockScreen), findsNothing);
    });

    testWidgets('com PIN configurado, o conteúdo fica escondido',
        (tester) async {
      await _montarGate(tester, config: await configDeTeste('1234'));

      expect(find.byType(LockScreen), findsOneWidget);
      // O conteúdo nem é montado: nada vaza na tela nem no app recentes.
      expect(find.text('conteúdo do app'), findsNothing);
    });

    testWidgets('PIN certo revela o app', (tester) async {
      await _montarGate(tester, config: await configDeTeste('1234'));

      await _digitar(tester, '1234');

      expect(find.text('conteúdo do app'), findsOneWidget);
      expect(find.byType(LockScreen), findsNothing);
    });

    testWidgets('PIN errado avisa e mantém travado; o certo ainda entra',
        (tester) async {
      await _montarGate(tester, config: await configDeTeste('1234'));

      await _digitar(tester, '9999');

      expect(find.text('PIN incorreto'), findsOneWidget);
      expect(find.text('conteúdo do app'), findsNothing);

      await _digitar(tester, '1234');

      expect(find.text('conteúdo do app'), findsOneWidget);
    });

    testWidgets('biometria ligada tenta sozinha e destrava', (tester) async {
      final bio = FakeBiometrico();
      await _montarGate(
        tester,
        config: await configDeTeste('1234', biometria: true),
        biometrico: bio,
      );

      expect(bio.autenticacoes, 1);
      expect(bio.motivos.single, 'Desbloquear o Mango');
      expect(find.text('conteúdo do app'), findsOneWidget);
    });

    testWidgets('biometria cancelada continua no PIN', (tester) async {
      final bio = FakeBiometrico(responde: false);
      await _montarGate(
        tester,
        config: await configDeTeste('1234', biometria: true),
        biometrico: bio,
      );

      expect(find.byType(LockScreen), findsOneWidget);
      // Cancelar não é erro: nenhuma mensagem vermelha aparece.
      expect(find.text('PIN incorreto'), findsNothing);

      await _digitar(tester, '1234');

      expect(find.text('conteúdo do app'), findsOneWidget);
    });

    testWidgets('biometria desligada não chama o autenticador',
        (tester) async {
      final bio = FakeBiometrico();
      await _montarGate(
        tester,
        config: await configDeTeste('1234'),
        biometrico: bio,
      );

      expect(bio.autenticacoes, 0);
      expect(find.byIcon(Icons.fingerprint), findsNothing);
    });
    testWidgets('volta do segundo plano re-tranca o app', (tester) async {
      await _montarGate(tester, config: await configDeTeste('1234'));
      await _digitar(tester, '1234');
      expect(find.text('conteúdo do app'), findsOneWidget);

      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('conteúdo do app'), findsNothing);
    });

    testWidgets('resumed logo depois de destravar não re-tranca',
        (tester) async {
      // A janela de corrida existe justamente para isso: algumas OEMs
      // entregam o `resumed` por conta do sucesso da biometria.
      await _montarGate(
        tester,
        config: await configDeTeste('1234'),
        janelaCorrida: const Duration(seconds: 3),
      );
      await _digitar(tester, '1234');

      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('conteúdo do app'), findsOneWidget);
      expect(find.byType(LockScreen), findsNothing);
    });

    testWidgets('sem bloqueio, voltar do fundo não trava nada',
        (tester) async {
      await _montarGate(tester, config: null);

      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('conteúdo do app'), findsOneWidget);
    });

    testWidgets('falha ao ler a segurança avisa em vez de abrir o app',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          // Sem retry: o erro aqui é para ficar visível e parado.
          retry: (_, __) => null,
          overrides: [
            segurancaProvider.overrideWith(() => _ErroSegurancaNotifier()),
            autenticadorBiometricoProvider.overrideWithValue(FakeBiometrico()),
          ],
          child: appDeTeste(
            const LockGate(child: Scaffold(body: Text('conteúdo do app'))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Erro ao carregar a segurança'),
        findsOneWidget,
      );
      // Na dúvida, não abre: o conteúdo continua fora de alcance.
      expect(find.text('conteúdo do app'), findsNothing);
    });
  });

  group('LockScreen (teclado)', () {
    testWidgets('só valida quando completa o PIN', (tester) async {
      await _montarTela(tester, await configDeTeste('1234'));

      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();

      expect(find.text('travado'), findsOneWidget);
      expect(find.text('PIN incorreto'), findsNothing);

      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();

      expect(find.text('livre'), findsOneWidget);
    });

    testWidgets('apagar volta um dígito por toque', (tester) async {
      await _montarTela(tester, await configDeTeste('1234'));

      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('9')); // vai ser apagado
      await tester.pump();
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();

      expect(find.text('livre'), findsOneWidget);
    });

    testWidgets('apagar com o campo vazio não quebra', (tester) async {
      await _montarTela(tester, await configDeTeste('1234'));

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pumpAndSettle();

      expect(find.text('travado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mostra um slot por dígito do PIN', (tester) async {
      await _montarTela(tester, await configDeTeste('1234'));

      expect(find.byKey(const ValueKey('slot-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('slot-4')), findsNothing);

      await _montarTela(tester, await configDeTeste('123456'));

      expect(find.byKey(const ValueKey('slot-5')), findsOneWidget);
      expect(find.byKey(const ValueKey('slot-6')), findsNothing);
    });

    testWidgets('PIN de 6 dígitos só valida no sexto', (tester) async {
      await _montarTela(tester, await configDeTeste('123456'));

      for (final digito in ['1', '2', '3', '4', '5']) {
        await tester.tap(find.text(digito));
        await tester.pump();
      }
      expect(find.text('travado'), findsOneWidget);

      await tester.tap(find.text('6'));
      await tester.pumpAndSettle();

      expect(find.text('livre'), findsOneWidget);
    });

    testWidgets('"Esqueci meu PIN" explica que não há recuperação',
        (tester) async {
      await _montarTela(tester, await configDeTeste('1234'));

      await tester.tap(find.text('Esqueci meu PIN'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('não existe e-mail nem servidor'),
        findsOneWidget,
      );

      await tester.tap(find.text('Entendi'));
      await tester.pumpAndSettle();

      expect(find.text('Entendi'), findsNothing);
      expect(find.text('travado'), findsOneWidget);
    });
    testWidgets('botão de biometria destrava quando o aparelho responde',
        (tester) async {
      final bio = FakeBiometrico(responde: false);
      await _montarTela(
        tester,
        await configDeTeste('1234', biometria: true),
        biometrico: bio,
      );

      // A tentativa automática do primeiro frame foi cancelada.
      expect(find.text('travado'), findsOneWidget);
      expect(bio.autenticacoes, 1);

      bio.responde = true;
      await tester.tap(find.byIcon(Icons.fingerprint));
      await tester.pumpAndSettle();

      expect(find.text('livre'), findsOneWidget);
      expect(bio.autenticacoes, 2);
    });
  });

  group('Trava por tentativas', () {
    /// Digita [vezes] PINs errados seguidos.
    Future<void> errar(WidgetTester tester, int vezes) async {
      for (var i = 0; i < vezes; i++) {
        await _errar(tester, '9999');
      }
    }

    testWidgets('a última tentativa livre liga a espera e trava as teclas',
        (tester) async {
      final relogio = RelogioFalso();
      final bio = FakeBiometrico(responde: false);
      await _montarGate(
        tester,
        config: await configDeTeste('1234', biometria: true),
        biometrico: bio,
        relogio: relogio,
      );
      expect(bio.autenticacoes, 1); // a oferta automática não passou

      await errar(tester, kTentativasLivres - 1);
      // Ainda dentro das tentativas livres: só o aviso de PIN incorreto.
      expect(find.text('PIN incorreto'), findsOneWidget);
      expect(find.textContaining('Muitas tentativas'), findsNothing);

      await errar(tester, 1);

      expect(find.textContaining('Tente de novo em 30 s'), findsOneWidget);
      expect(find.text('PIN incorreto'), findsNothing);
      expect(find.text('conteúdo do app'), findsNothing);

      // Teclado travado: nem o PIN certo passa.
      await _errar(tester, '1234');
      expect(find.text('conteúdo do app'), findsNothing);

      // A biometria também fica fora de alcance — e o fake responderia "sim".
      bio.responde = true;
      await tester.tap(find.byIcon(Icons.fingerprint));
      await _assentar(tester);
      expect(bio.autenticacoes, 1);
      expect(find.text('conteúdo do app'), findsNothing);

      await _fecharApp(tester); // o cronômetro da espera para aqui
    });

    testWidgets('a espera cai com o tempo e libera o teclado', (tester) async {
      final relogio = RelogioFalso();
      await _montarGate(
        tester,
        config: await configDeTeste('1234'),
        relogio: relogio,
      );

      await errar(tester, kTentativasLivres);
      expect(find.textContaining('Tente de novo em 30 s'), findsOneWidget);

      await _passarTempo(tester, relogio, const Duration(seconds: 10));
      expect(find.textContaining('Tente de novo em 20 s'), findsOneWidget);

      await _passarTempo(tester, relogio, const Duration(seconds: 20));
      expect(find.textContaining('Muitas tentativas'), findsNothing);

      await _digitar(tester, '1234');

      expect(find.text('conteúdo do app'), findsOneWidget);
    });

    testWidgets('cada erro depois da espera dobra o tempo', (tester) async {
      final relogio = RelogioFalso();
      await _montarGate(
        tester,
        config: await configDeTeste('1234'),
        relogio: relogio,
      );

      await errar(tester, kTentativasLivres);
      expect(find.textContaining('Tente de novo em 30 s'), findsOneWidget);

      // Passa a espera inteira e erra de novo: agora são 60 s (1 min).
      await _passarTempo(tester, relogio, const Duration(seconds: 30));
      await errar(tester, 1);

      expect(find.textContaining('Tente de novo em 1 min'), findsOneWidget);

      // Mais um erro depois da espera inteira: 2 min — e, no meio dela,
      // a contagem aparece em minutos e segundos.
      await _passarTempo(tester, relogio, const Duration(seconds: 60));
      await errar(tester, 1);

      expect(find.textContaining('Tente de novo em 2 min'), findsOneWidget);

      await _passarTempo(tester, relogio, const Duration(seconds: 30));

      expect(
        find.textContaining('Tente de novo em 1 min 30 s'),
        findsOneWidget,
      );

      await _fecharApp(tester);
    });

    testWidgets('o PIN certo zera a contagem de erros', (tester) async {
      final fake = FakeTentativasNotifier();
      await _montarTela(
        tester,
        await configDeTeste('1234'),
        tentativas: fake,
      );

      await errar(tester, kTentativasLivres - 1);
      expect(fake.tentativas.falhas, kTentativasLivres - 1);

      await _digitar(tester, '1234');

      expect(fake.tentativas.falhas, 0);
      expect(fake.tentativas.bloqueadoAte, isNull);
    });

    testWidgets('a espera sobrevive a fechar e reabrir o app', (tester) async {
      final banco = BancoTentativas();
      final relogio = RelogioFalso();
      final config = await configDeTeste('1234');

      await _montarTela(
        tester,
        config,
        tentativas: FakeTentativasNotifier(banco),
        relogio: relogio,
      );
      await errar(tester, kTentativasLivres);
      expect(find.textContaining('Tente de novo em 30 s'), findsOneWidget);

      // "Fechar e abrir": a linha do banco é a mesma e a tela é nova (outro
      // notificador, como no app real). Matar o processo não foge da espera.
      await _fecharApp(tester);
      await _montarTela(
        tester,
        config,
        tentativas: FakeTentativasNotifier(banco),
        relogio: relogio,
        assentar: false,
      );

      expect(find.textContaining('Tente de novo em 30 s'), findsOneWidget);

      await _fecharApp(tester);
    });
  });

  group('BloqueioNotifier', () {
    test('nasce travado e destrava sob demanda', () {
      final container = ProviderContainer.test(
        overrides: [
          bloqueioProvider.overrideWith(
            () => BloqueioNotifier(janelaCorrida: Duration.zero),
          ),
        ],
      );

      expect(container.read(bloqueioProvider), isTrue);

      container.read(bloqueioProvider.notifier).destravar();

      expect(container.read(bloqueioProvider), isFalse);
    });

    test('reaoVoltar tranca quando o bloqueio está ativo', () async {
      final config = await configDeTeste('1234');
      final container = ProviderContainer.test(
        overrides: [
          bloqueioProvider.overrideWith(
            () => BloqueioNotifier(janelaCorrida: Duration.zero),
          ),
        ],
      );

      container.read(bloqueioProvider.notifier)
        ..destravar()
        ..reaoVoltar(config);

      expect(container.read(bloqueioProvider), isTrue);
    });

    test('reaoVoltar não tranca sem bloqueio configurado', () {
      final container = ProviderContainer.test(
        overrides: [
          bloqueioProvider.overrideWith(
            () => BloqueioNotifier(janelaCorrida: Duration.zero),
          ),
        ],
      );

      container.read(bloqueioProvider.notifier)
        ..destravar()
        ..reaoVoltar(null);

      expect(container.read(bloqueioProvider), isFalse);
    });

    test('volta logo depois de destravar é ignorada (janela de corrida)', () {
      final container = ProviderContainer.test();
      final notifier = container.read(bloqueioProvider.notifier);

      notifier.destravar();
      notifier.reaoVoltar(
        const SegurancaConfig(
          pinHash: 'x',
          pinSalt: 'y',
          pinIteracoes: 1,
          pinTamanho: 4,
        ),
      );

      expect(container.read(bloqueioProvider), isFalse);
      expect(notifier.janelaCorrida, const Duration(seconds: 3));
    });
  });
}

/// Monta a [LockScreen] sozinha (sem o [LockGate]) com o estado da tranca
/// visível embaixo, para conferir o teclado de perto.
///
/// [assentar] vale o mesmo do [_montarGate]: com a espera ligada, o
/// `pumpAndSettle` não teria fim.
Future<void> _montarTela(
  WidgetTester tester,
  SegurancaConfig config, {
  FakeBiometrico? biometrico,
  FakeTentativasNotifier? tentativas,
  RelogioFalso? relogio,
  bool assentar = true,
}) async {
  await tester.pumpWidget(
    escopoDeSeguranca(
      config: config,
      biometrico: biometrico,
      tentativas: tentativas,
      relogio: relogio,
      child: appDeTeste(_EstadoDaTranca(child: LockScreen(config: config))),
    ),
  );
  if (assentar) {
    await tester.pumpAndSettle();
  } else {
    await _assentar(tester);
  }
}

/// Mostra "travado"/"livre" embaixo da tela: é como os testes leem o estado
/// da tranca sem depender de detalhe interno do Riverpod.
class _EstadoDaTranca extends StatelessWidget {
  const _EstadoDaTranca({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(child: child),
          Consumer(
            builder: (_, ref, __) => Text(
              ref.watch(bloqueioProvider) ? 'travado' : 'livre',
            ),
          ),
        ],
      );
}

/// Segurança que falha ao carregar (banco fora do ar, por exemplo).
class _ErroSegurancaNotifier extends SegurancaNotifier {
  @override
  Future<SegurancaConfig?> build() async =>
      throw StateError('banco fora do ar');
}
