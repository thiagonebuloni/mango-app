import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mango/services/crash_log.dart';

/// Regras do log de falhas local: formatação, cortes de tamanho, rotação,
/// somatório de repetições e o ciclo gravar → ler → limpar.
///
/// Todos os testes usam um diretório temporário próprio (parâmetro `dir`),
/// então rodam sem `path_provider` e sem tocar no log real do app.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mango_falhas_test');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File arquivo() => File('${dir.path}/$kNomeArquivoFalhas');

  group('formatação', () {
    test('formatarQuando é fixo, sem depender de locale', () {
      expect(
        formatarQuando(DateTime(2026, 9, 29, 8, 15, 3)),
        '29/09/2026 08:15:03',
      );
    });

    test('cortarTexto corta e anota o que ficou de fora', () {
      expect(cortarTexto('curto', 10), 'curto');
      final cortado = cortarTexto('x' * 50, 10);
      expect(cortado, startsWith('x' * 10));
      expect(cortado, contains('(+40 caracteres cortados)'));
    });

    test('montarLinha → lerLinha preserva o evento inteiro', () {
      final original = EventoFalha(
        quando: DateTime(2026, 9, 29, 8, 15, 3),
        erro: 'boom',
        stack: '#0 pilha',
        contexto: 'ocr',
        repetido: 2,
      );
      final lido = lerLinha(montarLinha(original));
      expect(lido, isNotNull);
      expect(lido!.quando, original.quando);
      expect(lido.erro, 'boom');
      expect(lido.stack, '#0 pilha');
      expect(lido.contexto, 'ocr');
      expect(lido.repetido, 2);
    });

    test('linha inválida ou incompleta vira null, sem lançar', () {
      expect(lerLinha(''), isNull);
      expect(lerLinha('{não é json'), isNull);
      expect(lerLinha('["lista"]'), isNull);
      // Sem `erro` não é um evento, e `quando` inválido também não.
      expect(lerLinha('{"quando":"2026-09-29T08:15:03.000"}'), isNull);
      expect(lerLinha('{"quando":"??","erro":"x"}'), isNull);
    });

    test('montarLinha corta erro e pilha absurdos', () {
      final linha = montarLinha(EventoFalha(
        quando: DateTime(2026),
        erro: 'e' * 50000,
        stack: 's' * 50000,
      ));
      final lido = lerLinha(linha);
      expect(lido, isNotNull);
      expect(lido!.erro.length, lessThan(1300));
      expect(lido.stack!.length, lessThan(4100));
      expect(lido.erro, contains('caracteres cortados'));
      expect(lido.stack, contains('caracteres cortados'));
    });

    test('formatarEvento junta quando, contexto, repetição e pilha', () {
      final texto = formatarEvento(EventoFalha(
        quando: DateTime(2026, 9, 29, 8, 15, 3),
        erro: 'boom',
        stack: '#0 pilha',
        contexto: 'ocr',
        repetido: 3,
      ));
      expect(texto, contains('29/09/2026 08:15:03 · ocr (×3)'));
      expect(texto, contains('boom'));
      expect(texto, contains('Pilha de chamadas:'));
      expect(texto, contains('#0 pilha'));
    });

    test('rotacionarConteudo descarta os mais antigos, nunca o novo', () {
      final conteudo = ['uma', 'duas', 'três'].join('\n');
      final soCabemDuas = utf8.encode('duas\ntrês').length;
      expect(rotacionarConteudo(conteudo, soCabemDuas), 'duas\ntrês');
      // Nem a menor linha cabe: fica vazio.
      expect(rotacionarConteudo(conteudo, 2), '');
      expect(rotacionarConteudo('', 100), '');
    });
  });

  group('arquivo (dir de teste)', () {
    test('iniciar cria o arquivo; ciclo gravar → ler → limpar', () async {
      await iniciarLogDeFalhas(dir: dir);
      expect(arquivo().existsSync(), isTrue);

      await registrarFalha(
        Exception('boom'),
        StackTrace.current,
        contexto: 'ocr',
        dir: dir,
      );
      await aguardarEscritas();

      final eventos = await lerFalhas(dir: dir);
      expect(eventos, hasLength(1));
      expect(eventos.single.erro, contains('boom'));
      expect(eventos.single.contexto, 'ocr');
      expect(eventos.single.stack, isNotNull);

      await limparFalhas(dir: dir);
      expect(await lerFalhas(dir: dir), isEmpty);
      expect(arquivo().existsSync(), isFalse);
    });

    test('falhas iguais seguidas viram uma linha com ×N', () async {
      await registrarFalha('repetida', null, dir: dir);
      await registrarFalha('repetida', null, dir: dir);
      await registrarFalha('outra', null, dir: dir);
      await aguardarEscritas();

      final eventos = await lerFalhas(dir: dir);
      expect(eventos, hasLength(2));
      expect(eventos.first.erro, 'repetida');
      expect(eventos.first.repetido, 2);
      expect(eventos.last.erro, 'outra');
      expect(eventos.last.repetido, 1);
    });

    test('arquivo não passa do teto mesmo em erro em loop', () async {
      for (var i = 0; i < 80; i++) {
        await registrarFalha(
          'falha $i ${'x' * 900}',
          StackTrace.fromString('# pilha ${'y' * 3000}'),
          dir: dir,
        );
      }
      await aguardarEscritas();

      expect(arquivo().lengthSync(), lessThanOrEqualTo(kTetoFalhasBytes));

      final eventos = await lerFalhas(dir: dir);
      // A mais antiga saiu por rotação; a mais nova ficou.
      expect(eventos, isNotEmpty);
      expect(eventos.first.erro, isNot(contains('falha 0 ')));
      expect(eventos.last.erro, contains('falha 79 '));
    });

    test('registrarFalha nunca lança, mesmo sem lugar para gravar', () async {
      final bloqueio = File('${dir.path}/nao_e_dir')..writeAsStringSync('x');
      await registrarFalha('sem log', null, dir: Directory(bloqueio.path));
      // E o log normal continua funcionando logo depois.
      await registrarFalha('com log', null, dir: dir);
      await aguardarEscritas();
      expect((await lerFalhas(dir: dir)).single.erro, 'com log');
    });
  });
}
