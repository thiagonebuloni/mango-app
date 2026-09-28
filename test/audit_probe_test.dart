// Testes exploratórios da auditoria de segurança/robustez.
// Procuram crashes: estouro de pilha, null pointer, exceções não tratadas
// com entradas adversariais (limites numéricos, datas extremas, OCR malicioso).
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:mango/db/db.dart';
import 'package:mango/models/models.dart';
import 'package:mango/services/receipt_parser.dart';
import 'package:mango/state/providers.dart';
import 'package:mango/widgets/common.dart';

Expense _base({String estabelecimento = '', int valor = 1000,
    DateTime? data}) => Expense(
      valorCentavos: valor,
      dataHora: data ?? DateTime(2026, 3, 20),
      categoria: Category.lazer,
      forma: PaymentMethod.dinheiro,
      estabelecimento: estabelecimento,
    );

void main() {
  group('parseMoneyInput com entradas extremas', () {
    test('número gigante (400 dígitos) não lança: retorna null', () {
      Object? erro;
      int? result;
      try {
        result = parseMoneyInput('9' * 400);
      } catch (e) {
        erro = e;
      }
      // ignore: avoid_print
      print('400 dígitos -> result=$result erro=$erro');
      expect(erro, isNull,
          reason: 'parseMoneyInput não pode lançar com valor gigante');
      expect(result, isNull, reason: 'valor absurdo deve ser recusado');
    });

    test('valor acima do teto (1e12) é recusado sem lançar', () {
      final r = parseMoneyInput('9' * 30);
      // ignore: avoid_print
      print('30 dígitos -> $r');
      expect(r, isNull, reason: 'valor absurdo (> R\$ 1 tri) deve cair no '
          'mesmo caminho de "Informe o valor"');
    });

    test('fronteira do teto: 1e12 passa, acima cai', () {
      expect(parseMoneyInput('1000000000000'), isNotNull); // R$ 1 tri
      expect(parseMoneyInput('1000000000001'), isNull); // +1 centavo além
      expect(parseMoneyInput('999999999999'), isNotNull);
    });

    test('decimal gigante', () {
      Object? erro;
      try {
        parseMoneyInput('1,${'9' * 400}');
      } catch (e) {
        erro = e;
      }
      // ignore: avoid_print
      print('decimal gigante erro=$erro');
      expect(erro, isNull);
    });
  });

  group('expandirParcelas com datas extremas', () {
    test('data no limite do DateTime + 60 parcelas', () {
      Object? erro;
      try {
        expandirParcelas(_base(
            estabelecimento: 'LOJA 1/60', data: DateTime(275700, 1, 1)));
      } catch (e) {
        erro = e;
      }
      // ignore: avoid_print
      print('data extrema -> erro=$erro');
      expect(erro, isNull, reason: 'addMonths não pode estourar o range');
    });

    test('data negativa (ano < 0)', () {
      Object? erro;
      try {
        expandirParcelas(_base(
            estabelecimento: 'LOJA 1/60', data: DateTime(-5000, 1, 1)));
      } catch (e) {
        erro = e;
      }
      // ignore: avoid_print
      print('ano negativo -> erro=$erro');
      expect(erro, isNull);
    });

    test('60 parcelas: quantidade e soma exata', () {
      final l = expandirParcelas(_base(estabelecimento: 'LOJA 1/60'));
      expect(l.length, 60);
      final soma = l.fold<int>(0, (a, b) => a + b.valorCentavos);
      expect(soma, 1000, reason: 'soma das parcelas deve bater com o total');
    });
  });

  group('ReceiptParser com texto OCR adversarial', () {
    test('linhas gigantes e sem quebras', () {
      final text = 'A' * 200000;
      final r = ReceiptParser.parse(text);
      expect(r.textoOcr.length, text.length);
    });

    test('sequências que emulam ReDoS', () {
      final inputs = [
        '1' * 50000,
        '1.' * 20000,
        '12' * 20000,
        'a/' * 20000,
        '1/2' * 10000,
        '\n' * 50000,
        'R\$ 1,00' * 5000,
        'x/y ' * 10000,
        '1 de ' * 10000,
      ];
      for (final i in inputs) {
        final sw = Stopwatch()..start();
        ReceiptParser.parse(i);
        ReceiptParser.parcelas(i);
        sw.stop();
        // ignore: avoid_print
        print('input "${i.substring(0, 10)}..." len=${i.length} -> '
            '${sw.elapsedMilliseconds}ms');
        expect(sw.elapsedMilliseconds, lessThan(2000),
            reason: 'possível ReDoS: parsing muito lento');
      }
    });

    test('parseParcelaSuffix não quebra', () {
      for (final s in [
        'LOJA 0/0', 'LOJA 999/999', 'LOJA 1/61',
        'LOJA 00000000000000000001/60',
        'LOJA 1 / 60', 'LOJA -1/60', '  ', '',
      ]) {
        final p = ReceiptParser.parseParcelaSuffix(s);
        // ignore: avoid_print
        print('suffix "$s" -> $p');
      }
    });
  });

  group('CsvBackup.import com entradas maliciosas', () {
    test('campos com aspas e valores extremos', () {
      final lines = [
        '# MANGO_BACKUP v2',
        '# PERFIL;nome="${'N' * 100000}";avatar=😀;cor=4294967295;tema=claro',
        'despesa;100;2026-03-20T12:00:00.000;lazer;dinheiro;'
            '"${'D' * 100000}";"ESTAB";manual',
        'despesa;100;data-invalida;lazer;dinheiro;d;e;manual',
        'despesa;0;2026-03-20T12:00:00.000;lazer;dinheiro;d;e;manual',
        'despesa;-100;2026-03-20T12:00:00.000;lazer;dinheiro;d;e;manual',
        'despesa;99999999999999999999999;2026-03-20T12:00:00.000;lazer;'
            'dinheiro;d;e;manual',
        '"aspas inabaláveis \'" "',
        'tipo;valor;data_hora;categoria;forma;descricao;estabelecimento;origem',
      ];
      final r = CsvBackup.import(lines.join('\n'));
      // ignore: avoid_print
      print('import: ${r.expenses.length} gastos, ${r.skipped} pulados, '
          'perfil=${r.perfil?.nome}');
      expect(r.expenses, isNotEmpty);
      // A4: o nome de 100000 caracteres entra cortado no limite da tela de
      // perfil; a cor 0xFFFFFFFF (opaca) continua valendo.
      expect(r.perfil?.nome, 'N' * UserProfile.nomeMaxLength);
      expect(r.perfil?.corFundo, 0xFFFFFFFF);
    });

    test('perfil com cor inválida não quebra', () {
      for (final cor in [
        'abc', '-1', '999999999999999999999999', '', '4294967296', '0',
      ]) {
        final csv = '# MANGO_BACKUP v2\n# PERFIL;nome=X;avatar=Y;cor=$cor;'
            'tema=claro\ntipo;valor;data_hora;categoria;forma;descricao;'
            'estabelecimento;origem';
        final r = CsvBackup.import(csv);
        // ignore: avoid_print
        print('cor="$cor" -> perfil.cor=${r.perfil?.corFundo}');
        // A4: vira o padrão e o fundo segue visível (alpha 255) — valores
        // fora de 32 bits ou transparentes deixariam a tela "vazada".
        expect(
          r.perfil?.corFundo,
          UserProfile.corFundoInicialPadrao,
          reason: 'cor="$cor"',
        );
        expect(Color(r.perfil!.corFundo).a, 1.0, reason: 'cor="$cor"');
      }
    });

    test('utf8 binário inválido: documenta comportamento', () {
      final bytes = [0xFF, 0xFE, 0x00, 0xC3, 0x28];
      Object? erro;
      try {
        utf8.decode(bytes);
      } catch (e) {
        erro = e;
      }
      // O import na UI lê com try/catch (common.dart / first_run_screen).
      // ignore: avoid_print
      print('utf8 inválido lança: ${erro.runtimeType}');
    });
  });

  group('chaveUnica não colide com | nos campos (B6)', () {
    Expense e({String descricao = '', String estabelecimento = ''}) =>
        Expense(
          valorCentavos: 1000,
          dataHora: DateTime(2026, 3, 20, 12),
          categoria: Category.lazer,
          forma: PaymentMethod.dinheiro,
          descricao: descricao,
          estabelecimento: estabelecimento,
        );

    test('desc "a" + estab "b|c" ≠ desc "a|b" + estab "c"', () {
      final a = e(descricao: 'a', estabelecimento: 'b|c');
      final b = e(descricao: 'a|b', estabelecimento: 'c');
      // Sob o esquema antigo (join('|') puro) as duas chaves eram idênticas
      // e o mergeAll descartaria um lançamento legítimo como "duplicata".
      expect(a.chaveUnica, isNot(b.chaveUnica));
    });

    test('desc "|a" + estab "b" ≠ desc "" + estab "a|b"', () {
      // Outro par que colidia sob o join('|') puro antigo.
      final a = e(descricao: '|a', estabelecimento: 'b');
      final b = e(descricao: '', estabelecimento: 'a|b');
      expect(a.chaveUnica, isNot(b.chaveUnica));
    });

    test('campos idênticos continuam com a mesma chave', () {
      final a = e(descricao: 'a|b', estabelecimento: 'LOJA X');
      final b = e(descricao: 'a|b', estabelecimento: 'LOJA X');
      expect(a.chaveUnica, b.chaveUnica);
      expect(e(descricao: 'a').chaveUnica, isNot(e(descricao: 'a2').chaveUnica));
    });
  });

  group('Limites do import de CSV (A2)', () {
    test('validateImportSize aceita o teto e recusa 1 byte acima', () {
      expect(CsvBackup.validateImportSize(0), isNull);
      expect(CsvBackup.validateImportSize(CsvBackup.maxBytes), isNull);
      final recusa = CsvBackup.validateImportSize(CsvBackup.maxBytes + 1);
      expect(recusa, isNotNull);
      expect(recusa, contains('16 MB'));
      // Tamanhos "quebrados" ganham uma casa decimal em pt-BR.
      expect(
        CsvBackup.validateImportSize(CsvBackup.maxBytes + (512 * 1024)),
        contains('16,5 MB'),
      );
      // ignore: avoid_print
      print('recusa: $recusa');
    });

    test('texto gigante é recusado sem travar o app', () {
      final gigante = 'x' * (CsvBackup.maxBytes + 1);
      Object? erro;
      try {
        CsvBackup.import(gigante);
      } catch (e) {
        erro = e;
      }
      // Antes da correção: 16 MiB de texto viravam String + lista de linhas
      // e o app morria por falta de memória (OOM), sem aviso ao usuário.
      expect(erro, isA<CsvImportException>());
      expect((erro as CsvImportException).message, contains('16 MB'));
    });

    test('arquivo de linhas minúsculas (sem fim) também é recusado', () {
      final muitasLinhas = 'a\n' * (CsvBackup.maxLines + 1);
      expect(
        () => CsvBackup.import(muitasLinhas),
        throwsA(isA<CsvImportException>()),
      );
      // No limite ainda passa: linhas inválidas viram "ignoradas", sem erro.
      expect(CsvBackup.import('a\n' * CsvBackup.maxLines).expenses, isEmpty);
    });

    test('lerBackupCsv remonta os blocos e sobrevive a UTF-8 cortado', () async {
      final csv = CsvBackup.export([_base(estabelecimento: 'PADARIA AÇÃO')]);
      final bytes = utf8.encode(csv);
      final corte = bytes.indexWhere((b) => b >= 0x80) + 1;
      expect(corte, greaterThan(0), reason: 'teste precisa de acento no CSV');
      final texto = await lerBackupCsv(
        Stream.fromIterable([bytes.sublist(0, corte), bytes.sublist(corte)]),
      );
      expect(texto, csv);
      final lancamento = CsvBackup.import(texto).expenses.single;
      expect(lancamento.estabelecimento, 'PADARIA AÇÃO');
    });

    test('lerBackupCsv aborta cedo num fluxo sem fim', () async {
      var blocos = 0;
      Stream<List<int>> semFim() async* {
        while (true) {
          blocos++;
          yield Uint8List(1024 * 1024);
        }
      }

      await expectLater(
        lerBackupCsv(semFim()),
        throwsA(isA<CsvImportException>()),
      );
      // Para no teto em vez de ler o "arquivo" inteiro (que não termina).
      final teto = CsvBackup.maxBytes ~/ (1024 * 1024);
      // ignore: avoid_print
      print('blocos lidos até abortar: $blocos (teto $teto)');
      expect(blocos, lessThanOrEqualTo(teto + 2));
    });

    test('fluxo vazio vira texto vazio, sem lançar', () async {
      final texto = await lerBackupCsv(Stream<List<int>>.empty());
      expect(texto, isEmpty);
      expect(CsvBackup.import(texto).expenses, isEmpty);
    });
  });

  // A4: o CSV é a porta de entrada de nome/avatar/cor do perfil — arquivo
  // editado à mão (ou de outra pessoa) não pode deixar a tela inicial lenta
  // (nome gigante) nem invisível (cor transparente).
  group('Limites do perfil vindo do CSV (A4)', () {
    String csvDe(String campos) =>
        '${CsvBackup.backupMarker}\n# PERFIL;$campos\n${CsvBackup.header}';

    UserProfile perfilDe(String campos) =>
        CsvBackup.import(csvDe(campos)).perfil!;

    test('nome gigante entra cortado no limite da tela de perfil', () {
      final p = perfilDe('nome="${'N' * 100000}";avatar=😀;cor=4280171103');
      expect(p.nome, 'N' * UserProfile.nomeMaxLength);
    });

    test('nome com caracteres de controle vira texto limpo', () {
      final p = perfilDe(
        'nome="  Ana\t\u0007Souza\u0001";avatar=😀;cor=4280171103',
      );
      expect(p.nome, 'Ana Souza');
    });

    test('corte do nome não parte um emoji no meio', () {
      // Cada 🐸 ocupa 2 unidades UTF-16: cortar por unidades deixaria um
      // par substituto solto (caractere inválido no meio do nome).
      final p = perfilDe('nome="${'🐸' * 40}";avatar=😀;cor=4280171103');
      expect(p.nome.runes.length, UserProfile.nomeMaxLength);
      expect(p.nome.length, UserProfile.nomeMaxLength * 2);
      expect(p.nome, '🐸' * UserProfile.nomeMaxLength);
    });

    test('cor transparente ou fora de 32 bits vira o padrão opaco', () {
      for (final cor in ['0', '4294967296', '2130771967', '-1', 'abc', '']) {
        final p = perfilDe('nome=Ana;avatar=😀;cor=$cor');
        expect(
          p.corFundo,
          UserProfile.corFundoInicialPadrao,
          reason: 'cor=$cor',
        );
        expect(Color(p.corFundo).a, 1.0, reason: 'cor=$cor ficou invisível');
      }
    });

    test('cor opaca válida continua valendo', () {
      for (final cor in ['4280171103', '4294967295', '4278252193']) {
        expect(perfilDe('nome=Ana;cor=$cor').corFundo, int.parse(cor));
      }
    });

    test('avatar gigante entra cortado', () {
      final p = perfilDe('nome=Ana;avatar="${'😀' * 500}";cor=4280171103');
      expect(p.avatar.runes.length, UserProfile.avatarMaxLength);
    });

    test('perfil dentro dos limites continua com round-trip exato', () {
      const original = UserProfile(
        nome: 'Ana Souza',
        avatar: '🦊',
        corFundo: 0xFF1E3A5F,
        temaClaro: true,
      );
      final lido = CsvBackup.import(
        CsvBackup.export([_base()], perfil: original),
      ).perfil!;
      expect(lido.nome, original.nome);
      expect(lido.avatar, original.avatar);
      expect(lido.corFundo, original.corFundo);
      expect(lido.temaClaro, isTrue);
    });
  });
}

