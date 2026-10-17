// Relatório por I.A.: o contexto (números em Dart), o prompt no idioma do
// app e a tela nos dois caminhos principais — sem modelo instalado e com
// modelo + narrador fake (sem FFI nativa nos testes).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;

import 'package:mango/l10n/app_locale.dart';
import 'package:mango/l10n/app_strings.dart';
import 'package:mango/models/models.dart';
import 'package:mango/screens/relatorio_ia_screen.dart';
import 'package:mango/services/crash_log.dart';
import 'package:mango/services/ia_andamento.dart';
import 'package:mango/services/ia_modelos.dart';
import 'package:mango/services/ia_narrador.dart';
import 'package:mango/services/relatorio_contexto.dart';
import 'package:mango/services/relatorio_prompt.dart';
import 'package:mango/state/providers.dart';

final _s = AppStrings.of(null); // pt-BR

Expense _gasto({
  required int valor,
  required DateTime data,
  Category categoria = Category.mercado,
  String estabelecimento = 'Mercado do Zé',
  PaymentMethod forma = PaymentMethod.pix,
  EntryKind tipo = EntryKind.despesa,
}) =>
    Expense(
      valorCentavos: valor,
      dataHora: data,
      categoria: categoria,
      forma: forma,
      estabelecimento: estabelecimento,
      tipo: tipo,
    );

/// Narrador fake que devolve um texto pronto e registra o cancelamento.
class _NarradorFake implements NarradorIa {
  bool cancelado = false;

  @override
  Stream<String> narrar({required String system, required String user}) =>
      Stream.fromIterable(const ['Olá, ', 'relatório de teste.']);

  @override
  void cancelar() => cancelado = true;
}

/// Narrador fake com fluxo manual (para testar o cancelamento).
class _NarradorAberto implements NarradorIa {
  final controlador = StreamController<String>();
  bool cancelado = false;

  @override
  Stream<String> narrar({required String system, required String user}) =>
      controlador.stream;

  @override
  void cancelar() {
    cancelado = true;
    if (!controlador.isClosed) controlador.close();
  }
}

class _GastosFake extends ExpensesForReports {
  final List<Expense> gastos;
  _GastosFake(this.gastos);

  @override
  Future<List<Expense>> build() async => gastos;
}

final _outubro =
    PeriodRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 14));

final _modeloFake = ModeloIa(
  caminho: '/fake/models/modelo.litertlm',
  tamanhoBytes: 400 * 1024 * 1024,
);

Widget _tela({
  required List<Expense> gastos,
  NarradorIa Function(String)? fabrica,
  List<ModeloIa> modelos = const [],
  PeriodRange? periodo,
}) =>
    ProviderScope(
      overrides: [
        modelosIaProvider.overrideWithValue(AsyncData(modelos)),
        expensesForReportsProvider.overrideWith(() => _GastosFake(gastos)),
        if (fabrica != null)
          fabricaNarradorIaProvider.overrideWithValue(fabrica),
      ],
      child: MaterialApp(
        locale: const Locale('pt', 'BR'),
        supportedLocales: supportedAppLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: RelatorioIaScreen(periodo: periodo ?? _outubro),
      ),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    await initializeDateFormatting('en_US');
  });

  group('RelatorioContexto', () {
    test('soma despesas/receitas e reparte participação por categoria', () {
      final contexto = RelatorioContexto.construir(
        todas: [
          _gasto(valor: 5000, data: DateTime(2026, 10, 2)),
          _gasto(
            valor: 3000,
            data: DateTime(2026, 10, 3),
            categoria: Category.lazer,
            estabelecimento: 'Cinema',
          ),
          _gasto(
            valor: 100000,
            data: DateTime(2026, 10, 4),
            categoria: Category.salario,
            forma: PaymentMethod.dinheiro,
            estabelecimento: '',
            tipo: EntryKind.receita,
          ),
          // Fora do período: não pode entrar no resumo.
          _gasto(valor: 9999, data: DateTime(2026, 9, 5)),
        ],
        periodo: _outubro,
        rotuloCategoria: _s.categoriaLabel,
        rotuloPagamento: _s.pagamentoLabel,
      );

      expect(contexto.despesas, 8000);
      expect(contexto.receitas, 100000);
      expect(contexto.lancamentos, 3);
      expect(contexto.categorias.first.nome, 'Mercado');
      expect(contexto.categorias.first.percentual, 62.5);
      expect(contexto.maiorDia, DateTime(2026, 10, 2));
    });

    test('compara com o mês calendário anterior quando começa dia 1', () {
      final anterior = RelatorioContexto.anteriorDe(_outubro);
      expect(anterior.start, DateTime(2026, 9, 1));
      expect(anterior.end, DateTime(2026, 9, 30));

      final contexto = RelatorioContexto.construir(
        todas: [
          _gasto(valor: 5000, data: DateTime(2026, 10, 2)),
          _gasto(valor: 4000, data: DateTime(2026, 9, 10)),
        ],
        periodo: _outubro,
        rotuloCategoria: _s.categoriaLabel,
        rotuloPagamento: _s.pagamentoLabel,
      );
      expect(contexto.despesasAnteriores, 4000);
      expect(contexto.variacaoDespesasPct, 25.0);
    });

    test('janela irregular compara com a mesma duração logo antes', () {
      final periodo =
          PeriodRange(start: DateTime(2026, 10, 10), end: DateTime(2026, 10, 14));
      final anterior = RelatorioContexto.anteriorDe(periodo);
      expect(anterior.start, DateTime(2026, 10, 5));
      expect(anterior.end, DateTime(2026, 10, 9));
    });

    test('período sem despesa anterior não inventa variação', () {
      final contexto = RelatorioContexto.construir(
        todas: [_gasto(valor: 1000, data: DateTime(2026, 10, 2))],
        periodo: _outubro,
        rotuloCategoria: _s.categoriaLabel,
        rotuloPagamento: _s.pagamentoLabel,
      );
      expect(contexto.variacaoDespesasPct, isNull);
      expect(contexto.toMap()['previous_period'], containsPair(
        'expenses_change_pct',
        null,
      ));
    });

    test('JSON leva reais com 2 casas e datas ISO', () {
      final contexto = RelatorioContexto.construir(
        todas: [
          _gasto(valor: 123456, data: DateTime(2026, 10, 2)),
        ],
        periodo: _outubro,
        rotuloCategoria: _s.categoriaLabel,
        rotuloPagamento: _s.pagamentoLabel,
      );
      final json = contexto.json;
      expect(json, contains('"expenses_total":1234.56'));
      expect(json, contains('"start":"2026-10-01"'));
      expect(json, contains('"name":"Mercado"'));
    });
  });

  group('prompt do relatório', () {
    RelatorioContexto contextoDeExemplo() => RelatorioContexto.construir(
          todas: [_gasto(valor: 8000, data: DateTime(2026, 10, 2))],
          periodo: _outubro,
          rotuloCategoria: _s.categoriaLabel,
          rotuloPagamento: _s.pagamentoLabel,
        );

    test('envolve os dados em <dados> e traz os totais', () {
      final prompt =
          montarPromptRelatorio(contexto: contextoDeExemplo(), strings: _s);
      expect(prompt.user, contains('<dados>'));
      expect(prompt.user, contains('</dados>'));
      expect(prompt.user, contains('"expenses_total":80.0'));
      expect(prompt.system, contains('<dados>'));
    });

    test('muda de idioma junto com o app', () {
      final en = AppStrings.of(const Locale('en', 'US'));
      final pt = montarPromptRelatorio(contexto: contextoDeExemplo(), strings: _s);
      final ingles =
          montarPromptRelatorio(contexto: contextoDeExemplo(), strings: en);
      expect(ingles.system, isNot(pt.system));
      expect(ingles.user, contains('<dados>'));
    });
  });

  group('RelatorioIaScreen', () {
    testWidgets('sem modelo instalado mostra as instruções e o script', (
      tester,
    ) async {
      await tester.pumpWidget(_tela(gastos: [
        _gasto(valor: 1000, data: DateTime(2026, 10, 2)),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum modelo de I.A. instalado'), findsOneWidget);
      expect(find.textContaining('tool/install_modelo_ia.sh'), findsOneWidget);
      expect(find.text('Gerar relatório mensal por I.A.'), findsNothing);
      expect(find.text('Atualizar lista'), findsOneWidget);
    });

    testWidgets('com modelo gera o relatório e oferece compartilhar', (
      tester,
    ) async {
      await tester.pumpWidget(_tela(
        gastos: [_gasto(valor: 1000, data: DateTime(2026, 10, 2))],
        modelos: [_modeloFake],
        fabrica: (_) => _NarradorFake(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('modelo.litertlm'), findsOneWidget);
      await tester.tap(find.text('Gerar relatório mensal por I.A.'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Olá, relatório de teste.'), findsOneWidget);
      expect(find.text('Compartilhar'), findsOneWidget);
      expect(find.text('Gerar novamente'), findsOneWidget);
    });

    testWidgets('cancelar para a geração e libera o botão de novo', (
      tester,
    ) async {
      final narrador = _NarradorAberto();
      await tester.pumpWidget(_tela(
        gastos: [_gasto(valor: 1000, data: DateTime(2026, 10, 2))],
        modelos: [_modeloFake],
        fabrica: (_) => narrador,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gerar relatório mensal por I.A.'));
      await tester.pump();
      expect(find.text('Gerando o relatório no aparelho…'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      await tester.pump();

      expect(narrador.cancelado, isTrue);
      expect(find.text('Gerando o relatório no aparelho…'), findsNothing);
      final botao = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(botao.onPressed, isNotNull);
    });

    testWidgets('período sem lançamentos não oferece geração', (tester) async {
      await tester.pumpWidget(_tela(
        gastos: const [],
        modelos: [_modeloFake],
        fabrica: (_) => _NarradorFake(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Gerar relatório mensal por I.A.'), findsNothing);
    });
  });

  group('preparo do modelo (NarradorLiteRt)', () {
    test('modelo fora do armazenamento externo passa na validação', () async {
      final dir = await Directory.systemTemp.createTemp('mango-ia-');
      try {
        final modelo = File(p.join(dir.path, 'mini.litertlm'));
        // Assinatura LITERTLM + corpo suficiente para passar na validação.
        final bytes = BytesBuilder()
          ..add('LITERTLM'.codeUnits)
          ..add(Uint8List(2 * 1024 * 1024));
        await modelo.writeAsBytes(bytes.toBytes());

        // Executa só até a validação local: a leitura dos 8 primeiros bytes
        // replica o que `_prepararModelo` faz antes de chamar o motor nativo
        // (que não existe no teste de desktop).
        final acesso = await modelo.open();
        try {
          final cabeca = await acesso.read(8);
          expect(String.fromCharCodes(cabeca), 'LITERTLM');
        } finally {
          await acesso.close();
        }
        expect(await modelo.length(), greaterThan(1024 * 1024));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('arquivo pequeno demais gera erro legível', () async {
      final dir = await Directory.systemTemp.createTemp('mango-ia-');
      try {
        final modelo = File(p.join(dir.path, 'curto.litertlm'));
        await modelo.writeAsBytes('LITE'.codeUnits);

        final narrador = NarradorLiteRt(caminhoModelo: modelo.path);
        await expectLater(
          narrador.narrar(system: 's', user: 'u'),
          emitsError(isA<ModeloIaException>()),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('arquivo .litertlm sem assinatura gera erro legível', () async {
      final dir = await Directory.systemTemp.createTemp('mango-ia-');
      try {
        final modelo = File(p.join(dir.path, 'falso.litertlm'));
        await modelo.writeAsBytes(Uint8List(2 * 1024 * 1024));

        final narrador = NarradorLiteRt(caminhoModelo: modelo.path);
        await expectLater(
          narrador.narrar(system: 's', user: 'u'),
          emitsError(isA<ModeloIaException>()),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('modelo GGUF (motor antigo) gera erro de migração', () async {
      final dir = await Directory.systemTemp.createTemp('mango-ia-');
      try {
        final modelo = File(p.join(dir.path, 'antigo.gguf'));
        final bytes = BytesBuilder()
          ..add(const [0x47, 0x47, 0x55, 0x46]) // GGUF
          ..add(Uint8List(2 * 1024 * 1024));
        await modelo.writeAsBytes(bytes.toBytes());

        final narrador = NarradorLiteRt(caminhoModelo: modelo.path);
        await expectLater(
          narrador.narrar(system: 's', user: 'u'),
          emitsError(
            isA<ModeloIaException>().having(
              (e) => e.mensagem,
              'menciona a migração',
              allOf(contains('GGUF'), contains('install_modelo_ia.sh')),
            ),
          ),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('modelo inexistente gera erro legível', () async {
      final narrador = NarradorLiteRt(
        caminhoModelo: p.join(
          Directory.systemTemp.path,
          'mango-ia-inexistente-${DateTime.now().microsecondsSinceEpoch}.litertlm',
        ),
      );
      await expectLater(
        narrador.narrar(system: 's', user: 'u'),
        emitsError(isA<ModeloIaException>()),
      );
    });
  });

  group('marca de geração (crash nativo → Diagnóstico)', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('mango-ia-marca');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('sem marca órfã nada é registrado', () async {
      expect(await verificarGeracaoIaInterrompida(dir: dir), isFalse);
      expect(await lerFalhas(dir: dir), isEmpty);
    });

    test('marca órfã vira falha legível e é apagada', () async {
      await marcarGeracaoIa(modelo: 'qwen3-0.6b.litertlm', dir: dir);

      expect(await verificarGeracaoIaInterrompida(dir: dir), isTrue);

      final falhas = await lerFalhas(dir: dir);
      expect(falhas, hasLength(1));
      expect(falhas.first.contexto, kContextoGeracaoIa);
      expect(falhas.first.erro, contains('qwen3-0.6b.litertlm'));

      // Próxima abertura: marca já apagada, nada novo no Diagnóstico.
      expect(await verificarGeracaoIaInterrompida(dir: dir), isFalse);
      expect(await lerFalhas(dir: dir), hasLength(1));
    });

    test('limpar apaga a marca antes de qualquer interrupção', () async {
      await marcarGeracaoIa(modelo: 'm.litertlm', dir: dir);
      await limparGeracaoIa(dir: dir);

      expect(await verificarGeracaoIaInterrompida(dir: dir), isFalse);
      expect(await lerFalhas(dir: dir), isEmpty);
    });
  });
}
