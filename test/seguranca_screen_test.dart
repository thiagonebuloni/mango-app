import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mango/models/models.dart';
import 'package:mango/screens/seguranca_screen.dart';

import 'fakes_seguranca.dart';

/// Monta a tela de Segurança com o bloqueio em memória.
Future<FakeSegurancaNotifier> _montarTela(
  WidgetTester tester, {
  SegurancaConfig? config,
  FakeBiometrico? biometrico,
}) async {
  final notifier = FakeSegurancaNotifier(config);
  await tester.pumpWidget(
    escopoDeSeguranca(
      notifier: notifier,
      biometrico: biometrico,
      child: appDeTeste(const SegurancaScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

/// Preenche os campos do diálogo de PIN, na ordem mostrada.
Future<void> _preencher(WidgetTester tester, List<String> valores) async {
  for (var i = 0; i < valores.length; i++) {
    await tester.enterText(find.byType(TextFormField).at(i), valores[i]);
  }
  await tester.pump();
}

Future<void> _tocarEm(WidgetTester tester, String texto) async {
  await tester.tap(find.text(texto));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sem PIN: explica o bloqueio e oferece criar', (tester) async {
    await _montarTela(tester);

    expect(find.text('O bloqueio do app está desativado'), findsOneWidget);
    expect(find.text('Criar PIN'), findsOneWidget);
    expect(find.text('PIN ativo'), findsNothing);
  });

  testWidgets('criar PIN ativa o bloqueio', (tester) async {
    final notifier = await _montarTela(
      tester,
      // Sem biometria cadastrada: o fluxo termina no PIN.
      biometrico: FakeBiometrico(temBiometria: false),
    );

    await _tocarEm(tester, 'Criar PIN');
    await _preencher(tester, ['1234', '1234']);
    await _tocarEm(tester, 'Criar');

    expect(notifier.config?.pinTamanho, 4);
    expect(find.text('Bloqueio ativado.'), findsOneWidget);
    expect(find.text('PIN ativo'), findsOneWidget);
    expect(find.text('4 dígitos'), findsOneWidget);
  });

  testWidgets('depois de criar, oferece a biometria quando o aparelho tem',
      (tester) async {
    final notifier = await _montarTela(tester);

    await _tocarEm(tester, 'Criar PIN');
    await _preencher(tester, ['1234', '1234']);
    await _tocarEm(tester, 'Criar');

    expect(find.text('Usar biometria?'), findsOneWidget);

    await _tocarEm(tester, 'Agora não');
    expect(notifier.config?.biometria, isFalse);
    expect(find.text('Usar biometria?'), findsNothing);
  });

  testWidgets('confirmar biometria grava a preferência', (tester) async {
    final notifier = await _montarTela(tester);

    await _tocarEm(tester, 'Criar PIN');
    await _preencher(tester, ['1234', '1234']);
    await _tocarEm(tester, 'Criar');
    await _tocarEm(tester, 'Ativar');

    expect(notifier.config?.biometria, isTrue);
    // A mensagem do PIN ainda está na tela; esta entra depois dela.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Biometria ativada.'), findsOneWidget);
  });
  testWidgets('PIN curto não passa no diálogo', (tester) async {
    final notifier = await _montarTela(tester);

    await _tocarEm(tester, 'Criar PIN');
    await _preencher(tester, ['123', '123']);
    await _tocarEm(tester, 'Criar');

    // Os dois campos reclamam do mesmo PIN curto.
    expect(find.text('Use de 4 a 6 dígitos.'), findsNWidgets(2));
    expect(notifier.config, isNull);
  });

  testWidgets('PINs diferentes não passam no diálogo', (tester) async {
    final notifier = await _montarTela(tester);

    await _tocarEm(tester, 'Criar PIN');
    await _preencher(tester, ['1234', '9999']);
    await _tocarEm(tester, 'Criar');

    expect(find.text('Os PINs não conferem.'), findsOneWidget);
    expect(notifier.config, isNull);
  });

  testWidgets('PIN atual errado mantém o diálogo aberto', (tester) async {
    final config = await configDeTeste('1234');
    final notifier = await _montarTela(tester, config: config);

    await _tocarEm(tester, 'Alterar PIN');
    await _preencher(tester, ['9999', '5678', '5678']);
    await _tocarEm(tester, 'Alterar');

    expect(find.text('PIN atual incorreto.'), findsOneWidget);
    expect(notifier.config?.pinHash, config.pinHash);
  });

  testWidgets('alterar PIN com o atual certo', (tester) async {
    final notifier = await _montarTela(
      tester,
      config: await configDeTeste('1234'),
    );

    await _tocarEm(tester, 'Alterar PIN');
    await _preencher(tester, ['1234', '5678', '5678']);
    await _tocarEm(tester, 'Alterar');

    expect(find.text('PIN alterado.'), findsOneWidget);
    expect(notifier.config?.pinTamanho, 4);
    expect(find.text('4 dígitos'), findsOneWidget);
  });

  testWidgets('desativar bloqueio com o PIN certo', (tester) async {
    final notifier = await _montarTela(
      tester,
      config: await configDeTeste('1234'),
    );

    await _tocarEm(tester, 'Desativar bloqueio');
    await _preencher(tester, ['1234']);
    await _tocarEm(tester, 'Desativar');

    expect(notifier.config, isNull);
    expect(find.text('Bloqueio desativado.'), findsOneWidget);
    expect(find.text('O bloqueio do app está desativado'), findsOneWidget);
  });

  testWidgets('desativar exige o PIN certo', (tester) async {
    final notifier = await _montarTela(
      tester,
      config: await configDeTeste('1234'),
    );

    await _tocarEm(tester, 'Desativar bloqueio');
    await _preencher(tester, ['0000']);
    await _tocarEm(tester, 'Desativar');

    expect(find.text('PIN incorreto.'), findsOneWidget);
    expect(notifier.config, isNotNull);

    await _tocarEm(tester, 'Cancelar');

    expect(find.text('Desativar bloqueio'), findsOneWidget);
    expect(notifier.config, isNotNull);
  });

  testWidgets('cancelar não muda nada', (tester) async {
    final config = await configDeTeste('1234');
    final notifier = await _montarTela(tester, config: config);

    await _tocarEm(tester, 'Alterar PIN');
    await _tocarEm(tester, 'Cancelar');

    expect(find.byType(TextFormField), findsNothing);
    expect(notifier.config?.pinHash, config.pinHash);
  });

  testWidgets('sem biometria cadastrada, o switch fica desabilitado',
      (tester) async {
    await _montarTela(
      tester,
      config: await configDeTeste('1234'),
      biometrico: FakeBiometrico(temBiometria: false),
    );

    expect(find.text('Este aparelho não tem biometria cadastrada'),
        findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
  });

  testWidgets('ligar e desligar a biometria', (tester) async {
    final notifier = await _montarTela(
      tester,
      config: await configDeTeste('1234'),
    );

    expect(
      find.text('Digital/rosto do aparelho, com o PIN como reserva'),
      findsOneWidget,
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(notifier.config?.biometria, isTrue);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(notifier.config?.biometria, isFalse);
  });
}
