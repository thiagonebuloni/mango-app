import 'dart:async';

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

/// Perfil que nunca termina de carregar: simula o primeiro frame do app, antes
/// do `profileProvider` resolver.
class _LentoProfileNotifier extends ProfileNotifier {
  final _completer = Completer<UserProfile?>();

  @override
  Future<UserProfile?> build() => _completer.future;

  @override
  Future<void> save(UserProfile profile) async {}
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

    testWidgets('avatar pode vir do teclado de emojis do aparelho',
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
      await tester.ensureVisible(find.text('Outro emoji'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Outro emoji'));
      await tester.pumpAndSettle();

      // O diálogo abre com o campo em foco — é o autofocus que faz o teclado
      // (com a tecla de emojis) aparecer no aparelho.
      expect(find.text('Escolher emoji'), findsOneWidget);
      final campoDialogo = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(campoDialogo).autofocus, isTrue);

      // Emoji "digitado" no teclado do aparelho.
      await tester.enterText(campoDialogo, '🦄');
      await tester.tap(find.text('Usar'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Começar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();

      expect(notifier.salvo?.avatar, '🦄');
      expect(find.text('🦄'), findsOneWidget); // avatar na tela inicial
    });

    testWidgets('preview do avatar também abre o seletor, com validação',
        (tester) async {
      final notifier = _FakeProfileNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [profileProvider.overrideWith(() => notifier)],
          child: _makeApp(home: const ProfileGate()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('avatar-preview')));
      await tester.pumpAndSettle();

      final campoDialogo = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );

      // Sem emoji não fecha o diálogo (e a lista de atalhos continua válida).
      await tester.enterText(campoDialogo, '   ');
      await tester.tap(find.text('Usar'));
      await tester.pumpAndSettle();
      expect(find.text('Escolha um emoji'), findsOneWidget);
      expect(find.text('Escolher emoji'), findsOneWidget);

      // Emoji com vários code points (família) é guardado inteiro.
      await tester.enterText(campoDialogo, '👨‍👩‍👧');
      await tester.tap(find.text('Usar'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Ana');
      await tester.ensureVisible(find.text('Começar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();

      expect(notifier.salvo?.avatar, '👨‍👩‍👧');
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

    testWidgets('sair da edição com alterações pede confirmação',
        (tester) async {
      final notifier = _FakeProfileNotifier(_perfilTeste);
      await abrirTelaInicial(tester, perfil: notifier);

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();

      // Digita sem salvar e tenta sair pela seta de voltar.
      await tester.enterText(find.byType(TextFormField), 'Beatriz');
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Descartar alterações?'), findsOneWidget);
      expect(notifier.salvo, isNull);

      // Continuar editando mantém a tela e o que foi digitado.
      await tester.tap(find.text('Continuar editando'));
      await tester.pumpAndSettle();
      expect(find.text('Descartar alterações?'), findsNothing);
      expect(find.text('Beatriz'), findsOneWidget);
      expect(find.text('Olá, Ana!'), findsNothing);

      // Confirmando o descarte, volta sem salvar.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar e sair'));
      await tester.pumpAndSettle();

      expect(find.text('Olá, Ana!'), findsOneWidget);
      expect(notifier.salvo, isNull);
    });

    testWidgets('sair da edição sem alterações não pergunta nada',
        (tester) async {
      await abrirTelaInicial(tester);

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Descartar alterações?'), findsNothing);
      expect(find.text('Olá, Ana!'), findsOneWidget);
    });
  });

  group('Cor de fundo em todo o app', () {
    const cor = Color(0xFFE3F2FD); // cor do _perfilTeste

    Future<void> abrirApp(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider
                .overrideWith(() => _FakeProfileNotifier(_perfilTeste)),
            expensesProvider.overrideWith(() => _FakeExpensesNotifier()),
            expensesForReportsProvider
                .overrideWith(() => _FakeReportsNotifier()),
          ],
          child: const FinancApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tema do app usa a cor do perfil, em todas as telas',
        (tester) async {
      await abrirApp(tester);

      final themeInicial =
          tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
      expect(themeInicial.scaffoldBackgroundColor, cor);
      expect(themeInicial.appBarTheme.backgroundColor, cor);
      expect(themeInicial.navigationBarTheme.backgroundColor, cor);
      expect(themeInicial.bottomSheetTheme.backgroundColor, cor);
      expect(themeInicial.dialogTheme.backgroundColor, cor);

      // Dentro do app (Gastos) a cor continua valendo — inclusive pintada de
      // verdade pelo Scaffold/AppBar.
      await tester.tap(find.text('Meus gastos'));
      await tester.pumpAndSettle();

      final theme =
          Theme.of(tester.element(find.byType(HomeScreen)));
      expect(theme.scaffoldBackgroundColor, cor);
      expect(theme.appBarTheme.backgroundColor, cor);

      final fundo = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(HomeScreen),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(fundo.color, cor);
      expect(
        tester
            .widget<AppBar>(find.byType(AppBar))
            .backgroundColor,
        isNull, // usa o appBarTheme (cor do perfil)
      );
    });

    testWidgets('o app abre já com a cor do usuário (perfil lido no main)',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            perfilInicialProvider.overrideWithValue(_perfilTeste),
            profileProvider.overrideWith(() => _LentoProfileNotifier()),
          ],
          child: const FinancApp(),
        ),
      );
      await tester.pump(); // 1º frame: profileProvider ainda carregando

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .theme!
            .scaffoldBackgroundColor,
        cor,
      );
    });

    testWidgets('trocar a cor no perfil repinta o app', (tester) async {
      await abrirApp(tester);

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('cor-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cor-2'))); // lilás
      await tester.ensureVisible(find.text('Salvar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .theme!
            .scaffoldBackgroundColor,
        kProfileColors[2],
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
