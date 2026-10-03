// Cartões de crédito: modelo, datas de lembrete, filtro de fatura por mês e
// as telas de lista/detalhe.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:mango/db/db.dart';
import 'package:mango/l10n/app_locale.dart';
import 'package:mango/l10n/app_strings.dart';
import 'package:mango/models/models.dart';
import 'package:mango/screens/cartao_detalhe_screen.dart';
import 'package:mango/screens/cartoes_screen.dart';
import 'package:mango/services/notificacoes.dart';
import 'package:mango/state/providers.dart';
import 'package:mango/widgets/cartao_visual.dart';

const _cartao = CartaoCredito(
  id: 1,
  banco: 'Nubank',
  bandeira: BandeiraCartao.mastercard,
  nome: 'Viagem',
  diaFechamento: 20,
  diaPagamento: 27,
);

Expense _gasto({
  required int centavos,
  required DateTime data,
  int? cartaoId,
  PaymentMethod forma = PaymentMethod.credito,
  Category categoria = Category.mercado,
}) {
  return Expense(
    valorCentavos: centavos,
    dataHora: data,
    categoria: categoria,
    forma: forma,
    cartaoId: cartaoId,
    estabelecimento: 'LOJA TESTE',
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    await initializeDateFormatting('en_US');
  });

  group('proximoLembrete', () {
    test('dia ainda futuro no mês atual', () {
      expect(
        proximoLembrete(15, DateTime(2026, 6, 10, 8)),
        DateTime(2026, 6, 15, horaLembreteCartao),
      );
    });

    test('dia de hoje já passou das 9h → próximo mês', () {
      expect(
        proximoLembrete(15, DateTime(2026, 6, 15, 10)),
        DateTime(2026, 7, 15, horaLembreteCartao),
      );
    });

    test('31 em fevereiro vira 28 (ou 29 em bissexto)', () {
      expect(
        proximoLembrete(31, DateTime(2026, 1, 31, 10)),
        DateTime(2026, 2, 28, horaLembreteCartao),
      );
      expect(
        proximoLembrete(31, DateTime(2024, 2, 1)),
        DateTime(2024, 2, 29, horaLembreteCartao),
      );
    });

    test('vira o ano', () {
      expect(
        proximoLembrete(1, DateTime(2026, 12, 31, 23)),
        DateTime(2027, 1, 1, horaLembreteCartao),
      );
    });
  });

  group('CartaoCredito', () {
    test('toMap → fromMap preserva todos os campos', () {
      final volta = CartaoCredito.fromMap(_cartao.toMap());
      expect(volta.banco, 'Nubank');
      expect(volta.bandeira, BandeiraCartao.mastercard);
      expect(volta.nome, 'Viagem');
      expect(volta.diaFechamento, 20);
      expect(volta.diaPagamento, 27);
      expect(volta.id, 1);
    });

    test('bandeira desconhecida cai em outras', () {
      expect(BandeiraCartaoX.fromName('qualquer'), BandeiraCartao.outras);
      expect(BandeiraCartaoX.fromName(null), BandeiraCartao.outras);
    });
  });

  group('Expense.cartaoId', () {
    test('sobrevive a toMap/fromMap e ao copyWith (inclusive limpar)', () {
      final e = _gasto(centavos: 100, data: DateTime(2026, 6, 10), cartaoId: 7);
      expect(Expense.fromMap(e.toMap()).cartaoId, 7);
      expect(e.copyWith(estabelecimento: 'X').cartaoId, 7);
      expect(e.copyWith(cartaoId: null).cartaoId, isNull);
    });

    test('linha antiga sem a coluna carrega com cartaoId nulo', () {
      final map = _gasto(centavos: 100, data: DateTime(2026, 6, 10)).toMap()
        ..remove('cartao_id');
      expect(Expense.fromMap(map).cartaoId, isNull);
    });
  });

  group('gastosDoCartao', () {
    final base = DateTime(2026, 6, 10, 12);

    test('só o cartão, o mês e as despesas certos', () {
      final gastos = [
        _gasto(centavos: 500, data: base, cartaoId: 1),
        _gasto(centavos: 300, data: DateTime(2026, 6, 25), cartaoId: 1),
        // Outro cartão, outro mês, sem cartão, outra forma e receita ficam
        // de fora.
        _gasto(centavos: 999, data: base, cartaoId: 2),
        _gasto(centavos: 999, data: DateTime(2026, 5, 31), cartaoId: 1),
        _gasto(centavos: 999, data: base, cartaoId: null),
        _gasto(
          centavos: 999,
          data: base,
          cartaoId: 1,
          forma: PaymentMethod.pix,
        ),
        Expense(
          tipo: EntryKind.receita,
          valorCentavos: 999,
          dataHora: base,
          categoria: Category.salario,
          forma: PaymentMethod.pix,
          cartaoId: 1,
        ),
      ];
      final doCartao = gastosDoCartao(gastos, 1, base);
      expect(doCartao.length, 2);
      expect(totalOf(doCartao), 800);
    });
  });

  group('cores do cartão', () {
    test('banco conhecido tem a cor da marca', () {
      expect(corDoBanco('Nubank'), const Color(0xFF820AD1));
      expect(corDoBanco('Banco do Brasil'), const Color(0xFF003399));
    });

    test('nome livre é estável (mesmo nome, mesma cor)', () {
      final a = corDoBanco('Banco Xpto');
      final b = corDoBanco('Banco Xpto');
      expect(a, b);
    });

    test('normalização ignora caixa e acentos', () {
      expect(normalizarBanco('Itaú'), 'itau');
      expect(normalizarBanco('Banco Itaú S.A.'), 'bancoitausa');
    });
  });

  group('frases de cartão', () {
    test('traduzidas de verdade em en-US', () {
      const en = Locale('en', 'US');
      const pt = Locale('pt', 'BR');
      expect(AppStrings.of(en).cartoes, 'Cards');
      expect(AppStrings.of(pt).cartoes, 'Cartões');
      expect(
        AppStrings.of(en).totalFatura,
        isNot(AppStrings.of(pt).totalFatura),
      );
      expect(AppStrings.of(en).bandeiraLabel('outras'), 'Other');
    });
  });

  group('backup CSV com cartões', () {
    test('export → import mantém cartão e vínculo pelo nome', () {
      final csv = CsvBackup.export(
        [_gasto(centavos: 1234, data: DateTime(2026, 3, 10), cartaoId: 1)],
        cartoes: const [_cartao],
        nomesCartoes: const {1: 'Viagem'},
      );
      expect(csv, contains(CsvBackup.cartaoMarker));
      expect(csv, contains(CsvBackup.header));

      final r = CsvBackup.import(csv);
      expect(r.cartoes, hasLength(1));
      expect(r.cartoes.first.banco, 'Nubank');
      expect(r.cartoes.first.bandeira, BandeiraCartao.mastercard);
      expect(r.cartoes.first.nome, 'Viagem');
      expect(r.cartoes.first.diaFechamento, 20);
      expect(r.cartoes.first.diaPagamento, 27);
      // O id nasce null: os ids são locais de cada aparelho.
      expect(r.cartoes.first.id, isNull);
      expect(r.expenses.single.cartaoId, isNull);
      // O gasto aponta o cartão pelo nome, na mesma ordem da lista.
      expect(r.vinculosCartao, ['Viagem']);
      expect(r.cartaoPorNome.keys, ['Viagem']);
    });

    test('linha de cartão inválida é ignorada sem derrubar o import', () {
      final csv = '# CARTAO;banco=;bandeira=visa;nome=X;fechamento=40;'
          'pagamento=0\n${CsvBackup.header}';
      final r = CsvBackup.import(csv);
      expect(r.cartoes, isEmpty);
      expect(r.expenses, isEmpty);
      expect(r.skipped, 0);
    });

    test('religarCartoes casa por nome em minúsculas, posicional', () {
      final gastos = [
        _gasto(centavos: 100, data: DateTime(2026, 3, 10)),
        _gasto(centavos: 200, data: DateTime(2026, 3, 11)),
        _gasto(centavos: 300, data: DateTime(2026, 3, 12)),
      ];
      final religados = religarCartoes(
        gastos,
        [' VIAGEM ', '', 'Apagado'],
        const {'viagem': 7},
      );
      expect(religados[0].cartaoId, 7);
      // Sem nome e nome fora do mapa ficam desvinculados.
      expect(religados[1].cartaoId, isNull);
      expect(religados[2].cartaoId, isNull);
      // A lista de entrada não muda.
      expect(gastos[0].cartaoId, isNull);
    });

    test('sem coluna cartão (backup v2) a lista original volta igual', () {
      final gastos = [_gasto(centavos: 100, data: DateTime(2026, 3, 10))];
      final religados = religarCartoes(gastos, const [], const {'viagem': 7});
      expect(religados, same(gastos));
    });
  });

  group('telas de cartão', () {
    testWidgets('arte do cartão tem a proporção 85,6 × 53,98 mm (≈ 1,58:1)', (
      tester,
    ) async {
      // Coluna como nas telas: largura definida, altura livre — é a altura
      // que sai da proporção (não há altura fixa em pixels).
      await tester.pumpWidget(
        _app(const Column(children: [CartaoVisual(cartao: _cartao)])),
      );
      await tester.pumpAndSettle();

      final tamanho = tester.getSize(find.byType(CartaoVisual));
      expect(
        tamanho.width / tamanho.height,
        moreOrLessEquals(razaoCartao, epsilon: 0.001),
      );
      expect(
        tamanho.width / tamanho.height,
        moreOrLessEquals(1.58, epsilon: 0.01),
      );
    });

    testWidgets('na lista, a arte ocupa a largura com a mesma proporção', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const CartoesScreen(), cartoes: const [_cartao]),
      );
      await tester.pumpAndSettle();

      final arte = tester.getSize(find.byType(CartaoVisual));
      expect(
        arte.width / arte.height,
        moreOrLessEquals(85.6 / 53.98, epsilon: 0.001),
      );
    });

    testWidgets('sem cartões: estado vazio e botão de adicionar', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const CartoesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Cartões'), findsOneWidget);
      expect(find.text('Nenhum cartão cadastrado'), findsOneWidget);
      expect(find.text('Adicionar cartão'), findsOneWidget);
    });

    testWidgets('com cartão: mostra arte, total e abre o detalhe', (
      tester,
    ) async {
      final agora = DateTime.now();
      await tester.pumpWidget(
        _app(
          const CartoesScreen(),
          cartoes: const [_cartao],
          gastos: [
            _gasto(
              centavos: 123456,
              data: DateTime(agora.year, agora.month, 10, 12),
              cartaoId: 1,
              categoria: Category.lazer,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nubank'), findsOneWidget);
      expect(find.text('Viagem'), findsOneWidget);
      expect(find.text('Total da fatura'), findsOneWidget);
      expect(find.textContaining('1.234,56'), findsOneWidget);

      await tester.tap(find.text('Viagem'));
      await tester.pumpAndSettle();

      expect(find.byType(CartaoDetalheScreen), findsOneWidget);
      // Detalhe reusa os cartões dos relatórios: categoria e dia.
      expect(find.text('Lazer'), findsWidgets);
      expect(find.textContaining('1.234,56'), findsWidgets);
    });
  });
}

// ---------------- montagem das telas nos testes ----------------

class _FakeCartoesNotifier extends CartoesNotifier {
  _FakeCartoesNotifier([this._cartoes = const []]);

  final List<CartaoCredito> _cartoes;

  @override
  Future<List<CartaoCredito>> build() async => _cartoes;
}

class _FakeReportsNotifier extends ExpensesForReports {
  _FakeReportsNotifier([this._gastos = const []]);

  final List<Expense> _gastos;

  @override
  Future<List<Expense>> build() async => _gastos;
}

class _FakeProfileNotifier extends ProfileNotifier {
  @override
  Future<UserProfile?> build() async =>
      const UserProfile(nome: 'Ana', avatar: '🦊', corFundo: 0xFFE3F2FD);
}

Widget _app(
  Widget home, {
  List<CartaoCredito> cartoes = const [],
  List<Expense> gastos = const [],
}) =>
    ProviderScope(
      overrides: [
        cartoesProvider.overrideWith(() => _FakeCartoesNotifier(cartoes)),
        expensesForReportsProvider
            .overrideWith(() => _FakeReportsNotifier(gastos)),
        profileProvider.overrideWith(() => _FakeProfileNotifier()),
      ],
      child: MaterialApp(
        home: home,
        locale: const Locale('pt', 'BR'),
        supportedLocales: supportedAppLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
