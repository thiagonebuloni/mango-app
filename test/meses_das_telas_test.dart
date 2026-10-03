// Período de cada tela: Gastos e Cartões guardam o mês **um do outro** e o
// mantêm ao trocar de aba e ao sair e voltar da navegação.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:mango/l10n/app_locale.dart';
import 'package:mango/l10n/l10n_format.dart';
import 'package:mango/models/models.dart';
import 'package:mango/screens/cartoes_screen.dart';
import 'package:mango/screens/home_screen.dart';
import 'package:mango/screens/root_nav.dart';
import 'package:mango/state/providers.dart';

const _cartao = CartaoCredito(
  id: 1,
  banco: 'Nubank',
  bandeira: BandeiraCartao.mastercard,
  nome: 'Viagem',
  diaFechamento: 20,
  diaPagamento: 27,
);

class _FakeExpensesNotifier extends ExpensesNotifier {
  @override
  Future<List<Expense>> build() async => const [];
}

class _FakeReportsNotifier extends ExpensesForReports {
  @override
  Future<List<Expense>> build() async => const [];
}

class _FakeCartoesNotifier extends CartoesNotifier {
  @override
  Future<List<CartaoCredito>> build() async => const [_cartao];
}

class _FakeProfileNotifier extends ProfileNotifier {
  @override
  Future<UserProfile?> build() async =>
      const UserProfile(nome: 'Ana', avatar: '🦊', corFundo: 0xFFE3F2FD);
}

/// Overrides fixos das telas: a MESMA lista é reutilizada nos vários
/// `pumpWidget` — instâncias novas recriariam o estado dos provedores e
/// apagariam o mês escolhido.
final _overridesDasTelas = [
  expensesProvider.overrideWith(_FakeExpensesNotifier.new),
  expensesForReportsProvider.overrideWith(_FakeReportsNotifier.new),
  cartoesProvider.overrideWith(_FakeCartoesNotifier.new),
  profileProvider.overrideWith(_FakeProfileNotifier.new),
];

Future<void> _pump(WidgetTester tester, {Widget? home}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overridesDasTelas,
      child: MaterialApp(
        home: home ?? const RootNav(),
        locale: const Locale('pt', 'BR'),
        supportedLocales: supportedAppLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Rótulo do mês no locale do teste ("outubro 2026"). A tela de Gastos
/// capitaliza a inicial do mês; a de Cartões mostra como o intl entrega.
String _rotulo(DateTime mes, {bool maiuscula = false}) {
  final texto = formatDate(mes, (p) => p.monthYear, const Locale('pt', 'BR'));
  return maiuscula ? '${texto[0].toUpperCase()}${texto.substring(1)}' : texto;
}

/// [alvo] restrito à tela de Gastos.
Finder _emGastos(Finder alvo) =>
    find.descendant(of: find.byType(HomeScreen), matching: alvo);

/// [alvo] restrito à tela de Cartões.
Finder _emCartoes(Finder alvo) =>
    find.descendant(of: find.byType(CartoesScreen), matching: alvo);

/// Toca na aba da barra de navegação inferior.
Future<void> _irParaAba(WidgetTester tester, String aba) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(aba)),
  );
  await tester.pumpAndSettle();
}

Finder _botaoMesAnterior(Finder Function(Finder) escopo) =>
    escopo(find.byTooltip('Mês anterior'));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    await initializeDateFormatting('en_US');
  });

  group('mês das telas', () {
    testWidgets('Gastos e Cartões guardam períodos independentes', (
      tester,
    ) async {
      await _pump(tester);

      final agora = DateTime.now();
      final mesAtual = DateTime(agora.year, agora.month);
      final mesPassado = DateTime(mesAtual.year, mesAtual.month - 1);
      final mesMaisAntigo = DateTime(mesAtual.year, mesAtual.month - 2);

      // As telas começam no mês corrente.
      expect(
        _emGastos(find.text(_rotulo(mesAtual, maiuscula: true))),
        findsOneWidget,
      );

      // Volta um mês só na Gastos.
      await tester.tap(_botaoMesAnterior(_emGastos));
      await tester.pumpAndSettle();
      expect(
        _emGastos(find.text(_rotulo(mesPassado, maiuscula: true))),
        findsOneWidget,
      );

      // Cartões nem saiu do mês corrente: o período é de cada tela.
      await _irParaAba(tester, 'Cartões');
      expect(_emCartoes(find.text(_rotulo(mesAtual))), findsOneWidget);
      expect(_emCartoes(find.text(_rotulo(mesPassado))), findsNothing);

      // Recua dois meses em Cartões...
      await tester.tap(_botaoMesAnterior(_emCartoes));
      await tester.pumpAndSettle();
      await tester.tap(_botaoMesAnterior(_emCartoes));
      await tester.pumpAndSettle();
      expect(_emCartoes(find.text(_rotulo(mesMaisAntigo))), findsOneWidget);

      // ...e a Gastos continua exatamente onde estava.
      await _irParaAba(tester, 'Gastos');
      expect(
        _emGastos(find.text(_rotulo(mesPassado, maiuscula: true))),
        findsOneWidget,
      );
      expect(
        _emGastos(find.text(_rotulo(mesMaisAntigo, maiuscula: true))),
        findsNothing,
      );
      expect(
        _emGastos(find.text(_rotulo(mesAtual, maiuscula: true))),
        findsNothing,
      );
    });

    testWidgets('período escolhido sobrevive a sair e voltar das telas', (
      tester,
    ) async {
      await _pump(tester);

      final agora = DateTime.now();
      final mesAtual = DateTime(agora.year, agora.month);
      final mesPassado = DateTime(mesAtual.year, mesAtual.month - 1);
      final mesMaisAntigo = DateTime(mesAtual.year, mesAtual.month - 2);

      // Escolhe um período em cada tela.
      await tester.tap(_botaoMesAnterior(_emGastos));
      await tester.pumpAndSettle();
      await _irParaAba(tester, 'Cartões');
      await tester.tap(_botaoMesAnterior(_emCartoes));
      await tester.pumpAndSettle();
      await tester.tap(_botaoMesAnterior(_emCartoes));
      await tester.pumpAndSettle();

      // Sai da navegação (a tela é destruída)...
      await _pump(tester, home: const SizedBox());
      // ...e entra de novo.
      await _pump(tester);

      // Cada tela continua no seu período.
      expect(
        _emGastos(find.text(_rotulo(mesPassado, maiuscula: true))),
        findsOneWidget,
      );
      expect(
        _emGastos(find.text(_rotulo(mesAtual, maiuscula: true))),
        findsNothing,
      );

      await _irParaAba(tester, 'Cartões');
      expect(_emCartoes(find.text(_rotulo(mesMaisAntigo))), findsOneWidget);
      expect(_emCartoes(find.text(_rotulo(mesAtual))), findsNothing);
    });
  });
}
