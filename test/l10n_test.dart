// Idioma do app: resolução a partir do sistema, formatação por locale e a
// tradução de verdade para en-US (não só a troca de rótulos).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mango/l10n/app_locale.dart';
import 'package:mango/l10n/app_strings.dart';
import 'package:mango/l10n/l10n_format.dart';
import 'package:mango/screens/lock_screen.dart';

import 'fakes_seguranca.dart';

const en = Locale('en', 'US');
const pt = Locale('pt', 'BR');

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    await initializeDateFormatting('en_US');
  });

  group('resolveAppLocale', () {
    test('sistema em inglês abre em en-US', () {
      expect(resolveAppLocale(const Locale('en', 'US')), en);
      // Qualquer variante de inglês, não só en_US.
      expect(resolveAppLocale(const Locale('en', 'GB')), en);
      expect(resolveAppLocale(const Locale('en')), en);
    });

    test('pt-BR é o padrão; o resto também cai nele', () {
      expect(resolveAppLocale(const Locale('pt', 'BR')), pt);
      expect(resolveAppLocale(const Locale('pt', 'PT')), pt);
      expect(resolveAppLocale(const Locale('es', 'ES')), pt);
    });

    test('sem locale do sistema assume pt-BR', () {
      expect(resolveAppLocale(null), pt);
    });
  });

  group('AppStrings.of', () {
    test('escolhe a classe pelo idioma', () {
      expect(AppStrings.of(en), isA<EnUsStrings>());
      expect(AppStrings.of(pt), isA<PtBrStrings>());
      expect(AppStrings.of(null), isA<PtBrStrings>());
    });

    test('en-US responde de verdade, não cai no texto de pt-BR', () {
      final s = AppStrings.of(en);
      final p = AppStrings.of(pt);
      expect(s.appName, p.appName);
      expect(s.gastos, isNot(p.gastos));
      expect(s.relatorios, isNot(p.relatorios));
      expect(s.salvar, isNot(p.salvar));
      expect(s.cancelar, isNot(p.cancelar));
      expect(s.seguranca, 'Security');
      // Frases com parâmetro também são conferidas com os mesmos argumentos.
      expect(s.pinRegra(4, 6), isNot(p.pinRegra(4, 6)));
      expect(s.gastoExcluido, isNot(p.gastoExcluido));
    });
  });

  group('formatação por locale', () {
    test('moeda em BRL no pt-BR e em USD no en-US', () {
      expect(formatMoney(123456, pt), 'R\$\u00a01.234,56');
      expect(formatMoney(123456, en), '\$1,234.56');
    });

    test('sem locale explícito vale pt-BR', () {
      expect(formatMoney(100, null), formatMoney(100, pt));
    });

    test('datas seguem o idioma', () {
      final data = DateTime(2026, 3, 7, 14, 5);
      expect(formatDate(data, (p) => p.dayMonthYear, pt), '07/03/2026');
      expect(formatDate(data, (p) => p.dayMonthYear, en), '03/07/2026');
      expect(formatDate(data, (p) => p.monthYear, en), 'March 2026');
    });

    test('rótulos de categoria e pagamento são traduzidos', () {
      expect(AppStrings.of(pt).categoriaLabel('alimentacao'), 'Alimentação');
      expect(AppStrings.of(en).categoriaLabel('alimentacao'), 'Dining');
      expect(AppStrings.of(pt).categoriaLabel('vestuario'), 'Vestuário');
      expect(AppStrings.of(en).categoriaLabel('vestuario'), 'Clothing');
      expect(AppStrings.of(pt).pagamentoLabel('dinheiro'), 'Dinheiro');
      expect(AppStrings.of(en).pagamentoLabel('dinheiro'), isNot('Dinheiro'));
    });
  });

  group('LockScreen traduzida', () {
    testWidgets('em en-US mostra as frases em inglês', (tester) async {
      final config = await configDeTeste('1234');
      await tester.pumpWidget(escopoDeSeguranca(
        config: config,
        child: appDeTeste(LockScreen(config: config), locale: en),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Mango locked'), findsOneWidget);
      expect(find.text('I forgot my PIN'), findsOneWidget);
      expect(find.text('Mango bloqueado'), findsNothing);
      expect(find.text('Esqueci meu PIN'), findsNothing);
    });

    testWidgets('em pt-BR continua como sempre', (tester) async {
      final config = await configDeTeste('1234');
      await tester.pumpWidget(escopoDeSeguranca(
        config: config,
        child: appDeTeste(LockScreen(config: config), locale: pt),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Mango bloqueado'), findsOneWidget);
      expect(find.text('Esqueci meu PIN'), findsOneWidget);
    });
  });
}
