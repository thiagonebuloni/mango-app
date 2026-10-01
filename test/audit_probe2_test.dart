// Auditoria — parte 2: caminho de crash na UI e limites de data/valor.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mango/models/models.dart';
import 'package:mango/screens/expense_form_screen.dart';
import 'package:mango/state/providers.dart';
import 'fakes_seguranca.dart';
import 'package:mango/services/receipt_parser.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));
  group('Caminho de crash na tela do formulário', () {
    testWidgets('colar valor gigante no campo Valor quebra o build',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: appDeTeste(const ExpenseFormScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Cola ~400 dígitos (permitido pelo filtro [0-9,.] do campo).
      final field = find.byType(TextFormField).first;
      await tester.enterText(field, '9' * 400);
      await tester.pump();

      final erro = tester.takeException();
      // ignore: avoid_print
      print('exceção capturada no build: $erro');
      expect(erro, isNull,
          reason: 'valor gigante no campo não pode quebrar o build');
      // O campo continua montado e funcional após a entrada.
      expect(find.byType(ExpenseFormScreen), findsOneWidget);
    });

    testWidgets('formulário novo intocado pode sair sem confirmação',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: appDeTeste(const ExpenseFormScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final pop = tester.widget<PopScope>(find.byWidgetPredicate(
          (w) => w is PopScope));
      // ignore: avoid_print
      print('form intocado -> canPop=${pop.canPop}');
      expect(pop.canPop, isTrue,
          reason: 'form novo sem nenhuma alteração não é "sujo"');
    });

    testWidgets('mexer em qualquer campo torna o form sujo', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: appDeTeste(const ExpenseFormScreen()),
        ),
      );
      await tester.pumpAndSettle();
      bool canPop() => tester
          .widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope))
          .canPop;
      expect(canPop(), isTrue);

      // Campo Valor (onChanged já fazia setState).
      await tester.enterText(find.byType(TextFormField).first, '25,00');
      await tester.pump();
      expect(canPop(), isFalse, reason: 'valor editado = sujo');

      // Campo Descrição: era o caso em que faltava setState (regressão da B4).
      await tester.enterText(
          find.byType(TextFormField).at(2), 'Café da tarde');
      await tester.pump();
      expect(canPop(), isFalse,
          reason: 'descrição editada deve marcar o form como sujo');
    });
  });

  group('Data e hora (_pickDate)', () {
    testWidgets('cancelar o seletor de hora mantém a hora original',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: appDeTeste(const ExpenseFormScreen()),
        ),
      );
      await tester.pumpAndSettle();

      String dataExibida() => tester
          .widget<Text>(
              find.textContaining(RegExp(r'\d{2}/\d{2}/\d{4}  \d{2}:\d{2}')).first)
          .data!;
      final antes = dataExibida();

      await tester.tap(find.text('Data e hora'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);

      // Escolhe um dia do mês sempre habilitado: o seletor limita a data a
      // hoje + 1 dia, então o dia 15 fica desabilitado nos primeiros dias do
      // mês e o toque não muda nada (teste quebrava do dia 1 ao 14).
      final hoje = DateTime.now();
      final dia = hoje.day == 1 ? 2 : 1;
      await tester.tap(find.text('$dia').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);

      // Cancela a hora: a data muda, mas hora/minuto ficam como estavam.
      await tester.tap(find.text('Cancelar')); // pt-BR do app de teste
      await tester.pumpAndSettle();

      final depois = dataExibida();
      final agora = DateTime.now();
      final prefixo = '${dia.toString().padLeft(2, '0')}/'
          '${agora.month.toString().padLeft(2, '0')}/${agora.year}';
      expect(depois, startsWith(prefixo),
          reason: 'a data deve ter mudado para o dia $dia');
      expect(depois.substring(11), antes.substring(11),
          reason: 'cancelar o seletor de hora deve manter hora/minuto '
              'originais, não zerar em 12:00 (B5)');
    });
  });

  group('moneyToCentavos com valores gigantes do OCR', () {
    test('valor formatado gigante não lança: trava no teto do app', () {
      final gigante = '999${'.999' * 20},99';
      Object? erro;
      int? v;
      try {
        v = ReceiptParser.moneyToCentavos(gigante);
      } catch (e) {
        erro = e;
      }
      // ignore: avoid_print
      print('moneyToCentavos gigante -> v=$v erro=$erro');
      expect(erro, isNull,
          reason: 'moneyToCentavos não pode lançar com valor gigante do OCR');
      expect(v, ReceiptParser.maxCentavos,
          reason: 'valor fora do range deve travar no teto (R\$ 1 tri)');
    });

    test('valores normais continuam exatos e acima do teto são cortados', () {
      expect(ReceiptParser.moneyToCentavos('1.234,56'), 123456);
      expect(ReceiptParser.moneyToCentavos('0,50'), 50);
      // 20 dígitos cabe em int64 mas passa do teto do app.
      expect(ReceiptParser.moneyToCentavos('999999999999999999,99'),
          ReceiptParser.maxCentavos);
    });

    test('ReceiptParser.parse com total gigante não propaga', () {
      final gigante = '999${'.999' * 20},99';
      final text = 'LOJA X\nCNPJ 12.345.678/0001-90\n'
          'TOTAL $gigante\nPAGTO DINHEIRO';
      Object? erro;
      ReceiptDraft? draft;
      try {
        draft = ReceiptParser.parse(text);
      } catch (e) {
        erro = e;
      }
      // ignore: avoid_print
      print('parse com total gigante -> erro=$erro');
      expect(erro, isNull,
          reason: 'parse deve tolerar OCR malformado sem lançar');
      expect(draft?.totalCentavos, ReceiptParser.maxCentavos,
          reason: 'total gigante deve sair travado no teto, não lançar');
    });
  });

  group('addMonths na fronteira do DateTime', () {
    test('data próxima do máximo absoluto + 60 parcelas não lança', () {
      Object? erro;
      DateTime? r;
      try {
        // 275759-12-31 é a última data segura em qualquer fuso; +59 meses
        // ultrapassa o range e exercita o clamp do ano.
        r = addMonths(DateTime(275759, 12, 31), 59);
      } catch (e) {
        erro = e;
      }
      // ignore: avoid_print
      print('fronteira addMonths -> erro=$erro data=$r');
      expect(erro, isNull,
          reason: 'addMonths não pode estourar o range do DateTime');
      expect(r!.year, lessThanOrEqualTo(275759),
          reason: 'ano deve ficar no limite seguro construível');
    });

    test('data próxima do mínimo absoluto com meses negativos não lança', () {
      Object? erro;
      try {
        addMonths(DateTime(-271800, 6, 15), -100000);
      } catch (e) {
        erro = e;
      }
      // ignore: avoid_print
      print('fronteira inferior addMonths -> erro=$erro');
      expect(erro, isNull);
    });

    test('datas normais continuam exatas', () {
      final r = addMonths(DateTime(2026, 1, 31), 1);
      expect(r, DateTime(2026, 2, 28),
          reason: '31/01 + 1 mês deve travar no último dia de fevereiro');
      final n = addMonths(DateTime(2026, 3, 20), -14);
      expect(n, DateTime(2025, 1, 20));
      final f = addMonths(DateTime(2026, 11, 30), 3);
      expect(f, DateTime(2027, 2, 28));
    });
  });
}
