// Foto do cupom: cópia para os documentos do app (a foto sobrevive à limpeza
// do cache do sistema, que era o furo da versão que guardava o caminho do
// `image_picker` no banco) e as travas de segurança das exclusões.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mango/services/receipt_photo.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mango_foto_cupom_');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  /// Cria um arquivo qualquer (conteúdo não importa para estes testes).
  File criarArquivo(String caminho, {List<int> bytes = const [1, 2, 3]}) {
    final arquivo = File(caminho);
    arquivo.createSync(recursive: true);
    arquivo.writeAsBytesSync(bytes);
    return arquivo;
  }

  group('salvarFotoCupom', () {
    test('copia a foto para os documentos com nome do app', () async {
      final origem = criarArquivo(
        p.join(tmp.path, 'cache', 'image_picker1234.jpg'),
        bytes: const [7, 8, 9],
      );
      final destino = Directory(p.join(tmp.path, 'documentos'));

      final salvo = await salvarFotoCupom(origem, destino);

      expect(File(salvo).existsSync(), isTrue);
      expect(File(salvo).readAsBytesSync(), const [7, 8, 9]);
      expect(p.basename(salvo), startsWith(kPrefixoFotoCupom));
      expect(p.dirname(salvo), destino.path);
      // A origem continua intacta: quem decide apagar é o chamador.
      expect(origem.existsSync(), isTrue);
    });

    test('cria o diretório de destino quando ele não existe', () async {
      final origem = criarArquivo(p.join(tmp.path, 'cupom.jpg'));
      final destino = Directory(p.join(tmp.path, 'ainda', 'nao', 'existe'));

      final salvo = await salvarFotoCupom(origem, destino);

      expect(File(salvo).existsSync(), isTrue);
    });

    test('duas cópias não se sobrescrevem', () async {
      final origem =
          criarArquivo(p.join(tmp.path, 'cupom.jpg'), bytes: const [1]);
      final destino = Directory(p.join(tmp.path, 'documentos'));

      final primeira = await salvarFotoCupom(origem, destino);
      final segunda = await salvarFotoCupom(origem, destino);

      expect(primeira, isNot(segunda));
      expect(File(primeira).existsSync(), isTrue);
      expect(File(segunda).existsSync(), isTrue);
    });

    test('origem sem extensão vira .jpg', () async {
      final origem = criarArquivo(p.join(tmp.path, 'sem_extensao'));

      final salvo =
          await salvarFotoCupom(origem, Directory(p.join(tmp.path, 'doc')));

      expect(p.extension(salvo), '.jpg');
    });
  });

  group('fotoCupomPodeSerApagada', () {
    test('aceita só foto do app dentro do diretório', () {
      final dir = Directory(p.join(tmp.path, 'documentos'));

      expect(
        fotoCupomPodeSerApagada(
            p.join(dir.path, '${kPrefixoFotoCupom}1.jpg'), dir),
        isTrue,
      );
      // Outros arquivos do app (foto do avatar, banco) não são foto de cupom.
      expect(
        fotoCupomPodeSerApagada(p.join(dir.path, 'avatar_1.jpg'), dir),
        isFalse,
      );
      // Fora dos documentos: caminho vindo de um backup editado à mão.
      expect(
        fotoCupomPodeSerApagada(
            p.join(tmp.path, '${kPrefixoFotoCupom}1.jpg'), dir),
        isFalse,
      );
      expect(fotoCupomPodeSerApagada('/etc/passwd', dir), isFalse);
      // `..` não escapa da checagem.
      expect(
        fotoCupomPodeSerApagada(
            p.join(dir.path, '..', '${kPrefixoFotoCupom}1.jpg'), dir),
        isFalse,
      );
      expect(fotoCupomPodeSerApagada('', dir), isFalse);
    });
  });

  group('apagarFotoCupom', () {
    test('apaga a foto guardada pelo app', () async {
      final dir = Directory(p.join(tmp.path, 'documentos'))..createSync();
      final foto = criarArquivo(p.join(dir.path, '${kPrefixoFotoCupom}1.jpg'));

      await apagarFotoCupom(foto.path, dir: dir);

      expect(foto.existsSync(), isFalse);
    });

    test('não apaga arquivo fora dos documentos', () async {
      final dir = Directory(p.join(tmp.path, 'documentos'))..createSync();
      final fora = criarArquivo(p.join(tmp.path, '${kPrefixoFotoCupom}1.jpg'));

      await apagarFotoCupom(fora.path, dir: dir);

      expect(fora.existsSync(), isTrue);
    });

    test('não apaga outro arquivo do app', () async {
      final dir = Directory(p.join(tmp.path, 'documentos'))..createSync();
      final avatar = criarArquivo(p.join(dir.path, 'avatar_1.jpg'));

      await apagarFotoCupom(avatar.path, dir: dir);

      expect(avatar.existsSync(), isTrue);
    });

    test('caminho nulo, vazio ou inexistente não lança', () async {
      final dir = Directory(p.join(tmp.path, 'documentos'))..createSync();

      await apagarFotoCupom(null, dir: dir);
      await apagarFotoCupom('   ', dir: dir);
      await apagarFotoCupom(
          p.join(dir.path, '${kPrefixoFotoCupom}nada.jpg'), dir: dir);
    });
  });

  group('apagarCopiaTemporaria', () {
    test('apaga a cópia deixada no cache', () async {
      final cache = Directory(p.join(tmp.path, 'cache'))..createSync();
      final copia = criarArquivo(p.join(cache.path, 'image_picker1234.jpg'));

      await apagarCopiaTemporaria(copia.path, dir: cache);

      expect(copia.existsSync(), isFalse);
    });

    test('não encosta em arquivo fora do cache', () async {
      final cache = Directory(p.join(tmp.path, 'cache'))..createSync();
      final documentos = Directory(p.join(tmp.path, 'documentos'))..createSync();
      final foto = criarArquivo(
          p.join(documentos.path, '${kPrefixoFotoCupom}1.jpg'));

      await apagarCopiaTemporaria(foto.path, dir: cache);

      expect(foto.existsSync(), isTrue);
    });
  });
}
