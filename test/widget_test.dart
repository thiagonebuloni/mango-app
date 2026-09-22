import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:financ/models/models.dart';
import 'package:financ/screens/expense_form_screen.dart';
import 'package:financ/screens/home_screen.dart';
import 'package:financ/screens/reports_screen.dart';
import 'package:financ/state/providers.dart';
import 'package:financ/widgets/common.dart';

class _FakeExpensesNotifier extends ExpensesNotifier {
  _FakeExpensesNotifier([this._expenses = const []]);

  final List<Expense> _expenses;

  @override
  Future<List<Expense>> build() async => _expenses;
}

class _FakeReportsNotifier extends ExpensesForReports {
  _FakeReportsNotifier([this._expenses = const []]);

  final List<Expense> _expenses;

  @override
  Future<List<Expense>> build() async => _expenses;
}

/// Gasto de hoje (meio-dia) para as telas com dados — sempre cai no mês atual.
Expense _gasto(int i) {
  final now = DateTime.now();
  return Expense(
    valorCentavos: 1000 + i * 100,
    dataHora: DateTime(now.year, now.month, now.day, 12),
    categoria: Category.mercado,
    forma: PaymentMethod.dinheiro,
    estabelecimento: 'MERCADO TESTE $i',
  );
}

void main() async {
  await initializeDateFormatting('pt_BR');

  testWidgets('HomeScreen mostra cards de resumo e estado vazio',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expensesProvider.overrideWith(() => _FakeExpensesNotifier()),
        ],
        child: _makeApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dia'), findsOneWidget);
    expect(find.text('Semana'), findsOneWidget);
    expect(find.text('Mês'), findsOneWidget);
    expect(find.textContaining('Nenhum gasto'), findsOneWidget);
  });

  group('Fluxo Lançamento manual (bottom sheet → form → date picker)', () {
    testWidgets('tocar em Lançamento manual abre o formulário', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            expensesProvider.overrideWith(() => _FakeExpensesNotifier()),
          ],
          child: _makeApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Abre o menu (+) e toca em "Lançamento manual".
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lançamento manual'));
      await tester.pumpAndSettle();

      // O formulário manual deve ter sido empilhado.
      expect(find.text('Novo gasto'), findsOneWidget);
      expect(find.text('Data e hora'), findsOneWidget);
    });

    testWidgets('tocar em Data e hora abre o seletor de data', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            expensesProvider.overrideWith(() => _FakeExpensesNotifier()),
          ],
          child: _makeApp(home: const ExpenseFormScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Data e hora'));
      await tester.pumpAndSettle();

      // O diálogo do showDatePicker deve aparecer.
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });
  });

  group('ReportsScreen (barra de períodos)', () {
    testWidgets('botões Mês/30 dias/Ano/Custom ficam centralizados',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            expensesForReportsProvider
                .overrideWith(() => _FakeReportsNotifier()),
          ],
          child: _makeApp(home: const ReportsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in ['Mês', '30 dias', 'Ano', 'Custom']) {
        expect(find.text(label), findsOneWidget);
      }

      final screenWidth = tester.getSize(find.byType(Scaffold)).width;
      final bar = tester.getSize(find.byType(ToggleButtons));
      expect(
        bar.width,
        lessThan(screenWidth - 24),
        reason: 'a barra deve encolher ao conteúdo e não ocupar a tela toda',
      );
      expect(
        tester.getCenter(find.byType(ToggleButtons)).dx,
        moreOrLessEquals(screenWidth / 2, epsilon: 1),
        reason: 'a barra de períodos deve ficar centralizada',
      );
    });
  });

  group('FAB não cobre o conteúdo', () {
    testWidgets('HomeScreen: último gasto fica acima do FAB', (tester) async {
      final gastos = [for (var i = 0; i < 8; i++) _gasto(i)];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            expensesProvider.overrideWith(() => _FakeExpensesNotifier(gastos)),
          ],
          child: _makeApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Rola a lista até o fim.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
      await tester.pumpAndSettle();

      final fabTop = tester.getTopLeft(find.byType(FloatingActionButton)).dy;
      final lastTileBottom =
          tester.getBottomLeft(find.byType(ExpenseTile).last).dy;
      expect(
        lastTileBottom,
        lessThan(fabTop),
        reason: 'a lista deve rolar até deixar o último gasto acima do FAB',
      );
    });

    testWidgets('ReportsScreen: cartões ficam acima do FAB', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            expensesForReportsProvider
                .overrideWith(() => _FakeReportsNotifier([_gasto(0)])),
          ],
          child: _makeApp(home: const ReportsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Rola a página até o fim.
      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();

      final fabTop = tester.getTopLeft(find.byType(FloatingActionButton)).dy;
      final lastCardBottom = tester.getBottomLeft(find.byType(Card).last).dy;
      expect(
        lastCardBottom,
        lessThan(fabTop),
        reason: 'a página deve rolar até os dados ficarem acima do FAB',
      );
    });
  });
}

Widget _makeApp({Widget? home}) => MaterialApp(
      home: home ?? const HomeScreen(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
