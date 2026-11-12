import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mango/db/db.dart';
import 'package:mango/models/models.dart';

void main() {
  group('Backup com perfil (CsvBackup v2)', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    const perfil = UserProfile(
      nome: 'Ana Souza',
      avatar: '🦊',
      corFundo: 0xFF1E3A5F,
      temaClaro: false,
    );

    Expense gasto() => Expense(
          valorCentavos: 2299,
          dataHora: DateTime(2026, 3, 15, 12, 30),
          categoria: Category.mercado,
          forma: PaymentMethod.dinheiro,
          descricao: 'Compra',
          estabelecimento: 'MERCADO',
        );

    test('export inclui nome, avatar, cor e tema', () async {
      final csv = await CsvBackup.export([gasto()], perfil: perfil);
      expect(csv, contains(CsvBackup.backupMarker));
      expect(csv, contains('nome="Ana Souza"'));
      expect(csv, contains('avatar="🦊"'));
      expect(csv, contains('cor=4280171103'));
      expect(csv, contains('tema=escuro'));
      expect(csv, contains(CsvBackup.header));
    });

    test('export sem perfil mantem formato antigo + marcador', () async {
      final csv = await CsvBackup.export([gasto()]);
      expect(csv, contains(CsvBackup.header));
      expect(csv, isNot(contains('# PERFIL')));
    });

    test('import restaura perfil + lancamentos', () async {
      final csv = await CsvBackup.export([gasto()], perfil: perfil);
      final result = await CsvBackup.import(csv);
      expect(result.expenses, hasLength(1));
      expect(result.skipped, 0);
      expect(result.perfil?.nome, 'Ana Souza');
      expect(result.perfil?.avatar, '🦊');
      expect(result.perfil?.corFundo, 0xFF1E3A5F);
      expect(result.perfil?.temaClaro, isFalse);
    });

    test('import de backup antigo (sem # PERFIL) tem perfil nulo', () async {
      const antigo =
          'tipo;valor;data_hora;categoria;forma;descricao;estabelecimento;origem\n'
          'despesa;2299;2026-03-15T12:30:00.000;mercado;dinheiro;"Compra";"MERCADO";manual';
      final result = await CsvBackup.import(antigo);
      expect(result.expenses, hasLength(1));
      expect(result.perfil, isNull);
    });

    test('tema invalido/ausente assume escuro', () async {
      final semTema =
          '${CsvBackup.backupMarker}\n# PERFIL;nome="Ana";avatar="X";cor=4280000000\n${CsvBackup.header}';
      expect((await CsvBackup.import(semTema)).perfil?.temaClaro, isFalse);
      final invalido =
          '${CsvBackup.backupMarker}\n# PERFIL;nome="Ana";avatar="X";cor=4280000000;tema=banana\n${CsvBackup.header}';
      expect((await CsvBackup.import(invalido)).perfil?.temaClaro, isFalse);
      final claro =
          '${CsvBackup.backupMarker}\n# PERFIL;nome="Ana";avatar="X";cor=4280000000;tema=claro\n${CsvBackup.header}';
      expect((await CsvBackup.import(claro)).perfil?.temaClaro, isTrue);
    });

    test('aviso de texto puro vai no arquivo e não quebra o import', () async {
      final csv = await CsvBackup.export([gasto()], perfil: perfil);
      // O usuário vê o aviso em qualquer editor/planilha...
      expect(csv, contains(CsvBackup.csvAviso));
      // ...e a linha `#` continua sendo ignorada pelo importador.
      final result = await CsvBackup.import(csv);
      expect(result.expenses, hasLength(1));
      expect(result.skipped, 0);
      expect(result.perfil?.nome, 'Ana Souza');
    });

    test('nome com ; e aspas sobrevive ao round-trip', () async {
      const esquisito = UserProfile(
        nome: 'Ana; "Souza"',
        avatar: '🦊',
        corFundo: 0xFFE3F2FD,
        temaClaro: true,
      );
      final csv = await CsvBackup.export([gasto()], perfil: esquisito);
      final lido = (await CsvBackup.import(csv)).perfil;
      expect(lido?.nome, 'Ana; "Souza"');
      expect(lido?.temaClaro, isTrue);
    });

    test('export/import preserva a foto do avatar em base64', () async {
      final dir = Directory.systemTemp;
      final arquivo = File('${dir.path}/mango_avatar_teste.png');
      await arquivo.writeAsBytes(
        Uint8List.fromList([137, 80, 78, 71]), // cabeçalho PNG
        flush: true,
      );
      addTearDown(() => arquivo.delete());

      final perfilComFoto = UserProfile(
        nome: 'Ana Souza',
        avatar: '🦊',
        corFundo: 0xFF1E3A5F,
        temaClaro: false,
        avatarImagePath: arquivo.path,
      );

      final csv = await CsvBackup.export([gasto()], perfil: perfilComFoto);
      expect(csv, contains(CsvBackup.avatarB64Key));
      expect(csv, contains('avatar_b64='));

      final result = await CsvBackup.import(csv);
      expect(result.perfil?.nome, 'Ana Souza');
      expect(result.perfil?.avatarImagePath, isNotNull);
      expect(result.perfil?.avatarImagePath, isNot(arquivo.path));
      final restaurado = File(result.perfil!.avatarImagePath!);
      expect(await restaurado.exists(), isTrue);
      expect(await restaurado.readAsBytes(), equals(await arquivo.readAsBytes()));
    });

    test('export falha explicitamente se a foto do avatar não puder ser lida',
        () async {
      final perfilComFoto = UserProfile(
        nome: 'Ana Souza',
        avatar: '🦊',
        corFundo: 0xFF1E3A5F,
        avatarImagePath: '${Directory.systemTemp.path}/avatar-inexistente.png',
      );

      expect(
        () => CsvBackup.export([gasto()], perfil: perfilComFoto),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
