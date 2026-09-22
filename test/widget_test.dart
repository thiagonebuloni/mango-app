import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:financ/main.dart';
import 'package:financ/models/models.dart';
import 'package:financ/screens/expense_form_screen.dart';
import 'package:financ/screens/home_screen.dart';
import 'package:financ/screens/landing_screen.dart';
import 'package:financ/screens/profile_setup_screen.dart';
import 'package:financ/screens/reports_screen.dart';
import 'package:financ/state/providers.dart';
import 'package:financ/widgets/common.dart';

/// Perfil já cadastrado (casos de "demais aberturas" do app).
const _perfilTeste = UserProfile(
  nome: 'Ana',
  avatar: '🦊',
  corFundo: 0xFFE3F2FD,
);

class _FakeProfileNotifier extends ProfileNotifier {
  _FakeProfileNotifier([this._perfil]);

  final UserProfile? _perfil;

  /// Último perfil salvo pelo usuário (para as asserções dos testes).
  UserProfile? salvo;

  @override
  Future<UserProfile?> build() async => _perfil;

  @override
  Future<void> save(UserProfile profile) async {
    salvo = profile;
    state = AsyncData(profile);
  }
}

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

  group('Primeiro acesso (cadastro do perfil)', () {
    testWidgets('sem perfil o app abre a tela de cadastro', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(() => _FakeProfileNotifier()),
          ],
          child: _makeApp(home: const ProfileGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bem-vindo!'), findsOneWidget);
      expect(find.text('Nome do usuário'), findsOneWidget);
      expect(find.text('Escolha seu avatar'), findsOneWidget);
      expect(find.text('Cor de fundo'), findsOneWidget);
      expect(find.text('Começar'), findsOneWidget);
      // A tela inicial (landing) só aparece depois do cadastro.
      expect(find.text('Meus gastos'), findsNothing);
    });

    testWidgets('salvar nome, avatar e cor abre a tela inicial',
        (tester) async {
      final notifier = _FakeProfileNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [profileProvider.overrideWith(() => notifier)],
          child: _makeApp(home: const ProfileGate()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Ana');
      await tester.ensureVisible(find.text(kProfileAvatars[8]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kProfileAvatars[8])); // 🦊
      await tester.ensureVisible(find.byKey(const ValueKey('cor-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cor-1'))); // azul
      await tester.ensureVisible(find.text('Começar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();

      expect(notifier.salvo?.nome, 'Ana');
      expect(notifier.salvo?.avatar, kProfileAvatars[8]);
      expect(notifier.salvo?.corFundo, kProfileColors[1].toARGB32());

      // A tela inicial substituiu o cadastro com o que foi escolhido.
      expect(find.text('Olá, Ana!'), findsOneWidget);
      expect(find.text('Meus gastos'), findsOneWidget);
      expect(find.text('Menu'), findsOneWidget);
    });

    testWidgets('nome vazio não salva e mostra o erro', (tester) async {
      final notifier = _FakeProfileNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [profileProvider.overrideWith(() => notifier)],
          child: _makeApp(home: const ProfileGate()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Começar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();

      expect(find.text('Informe seu nome'), findsOneWidget);
      expect(notifier.salvo, isNull);
    });
  });

  group('Tela inicial (landing)', () {
    Future<void> abrirTelaInicial(
      WidgetTester tester, {
      _FakeProfileNotifier? perfil,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(
                () => perfil ?? _FakeProfileNotifier(_perfilTeste)),
            expensesProvider.overrideWith(() => _FakeExpensesNotifier()),
            expensesForReportsProvider
                .overrideWith(() => _FakeReportsNotifier()),
          ],
          child: _makeApp(home: const ProfileGate()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('mostra avatar, nome e os botões, tudo centralizado',
        (tester) async {
      await abrirTelaInicial(tester);

      expect(find.text('🦊'), findsOneWidget);
      expect(find.text('Olá, Ana!'), findsOneWidget);
      expect(find.text('Meus gastos'), findsOneWidget);
      expect(find.text('Menu'), findsOneWidget);

      final centro = tester.getSize(find.byType(Scaffold)).width / 2;
      expect(tester.getCenter(find.byType(CircleAvatar)).dx,
          moreOrLessEquals(centro, epsilon: 1));
      expect(tester.getCenter(find.text('Olá, Ana!')).dx,
          moreOrLessEquals(centro, epsilon: 1));

      for (final label in ['Meus gastos', 'Menu']) {
        final botao = find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == kLandingActionWidth,
          ),
        );
        expect(botao, findsOneWidget, reason: 'botão "$label"');
        expect(
          tester.getCenter(botao).dx,
          moreOrLessEquals(centro, epsilon: 1),
          reason: 'botão "$label" deve ficar centralizado',
        );
      }
    });

    testWidgets('"Meus gastos" abre a navegação Gastos/Relatórios',
        (tester) async {
      await abrirTelaInicial(tester);

      await tester.tap(find.text('Meus gastos'));
      await tester.pumpAndSettle();

      expect(find.text('Gastos'), findsOneWidget);
      expect(find.text('Relatórios'), findsOneWidget);
      expect(find.textContaining('Nenhum gasto'), findsOneWidget);
    });

    testWidgets('"Menu" abre as opções do app', (tester) async {
      await abrirTelaInicial(tester);

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Relatórios'), findsOneWidget);
      expect(find.text('Editar perfil'), findsOneWidget);
      expect(find.text('Sobre o Financ'), findsOneWidget);
    });

    testWidgets('"Editar perfil" salva as alterações', (tester) async {
      final notifier = _FakeProfileNotifier(_perfilTeste);
      await abrirTelaInicial(tester, perfil: notifier);

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();

      // Campos vêm preenchidos com o perfil atual.
      expect(find.text('Ana'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Beatriz');
      await tester.ensureVisible(find.text('Salvar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(notifier.salvo?.nome, 'Beatriz');
      expect(find.text('Olá, Beatriz!'), findsOneWidget);
      expect(find.text('Perfil atualizado'), findsOneWidget);
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
