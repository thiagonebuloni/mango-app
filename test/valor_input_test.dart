// Máscara do campo de valor: o campo abre em "0,00" e cada dígito entra pelos
// centavos, sem o usuário digitar ponto ou vírgula (a vírgula é da máscara).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mango/screens/expense_form_screen.dart';
import 'package:mango/widgets/common.dart';

import 'fakes_seguranca.dart';

/// Aplica o formatador como o campo faria e devolve o texto resultante.
String formata(String entrada) => const CurrencyInputFormatter()
    .formatEditUpdate(
      const TextEditingValue(text: ''),
      TextEditingValue(
        text: entrada,
        selection: TextSelection.collapsed(offset: entrada.length),
      ),
    )
    .text;

void main() {
  group('formatMoneyInput', () {
    test('vírgula decimal, duas casas e sem separador de milhar', () {
      expect(formatMoneyInput(0), '0,00');
      expect(formatMoneyInput(1), '0,01');
      expect(formatMoneyInput(99), '0,99');
      expect(formatMoneyInput(100), '1,00');
      expect(formatMoneyInput(1234), '12,34');
      expect(formatMoneyInput(123456), '1234,56');
    });

    test('é o inverso de parseMoneyInput na faixa válida', () {
      for (final centavos in [1, 5, 99, 100, 1234, 99999, 1000000000000]) {
        expect(parseMoneyInput(formatMoneyInput(centavos)), centavos);
      }
    });
  });

  group('CurrencyInputFormatter', () {
    test('cada dígito entra pela direita, dos centavos para cima', () {
      expect(formata('1'), '0,01');
      expect(formata('12'), '0,12');
      expect(formata('123'), '1,23');
      expect(formata('1234'), '12,34');
      expect(formata('123456'), '1234,56');
    });

    test('descarta ponto e vírgula digitados ou colados', () {
      expect(formata('1.234,56'), '1234,56');
      expect(formata('12,34'), '12,34');
      expect(formata('1,2'), '0,12');
      expect(formata('R\$ 10,00'), '10,00');
    });

    test('campo vazio continua vazio', () {
      expect(formata(''), '');
    });

    test('valor gigante colado não estoura: trava no teto de R\$ 1 tri', () {
      expect(formata('9' * 400), formatMoneyInput(1000000000000));
    });

    test('deixa o cursor no fim do texto formatado', () {
      final resultado = const CurrencyInputFormatter().formatEditUpdate(
        const TextEditingValue(text: '0,00'),
        const TextEditingValue(text: '0,005'),
      );
      expect(resultado.text, '0,05');
      expect(resultado.selection.baseOffset, resultado.text.length);
    });
  });

  group('campo de valor na tela', () {
    setUpAll(() => initializeDateFormatting('pt_BR'));

    testWidgets('abre em 0,00 e não aceita ponto/vírgula digitados',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: appDeTeste(const ExpenseFormScreen())),
      );
      await tester.pumpAndSettle();

      final campo = find.byType(TextFormField).first;
      expect(tester.widget<TextFormField>(campo).controller!.text, '0,00');

      // Colar "1.234,56" com separadores: a máscara lê só os dígitos.
      await tester.enterText(campo, '1.234,56');
      await tester.pump();
      expect(tester.widget<TextFormField>(campo).controller!.text, '1234,56');
    });
  });
}
