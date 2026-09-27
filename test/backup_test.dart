import 'package:flutter_test/flutter_test.dart';
import 'package:mango/db/db.dart';
import 'package:mango/models/models.dart';

void main() {
  group('Backup com perfil (CsvBackup v2)', () {
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

    test('export inclui nome, avatar, cor e tema', () {
      final csv = CsvBackup.export([gasto()], perfil: perfil);
      expect(csv, contains(CsvBackup.backupMarker));
      expect(csv, contains('nome="Ana Souza"'));
      expect(csv, contains('avatar="🦊"'));
      expect(csv, contains('cor=4280171103'));
      expect(csv, contains('tema=escuro'));
      expect(csv, contains(CsvBackup.header));
    });

    test('export sem perfil mantem formato antigo + marcador', () {
      final csv = CsvBackup.export([gasto()]);
      expect(csv, contains(CsvBackup.header));
      expect(csv, isNot(contains('# PERFIL')));
    });

    test('import restaura perfil + lancamentos', () {
      final csv = CsvBackup.export([gasto()], perfil: perfil);
      final result = CsvBackup.import(csv);
      expect(result.expenses, hasLength(1));
      expect(result.skipped, 0);
      expect(result.perfil?.nome, 'Ana Souza');
      expect(result.perfil?.avatar, '🦊');
      expect(result.perfil?.corFundo, 0xFF1E3A5F);
      expect(result.perfil?.temaClaro, isFalse);
    });

    test('import de backup antigo (sem # PERFIL) tem perfil nulo', () {
      const antigo =
          'tipo;valor;data_hora;categoria;forma;descricao;estabelecimento;origem\n'
          'despesa;2299;2026-03-15T12:30:00.000;mercado;dinheiro;"Compra";"MERCADO";manual';
      final result = CsvBackup.import(antigo);
      expect(result.expenses, hasLength(1));
      expect(result.perfil, isNull);
    });

    test('tema invalido/ausente assume escuro', () {
      final semTema =
          '${CsvBackup.backupMarker}\n# PERFIL;nome="Ana";avatar="X";cor=4280000000\n${CsvBackup.header}';
      expect(CsvBackup.import(semTema).perfil?.temaClaro, isFalse);
      final invalido =
          '${CsvBackup.backupMarker}\n# PERFIL;nome="Ana";avatar="X";cor=4280000000;tema=banana\n${CsvBackup.header}';
      expect(CsvBackup.import(invalido).perfil?.temaClaro, isFalse);
      final claro =
          '${CsvBackup.backupMarker}\n# PERFIL;nome="Ana";avatar="X";cor=4280000000;tema=claro\n${CsvBackup.header}';
      expect(CsvBackup.import(claro).perfil?.temaClaro, isTrue);
    });

    test('nome com ; e aspas sobrevive ao round-trip', () {
      const esquisito = UserProfile(
        nome: 'Ana; "Souza"',
        avatar: '🦊',
        corFundo: 0xFFE3F2FD,
        temaClaro: true,
      );
      final csv = CsvBackup.export([gasto()], perfil: esquisito);
      final lido = CsvBackup.import(csv).perfil;
      expect(lido?.nome, 'Ana; "Souza"');
      expect(lido?.temaClaro, isTrue);
    });
  });
}
