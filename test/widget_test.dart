import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart'
    hide Category;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;

import 'package:mango/db/db.dart';
import 'package:mango/main.dart';
import 'package:mango/models/models.dart';
import 'package:mango/screens/capture_screen.dart';
import 'package:mango/screens/diagnostico_screen.dart';
import 'package:mango/screens/expense_form_screen.dart';
import 'package:mango/screens/home_screen.dart';
import 'package:mango/screens/landing_screen.dart';
import 'package:mango/screens/profile_setup_screen.dart';
import 'package:mango/screens/reports_screen.dart';
import 'package:mango/services/crash_log.dart';
import 'package:mango/state/providers.dart';
import 'package:mango/theme/app_theme.dart';
import 'package:mango/widgets/avatar.dart';
import 'package:mango/widgets/common.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Perfil já cadastrado (casos de "demais aberturas" do app).
const _perfilTeste = UserProfile(
  nome: 'Ana',
  avatar: '🦊',
  corFundo: 0xFFE3F2FD,
  temaClaro: true,
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

/// Rola a edição de perfil até o botão "Salvar" ficar tocável.
///
/// A tela de edição é mais alta que a viewport de teste (600px), então rola
/// o [SingleChildScrollView] da tela até o centro do botão entrar na
/// viewport (só estar parcialmente visível não basta para o `tap`).
Future<void> _rolarAteSalvar(WidgetTester tester) async {
  final salvar = find.text('Salvar');
  final view = find.byType(SingleChildScrollView);
  await tester.dragUntilVisible(
    salvar,
    view,
    const Offset(0, -200),
  );
  await tester.pumpAndSettle();
  // `dragUntilVisible` para na primeira aparição parcial: continua rolando
  // até o centro do botão (usado pelo `tap`) entrar na viewport de 600px.
  for (var i = 0; i < 5; i++) {
    final dy = tester.getCenter(salvar).dy;
    if (dy < 550) break;
    await tester.drag(view, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
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

/// Receita de hoje (meio-dia) para os testes do gráfico despesas x receitas.
Expense _receita(int i) {
  final now = DateTime.now();
  return Expense(
    tipo: EntryKind.receita,
    valorCentavos: 5000 + i * 100,
    dataHora: DateTime(now.year, now.month, now.day, 12),
    categoria: Category.salario,
    forma: PaymentMethod.pix,
    estabelecimento: 'EMPRESA TESTE $i',
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

  group('Backup CSV (exportar/importar)', () {
    test('exportar → importar preserva despesas, receitas e textos com ";"',
        () {
      final originais = [
        Expense(
          valorCentavos: 12345,
          dataHora: DateTime(2026, 8, 20, 9, 30),
          categoria: Category.mercado,
          forma: PaymentMethod.pix,
          descricao: 'café; pão',
          estabelecimento: 'MERCADO "BOM" LTDA',
        ),
        Expense(
          valorCentavos: 50000,
          dataHora: DateTime(2026, 9, 1, 8),
          categoria: Category.outros,
          forma: PaymentMethod.dinheiro,
          estabelecimento: 'SALÁRIO',
          tipo: EntryKind.receita,
        ),
      ];

      final result = CsvBackup.import(CsvBackup.export(originais));

      expect(result.skipped, 0);
      expect(result.expenses, hasLength(2));

      final despesa = result.expenses.singleWhere((e) => !e.isReceita);
      expect(despesa.valorCentavos, 12345);
      expect(despesa.dataHora, DateTime(2026, 8, 20, 9, 30));
      expect(despesa.categoria, Category.mercado);
      expect(despesa.forma, PaymentMethod.pix);
      expect(despesa.descricao, 'café; pão');
      expect(despesa.estabelecimento, 'MERCADO "BOM" LTDA');

      final receita = result.expenses.singleWhere((e) => e.isReceita);
      expect(receita.valorCentavos, 50000);
      expect(receita.estabelecimento, 'SALÁRIO');
    });

    test('linhas inválidas são ignoradas (skipped)', () {
      final result = CsvBackup.import('${CsvBackup.header}\nso um campo');
      expect(result.expenses, isEmpty);
      expect(result.skipped, 1);
    });

    test('chave de duplicidade sobrevive ao export/import (agregação)', () {
      final original = Expense(
        valorCentavos: 12345,
        dataHora: DateTime(2026, 8, 20, 9, 30, 15, 250),
        categoria: Category.mercado,
        forma: PaymentMethod.pix,
        descricao: 'café; pão',
        estabelecimento: 'MERCADO "BOM" LTDA',
      );
      final reimportado =
          CsvBackup.import(CsvBackup.export([original])).expenses.single;

      // Mesmo registro → mesma chave: a importação agrega sem duplicar.
      expect(reimportado.chaveUnica, original.chaveUnica);

      // Dados diferentes → chave diferente (seria um registro novo).
      expect(
        original.copyWith(valorCentavos: 999).chaveUnica,
        isNot(original.chaveUnica),
      );
      expect(
        original.copyWith(tipo: EntryKind.receita).chaveUnica,
        isNot(original.chaveUnica),
      );
    });
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

      // Abre o menu (+), entra em "Despesas" e toca em "Lançamento manual".
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('Despesas'), findsOneWidget);
      expect(find.text('Receita'), findsOneWidget);
      await tester.tap(find.text('Despesas'));
      await tester.pumpAndSettle();
      expect(find.text('Foto do cupom fiscal'), findsOneWidget);
      await tester.tap(find.text('Lançamento manual'));
      await tester.pumpAndSettle();

      // O formulário manual deve ter sido empilhado.
      expect(find.text('Nova despesa'), findsOneWidget);
      expect(find.text('Data e hora'), findsOneWidget);
    });

    testWidgets('tocar em Receita abre o formulário de receita',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            expensesProvider.overrideWith(() => _FakeExpensesNotifier()),
          ],
          child: _makeApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Nível 1 do menu (+): "Receita" já abre o formulário, sem submenu.
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receita'));
      await tester.pumpAndSettle();

      expect(find.text('Nova receita'), findsOneWidget);
      expect(find.text('Origem'), findsOneWidget);
      expect(find.text('Lançamento manual'), findsNothing);
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

    testWidgets('aviso de parcelas aparece integral e centralizado',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            expensesProvider.overrideWith(() => _FakeExpensesNotifier()),
          ],
          child: _makeApp(home: const ExpenseFormScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Valor total de R$ 100,00 em 2x: o aviso mostra 2x R$ 50,00.
      await tester.enterText(find.byType(TextFormField).first, '100,00');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'LOJA XYZ 1/2');
      await tester.pump();

      final aviso = find.textContaining('Serão criados 2 lançamentos');
      expect(aviso, findsOneWidget);
      final texto = tester.widget<Text>(aviso);
      expect(texto.textAlign, TextAlign.center);
      // Sem corte: texto em até 3 linhas, sem overflow.
      expect(texto.maxLines, isNull);
      expect(texto.overflow, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('ReportsScreen (barra de períodos)', () {
    testWidgets('mostra gráfico de barras despesas x receitas do período',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            expensesForReportsProvider
                .overrideWith(() => _FakeReportsNotifier([_gasto(0), _receita(0)])),
          ],
          child: _makeApp(home: const ReportsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Despesas x Receitas'), findsOneWidget);
      // Barras do gráfico: uma para despesas, uma para receitas.
      expect(find.byType(BarChart), findsOneWidget);
      // Valores por extenso na legenda, abaixo das barras (o rótulo aparece
      // 2x: título do eixo do gráfico + legenda com o valor).
      expect(find.text('Despesas'), findsNWidgets(2));
      expect(find.text('Receitas'), findsNWidgets(2));
      // O valor aparece 2x: legenda do gráfico + cartão "Gastos por dia".
      expect(find.text('R\$ 10,00'), findsNWidgets(2));
      expect(find.text('R\$ 50,00'), findsOneWidget);
      // Saldo = receitas − despesas, positivo usa "+" em verde.
      expect(find.text('Saldo'), findsOneWidget);
      expect(find.text('+ R\$ 40,00'), findsOneWidget);
    });

    testWidgets('saldo negativo usa "-" em vermelho',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            expensesForReportsProvider
                .overrideWith(() => _FakeReportsNotifier([_gasto(5)])),
          ],
          child: _makeApp(home: const ReportsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Só despesa de R$ 15,00: saldo = -R$ 15,00.
      expect(find.text('- R\$ 15,00'), findsOneWidget);
      final saldo = tester.widget<Text>(find.text('- R\$ 15,00'));
      expect(saldo.style?.color, Colors.red.shade400);
    });

    testWidgets('gráfico despesas x receitas aparece mesmo sem lançamentos',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            expensesForReportsProvider.overrideWith(() => _FakeReportsNotifier()),
          ],
          child: _makeApp(home: const ReportsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Despesas x Receitas'), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
    });

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

      // Rola a página até o fim (em etapas: a página cresce com novos cartões).
      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();
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
    testWidgets('sem perfil o app pergunta sobre backup', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(() => _FakeProfileNotifier()),
          ],
          child: _makeApp(home: const ProfileGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bem-vindo ao Mango!'), findsOneWidget);
      expect(find.text('Restaurar backup'), findsOneWidget);
      expect(find.text('Criar perfil novo'), findsOneWidget);
      // A tela inicial (landing) só aparece depois do cadastro.
      expect(find.text('Gastos'), findsNothing);
      expect(find.text('Relatórios'), findsNothing);

      // Criar novo abre o cadastro de perfil.
      await tester.tap(find.text('Criar perfil novo'));
      await tester.pumpAndSettle();
      expect(find.text('Bem-vindo!'), findsOneWidget);
      expect(find.text('Nome do usuário'), findsOneWidget);
      expect(find.text('Escolha seu avatar'), findsOneWidget);
      expect(find.text('Cor de fundo'), findsOneWidget);
      expect(find.text('Começar'), findsOneWidget);
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

      // Primeiro acesso: passar pelo gate do backup.
      await tester.tap(find.text('Criar perfil novo'));
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
      // Perfil novo usa o tema escuro por padrao.
      expect(notifier.salvo?.temaClaro, isFalse);
      expect(notifier.salvo?.corFundo, kProfileColorsEscuro[1].toARGB32());

      // Primeiro acesso via gate do backup: o cadastro foi empilhado;
      // ao salvar, o perfil existe e o gate mostra a landing por baixo.
      // Sair do cadastro (sem alteracoes pendentes) revela a landing.
      final navState = tester.state<NavigatorState>(find.byType(Navigator));
      navState.pop();
      await tester.pumpAndSettle();
      expect(find.text('Olá, Ana!'), findsOneWidget);
      expect(find.text('Gastos'), findsOneWidget);
      expect(find.text('Relatórios'), findsOneWidget);
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

      await tester.tap(find.text('Criar perfil novo'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Começar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();

      expect(find.text('Informe seu nome'), findsOneWidget);
      expect(notifier.salvo, isNull);
    });

    testWidgets('avatar pode vir da grade com todos os emojis',
        (tester) async {
      final notifier = _FakeProfileNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [profileProvider.overrideWith(() => notifier)],
          child: _makeApp(home: const ProfileGate()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Criar perfil novo'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Ana');
      await tester.ensureVisible(find.text('Outro emoji'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Outro emoji'));
      await tester.pumpAndSettle();

      // Abre direto a grade de emojis (interna ao app, com todos — busca,
      // categorias e recentes), sem depender do teclado do aparelho.
      expect(find.text('Escolha um emoji'), findsOneWidget);
      expect(find.byType(EmojiPicker), findsOneWidget);

      // Tocar num emoji fecha a grade e atualiza o preview.
      final grade = tester.widget<EmojiPicker>(find.byType(EmojiPicker));
      grade.onEmojiSelected!.call(null, const Emoji('🦄', 'unicorn'));
      await tester.pumpAndSettle();

      expect(find.text('Escolha um emoji'), findsNothing);

      await tester.ensureVisible(find.text('Começar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();

      expect(notifier.salvo?.avatar, '🦄');
      expect(find.text('🦄'), findsOneWidget); // avatar na tela inicial
    });

    testWidgets('preview do avatar também abre a grade de emojis',
        (tester) async {
      final notifier = _FakeProfileNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [profileProvider.overrideWith(() => notifier)],
          child: _makeApp(home: const ProfileGate()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Criar perfil novo'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('avatar-preview')));
      await tester.pumpAndSettle();
      // O toque no avatar abre o menu (emoticon ou foto): escolher o
      // emoticon abre a grade de emojis.
      expect(find.text('Escolher emoticon'), findsOneWidget);
      await tester.tap(find.text('Escolher emoticon'));
      await tester.pumpAndSettle();
      expect(find.text('Escolha um emoji'), findsOneWidget);

      // Família (emoji com vários code points) é guardada inteira.
      final grade = tester.widget<EmojiPicker>(find.byType(EmojiPicker));
      grade.onEmojiSelected!
          .call(null, const Emoji('👨‍👩‍👧', 'family man woman girl'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Ana');
      await tester.ensureVisible(find.text('Começar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();

      expect(notifier.salvo?.avatar, '👨‍👩‍👧');
    });
  });

  group('Avatar (foto e recorte)', () {
    testWidgets('tocar no avatar abre o menu com emoticon e foto',
        (tester) async {
      final notifier = _FakeProfileNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [profileProvider.overrideWith(() => notifier)],
          child: _makeApp(home: const ProfileGate()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Criar perfil novo'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('avatar-preview')));
      await tester.pumpAndSettle();

      expect(find.text('Escolher emoticon'), findsOneWidget);
      expect(find.text('Foto da galeria'), findsOneWidget);
      expect(find.text('Tirar foto'), findsOneWidget);
      // Sem foto ainda: sem opções de ajuste/remoção.
      expect(find.text('Ajustar posi\u00e7\u00e3o e recorte'), findsNothing);
      expect(find.text('Remover foto'), findsNothing);
    });

    test('limite da foto do avatar: at\u00e9 5 MB passa', () {
      expect(validarTamanhoAvatar(kMaxAvatarImageBytes), isNull);
      expect(validarTamanhoAvatar(3 * 1024 * 1024), isNull);

      final erro = validarTamanhoAvatar(12 * 1024 * 1024);
      expect(erro, isNotNull);
      expect(erro, contains('12.0 MB'));
      expect(erro, contains('m\u00e1ximo 5 MB'));
    });

    test('perfil com foto guarda recorte e cai para o emoticon sem foto', () {
      const comFoto = UserProfile(
        nome: 'Ana',
        avatar: '\ud83e\udd8a',
        corFundo: 0xFFE3F2FD,
        avatarImagePath: '/tmp/avatar.jpg',
        avatarAlignX: 0.5,
        avatarAlignY: -0.5,
        avatarZoom: 2,
      );
      expect(comFoto.temFoto, isTrue);
      final mapa = comFoto.toMap();
      expect(mapa['avatar_img'], '/tmp/avatar.jpg');
      expect(mapa['avatar_ax'], 0.5);
      expect(mapa['avatar_zoom'], 2);
      final lido = UserProfile.fromMap(mapa);
      expect(lido.avatarImagePath, '/tmp/avatar.jpg');
      expect(lido.avatarAlignX, 0.5);
      expect(lido.avatarZoom, 2);
      // Perfis antigos (sem as colunas novas) continuam com o emoticon.
      final antigo = UserProfile.fromMap(const {
        'nome': 'Ana',
        'avatar': '\ud83e\udd8a',
        'cor': 0xFFE3F2FD,
      });
      expect(antigo.temFoto, isFalse);
      expect(antigo.avatarImagePath, isNull);
    });
  });

  group('Limite da imagem do cupom', () {
    test('até 8 MB passa; acima disso, mensagem com o tamanho', () {
      expect(validarTamanhoImagem(kMaxReceiptImageBytes), isNull);
      expect(validarTamanhoImagem(3 * 1024 * 1024), isNull);

      final erro = validarTamanhoImagem(12 * 1024 * 1024);
      expect(erro, isNotNull);
      expect(erro, contains('12.0 MB'));
      expect(erro, contains('máximo 8 MB'));
    });
  });

  group('Foto do cupom no lançamento', () {
    Expense lancamentoComFoto(String? fotoPath) => Expense(
          id: 1,
          valorCentavos: 1500,
          dataHora: DateTime(2026, 3, 20, 12),
          categoria: Category.outros,
          forma: PaymentMethod.dinheiro,
          estabelecimento: 'PADARIA',
          fotoPath: fotoPath,
        );

    /// Abre o formulário em edição e deixa a checagem do arquivo terminar: ela
    /// é I/O de verdade (o `runAsync` libera o event loop) antes de conferir a
    /// tela.
    Future<void> abrirEdicao(WidgetTester tester, Expense expense) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            expensesProvider.overrideWith(() => _FakeExpensesNotifier()),
          ],
          child: _makeApp(home: ExpenseFormScreen(expense: expense)),
        ),
      );
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    testWidgets('lançamento sem foto não mostra a miniatura', (tester) async {
      await abrirEdicao(tester, lancamentoComFoto(null));

      expect(find.text('Foto do cupom'), findsNothing);
      expect(find.text('Toque para ampliar'), findsNothing);
    });

    testWidgets('foto que já não está no aparelho não mostra a miniatura',
        (tester) async {
      await abrirEdicao(tester, lancamentoComFoto('/nao/existe/cupom_1.jpg'));

      expect(find.text('Foto do cupom'), findsNothing);
    });

    testWidgets('foto no aparelho mostra a miniatura e amplia ao tocar',
        (tester) async {
      Directory? pasta;
      await tester.runAsync(() async {
        pasta = await Directory.systemTemp.createTemp('mango_cupom_ui_');
        File(p.join(pasta!.path, 'cupom_1.jpg'))
            .writeAsBytesSync(base64Decode(_pngUmPixel));
      });
      addTearDown(() {
        if (pasta != null && pasta!.existsSync()) {
          pasta!.deleteSync(recursive: true);
        }
      });

      await abrirEdicao(
          tester, lancamentoComFoto(p.join(pasta!.path, 'cupom_1.jpg')));

      expect(find.text('Foto do cupom'), findsOneWidget);
      expect(find.text('Toque para ampliar'), findsOneWidget);

      // O cartão fica abaixo da área visível (a viewport de teste tem 600px):
      // rola até ele antes de tocar, senão o tap erra o alvo.
      await tester.ensureVisible(find.text('Foto do cupom'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Foto do cupom'));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsOneWidget);
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
      expect(find.text('Gastos'), findsOneWidget);
      expect(find.text('Relatórios'), findsOneWidget);
      expect(find.text('Menu'), findsOneWidget);

      final centro = tester.getSize(find.byType(Scaffold)).width / 2;
      expect(tester.getCenter(find.byType(CircleAvatar)).dx,
          moreOrLessEquals(centro, epsilon: 1));
      expect(tester.getCenter(find.text('Olá, Ana!')).dx,
          moreOrLessEquals(centro, epsilon: 1));

      for (final label in ['Gastos', 'Relatórios', 'Menu']) {
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

    testWidgets('botão "Gastos" abre a navegação Gastos/Relatórios',
        (tester) async {
      await abrirTelaInicial(tester);

      await tester.tap(find.text('Gastos'));
      await tester.pumpAndSettle();

      expect(find.text('Gastos'), findsOneWidget);
      expect(find.text('Relatórios'), findsOneWidget);
      expect(find.textContaining('Nenhum gasto'), findsOneWidget);
    });

    testWidgets('botão "Relatórios" abre direto os relatórios',
        (tester) async {
      await abrirTelaInicial(tester);

      await tester.tap(find.text('Relatórios'));
      await tester.pumpAndSettle();

      expect(find.byType(ReportsScreen), findsOneWidget);
      expect(find.text('Gastos'), findsOneWidget); // navegação inferior
      // Título do AppBar + navegação inferior.
      expect(find.text('Relatórios'), findsNWidgets(2));
    });

    testWidgets('"Menu" abre as opções do app', (tester) async {
      await abrirTelaInicial(tester);

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      // Tela inicial tem as duas abas: cada texto aparece no botão da
      // landing + no item correspondente do menu.
      expect(find.text('Gastos'), findsNWidgets(2));
      expect(find.text('Relatórios'), findsNWidgets(2));
      expect(find.text('Editar perfil'), findsOneWidget);
      expect(find.text('Exportar em CSV'), findsOneWidget);
      expect(find.text('Importar em CSV'), findsOneWidget);
      expect(find.text('Sobre o Mango'), findsOneWidget);
    });

    testWidgets('"Sobre o Mango" mostra a versão do próprio app',
        (tester) async {
      // A versão vem do pacote instalado: o mock evita depender do plugin e
      // fixa um valor qualquer de propósito — não acompanha o `pubspec.yaml`.
      PackageInfo.setMockInitialValues(
        appName: 'Mango',
        packageName: 'br.com.mango.mango',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      await abrirTelaInicial(tester);

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      // O menu é mais alto que a viewport de teste (600px) e "Sobre o Mango" é
      // o último item: rola até ele antes de tocar, senão o tap erra o alvo.
      await tester.ensureVisible(find.text('Sobre o Mango'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sobre o Mango'));
      await tester.pumpAndSettle();

      expect(find.text('1.0.0 (1)'), findsOneWidget);
    });

    testWidgets('telas Gastos e Relatórios têm ícone de menu no AppBar',
        (tester) async {
      // Os dois scopes precisam da MESMA lista de overrides: reutilizar o
      // ProviderScope com overrides diferentes dispara erro do Riverpod.
      final overrides = [
        expensesProvider.overrideWith(() => _FakeExpensesNotifier()),
        expensesForReportsProvider
            .overrideWith(() => _FakeReportsNotifier()),
      ];

      // Tela Gastos.
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: _makeApp(home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.menu),
        ),
      );
      await tester.pumpAndSettle();
      // Aberto em Gastos: o menu oferece apenas a aba oposta (Relatórios).
      expect(find.text('Relatórios'), findsOneWidget);
      expect(find.text('Gastos'), findsNothing);
      expect(find.text('Editar perfil'), findsOneWidget);
      expect(find.text('Exportar em CSV'), findsOneWidget);
      expect(find.text('Importar em CSV'), findsOneWidget);
      expect(find.text('Sobre o Mango'), findsOneWidget);

      // Fecha o sheet antes de trocar de tela: o scrim dele bloquearia o
      // tap no ícone de menu da próxima tela.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      // Tela Relatórios: mesmo menu.
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: _makeApp(home: const ReportsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.menu),
        ),
      );
      await tester.pumpAndSettle();
      // Aberto em Relatórios: o menu oferece apenas a aba oposta (Gastos).
      // O "Relatórios" único é o título do AppBar (o item do menu some).
      expect(find.text('Gastos'), findsOneWidget);
      expect(find.text('Relatórios'), findsOneWidget);
      expect(find.text('Editar perfil'), findsOneWidget);
      expect(find.text('Exportar em CSV'), findsOneWidget);
      expect(find.text('Sobre o Mango'), findsOneWidget);
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
      await _rolarAteSalvar(tester);
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
          child: const MangoApp(),
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
      await tester.tap(find.text('Gastos'));
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
          child: const MangoApp(),
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
      await _rolarAteSalvar(tester);
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

    testWidgets('fundo escuro é sempre cinza escuro fixo',
        (tester) async {
      const claro = Color(0xFFE3F2FD); // azul claro da paleta
      const escuro = Color(0xFF1E3A5F); // azul escuro correspondente
      for (final cor in [claro, escuro]) {
        final fundo = corFundoDoPerfil(
          UserProfile(
            nome: 'Ana',
            avatar: '🦊',
            corFundo: cor.toARGB32(),
            temaClaro: false,
          ),
        );
        expect(fundo, kFundoTemaEscuro);
      }
      expect(corDestaqueDoPerfil(_perfilTeste), isNull);
      expect(
        corDestaqueDoPerfil(
          const UserProfile(
            nome: 'Ana',
            avatar: '🦊',
            corFundo: 0xFFE3F2FD,
            temaClaro: false,
          ),
        ),
        escuro,
      );
    });

    testWidgets('tema escuro usa brilho escuro e destaque nas caixas',
        (tester) async {
      const perfilEscuro = UserProfile(
        nome: 'Ana',
        avatar: '🦊',
        corFundo: 0xFF1E3A5F,
        temaClaro: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider
                .overrideWith(() => _FakeProfileNotifier(perfilEscuro)),
            expensesProvider.overrideWith(() => _FakeExpensesNotifier()),
            expensesForReportsProvider
                .overrideWith(() => _FakeReportsNotifier()),
          ],
          child: const MangoApp(),
        ),
      );
      await tester.pumpAndSettle();

      final theme =
          tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
      expect(theme.brightness, Brightness.dark);
      expect(
        theme.scaffoldBackgroundColor,
        corFundoDoPerfil(perfilEscuro),
      );
      expect(corDestaqueDoPerfil(perfilEscuro), kCoresTemaEscuro[1]);
    });

    testWidgets('editar perfil tem rolagem e troca a paleta com o tema',
        (tester) async {
      final notifier = _FakeProfileNotifier(_perfilTeste);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [profileProvider.overrideWith(() => notifier)],
          child: _makeApp(home: ProfileSetupScreen(existing: _perfilTeste)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tema'), findsOneWidget);
      expect(find.text('Claro'), findsOneWidget);
      expect(find.text('Escuro'), findsOneWidget);
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(
        tester
            .widget<ColorChoice>(find.byKey(const ValueKey('cor-1')))
            .color,
        kCoresTemaClaro[1],
      );

      // Tema claro: nome do usuário com fonte escura para contraste.
      final campoClaro =
          tester.widget<TextField>(find.byType(TextField).first);
      expect(campoClaro.style?.color, onBackgroundColor(kCoresTemaClaro[1]));

      await tester.ensureVisible(find.text('Escuro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escuro'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ColorChoice>(find.byKey(const ValueKey('cor-1')))
            .color,
        kCoresTemaEscuro[1],
      );

      // Prévia do tema escuro: fundo sempre cinza escuro fixo.
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        kFundoTemaEscuro,
      );
      final campoEscuro =
          tester.widget<TextField>(find.byType(TextField).first);
      expect(campoEscuro.style?.color, onBackgroundColor(kFundoTemaEscuro));

      await _rolarAteSalvar(tester);
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(notifier.salvo?.temaClaro, isFalse);
      expect(notifier.salvo?.corFundo, kCoresTemaEscuro[1].toARGB32());
    });

    testWidgets('card de Tema muda sozinho ao escolher outra cor',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(() => _FakeProfileNotifier(_perfilTeste)),
          ],
          child:
              _makeApp(home: ProfileSetupScreen(existing: _perfilTeste)),
        ),
      );
      await tester.pumpAndSettle();

      // Fundo do card de Tema derivado da cor inicial (tema claro).
      Color corCard() => (tester
              .widget<Container>(find.byKey(const ValueKey('tema-card')))
              .decoration! as BoxDecoration)
          .color!;

      final cardInicial = corCard();
      expect(
        cardInicial,
        Color.lerp(kCoresTemaClaro[1], Colors.white, 0.35),
      );

      // Escolhe outra cor da paleta: o card acompanha sem tocar no tema.
      await tester.ensureVisible(find.byKey(const ValueKey('cor-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cor-0')));
      await tester.pumpAndSettle();

      expect(
        corCard(),
        Color.lerp(kCoresTemaClaro[0], Colors.white, 0.35),
      );
      expect(corCard(), isNot(cardInicial));
      // O modo (Claro) permanece o mesmo: o botão segue selecionado
      // (fundo com cor, não transparente).
      expect(find.byKey(const ValueKey('tema-claro')), findsOneWidget);
      final bgClaro = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(const ValueKey('tema-claro')),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        (bgClaro.decoration! as BoxDecoration).color,
        isNot(Colors.transparent),
      );
    });
  });

  group('Diagnóstico (falhas locais)', () {
    /// Diretório temporário para o log, apagado ao fim do teste.
    Directory novoDir() {
      final dir = Directory.systemTemp.createTempSync('mango_diag_test');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      return dir;
    }

    /// Grava eventos no log. A escrita é I/O de verdade: o `runAsync` libera
    /// o event loop — o relógio falso do teste não entrega a escrita sozinho.
    Future<void> semear(
      WidgetTester tester,
      Directory dir,
      List<String> erros,
    ) async {
      reiniciarFila();
      await tester.runAsync(() async {
        for (final erro in erros) {
          await registrarFalha(erro, null, dir: dir);
        }
        await aguardarEscritas();
      });
    }

    /// Abre a tela pelo caminho do usuário: Menu → Diagnóstico.
    Future<void> abrirPeloMenu(WidgetTester tester) async {
      reiniciarFila();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider
                .overrideWith(() => _FakeProfileNotifier(_perfilTeste)),
            expensesProvider.overrideWith(() => _FakeExpensesNotifier()),
            expensesForReportsProvider
                .overrideWith(() => _FakeReportsNotifier()),
          ],
          child: _makeApp(home: const ProfileGate()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      // O sheet é rolável: "Diagnóstico" pode nascer abaixo da dobra.
      await tester.ensureVisible(find.text('Diagnóstico'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diagnóstico'));
      // A tela lê o arquivo no initState: o `runAsync` deixa a I/O terminar
      // e os pumps adiantam a rota — um pumpAndSettle aqui giraria à toa no
      // spinner enquanto a leitura não volta.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// Espera a I/O real terminar. Cada `runAsync` entrega **um** passo de
    /// arquivo (criar → existir → ler/apagar) e o `pump` consolida o passo
    /// seguinte — sem isso o relógio falso fica girando no spinner e o
    /// pumpAndSettle estoura o tempo (mesmo truque do grupo "Foto do cupom").
    Future<void> aguardarLeitura(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> abrirDireto(WidgetTester tester, Directory dir) async {
      reiniciarFila();
      await tester.pumpWidget(_makeApp(home: DiagnosticoScreen(dir: dir)));
      await aguardarLeitura(tester);
    }

    testWidgets('item no menu abre a tela de Diagnóstico', (tester) async {
      await abrirPeloMenu(tester);

      expect(find.text('Diagnóstico'), findsOneWidget);
      // A tela deixa claro que nada sai sozinho do aparelho.
      expect(find.textContaining('Nada é enviado'), findsOneWidget);
    });

    testWidgets('sem falhas → estado vazio e botões desativados',
        (tester) async {
      await abrirDireto(tester, novoDir());

      expect(find.text('Nenhuma falha registrada'), findsOneWidget);
      final compartilhar = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Compartilhar'),
      );
      expect(compartilhar.onPressed, isNull);
    });

    testWidgets('falha registrada aparece; Compartilhar avisa se falhar',
        (tester) async {
      final dir = novoDir();
      await semear(tester, dir, ['boom simulado', 'boom simulado']);

      await abrirDireto(tester, dir);

      // Duas ocorrências seguidas viram uma linha com ×2.
      expect(find.textContaining('boom simulado (×2)'), findsOneWidget);

      // Sem app de compartilhamento (plugin) o toque não pode travar: ele
      // precisa avisar em vez de falhar em silêncio.
      await tester.tap(find.text('Compartilhar'));
      await aguardarLeitura(tester);
      expect(
        find.textContaining('Não foi possível compartilhar'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });

    testWidgets('Limpar confirma e apaga o registro', (tester) async {
      final dir = novoDir();
      await semear(tester, dir, ['falha para apagar']);

      await abrirDireto(tester, dir);
      expect(find.textContaining('falha para apagar'), findsOneWidget);

      await tester.tap(find.text('Limpar'));
      await tester.pumpAndSettle();
      expect(find.text('Apagar o registro?'), findsOneWidget);

      // A confirmação apaga o arquivo de verdade (vários passos de I/O).
      await tester.tap(find.text('Apagar'));
      await aguardarLeitura(tester);

      expect(find.text('Nenhuma falha registrada'), findsOneWidget);
      expect(find.text('Registro de falhas apagado.'), findsOneWidget);
      // A checagem do arquivo também é I/O real: dentro do runAsync.
      final depois =
          await tester.runAsync(() => lerFalhas(dir: dir));
      expect(depois, isEmpty);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });
  });
}

/// PNG 1x1 válido (transparente), em base64: usado para o widget test da
/// miniatura da foto do cupom precisar de um arquivo de imagem de verdade.
const String _pngUmPixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=';

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
