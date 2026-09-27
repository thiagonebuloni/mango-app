import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// Camada de persistência local (SQLite via sqflite). Tudo offline:
/// sem servidor, sem custo.
class DBHelper {
  DBHelper._();

  static final DBHelper instance = DBHelper._();

  Database? _db;

  static const _expensesTable = '''
    CREATE TABLE expenses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      valor INTEGER NOT NULL,
      data_hora INTEGER NOT NULL,
      categoria TEXT NOT NULL,
      forma TEXT NOT NULL,
      descricao TEXT,
      estabelecimento TEXT,
      origem TEXT,
      tipo TEXT NOT NULL DEFAULT 'despesa',
      foto TEXT,
      raw TEXT
    )
  ''';

  static const _merchantsTable = '''
    CREATE TABLE merchants (
      merchant TEXT PRIMARY KEY,
      categoria TEXT NOT NULL
    )
  ''';

  /// Perfil do usuário (nome, avatar, cor de fundo e tema): uma única linha.
  /// v5 acrescenta a foto do avatar + posição/zoom do recorte.
  static const _profileTable = '''
    CREATE TABLE profile (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      nome TEXT NOT NULL,
      avatar TEXT NOT NULL,
      cor INTEGER NOT NULL,
      tema_claro INTEGER NOT NULL DEFAULT 1,
      avatar_img TEXT,
      avatar_ax REAL NOT NULL DEFAULT 0,
      avatar_ay REAL NOT NULL DEFAULT 0,
      avatar_zoom REAL NOT NULL DEFAULT 1
    )
  ''';

  /// v1 = gastos + memória de categorias; v2 = perfil do usuário;
  /// v3 = coluna `tipo` (despesa/receita) em expenses;
  /// v4 = coluna `tema_claro` (tema claro/escuro) em profile;
  /// v5 = foto do avatar (`avatar_img`) + posição/zoom do recorte
  /// (`avatar_ax`, `avatar_ay`, `avatar_zoom`) em profile.
  static const _dbVersion = 5;

  Future<void> init() async {
    if (_db != null) return;
    final path = join(await getDatabasesPath(), 'mango.db');
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, _) async {
        await db.execute(_expensesTable);
        await db.execute(_merchantsTable);
        await db.execute(_profileTable);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await db.execute(_profileTable);
        if (oldVersion < 3) {
          await db.execute(
              "ALTER TABLE expenses ADD COLUMN tipo TEXT NOT NULL DEFAULT 'despesa'");
        }
        if (oldVersion < 4) {
          // Perfis já salvos ganham a coluna do tema sem perder os dados:
          // quem não escolheu nada continua no tema claro.
          final cols = await db.rawQuery('PRAGMA table_info(profile)');
          final temTema = cols.any((c) => c['name'] == 'tema_claro');
          if (!temTema) {
            await db.execute(
                'ALTER TABLE profile ADD COLUMN tema_claro INTEGER NOT NULL DEFAULT 1');
          }
        }
        if (oldVersion < 5) {
          // Foto do avatar + posição/zoom do recorte: perfis antigos
          // continuam com o emoticon (avatar_img NULL).
          final cols = await db.rawQuery('PRAGMA table_info(profile)');
          final nomes = cols.map((c) => c['name'] as String?).toSet();
          if (!nomes.contains('avatar_img')) {
            await db.execute('ALTER TABLE profile ADD COLUMN avatar_img TEXT');
          }
          if (!nomes.contains('avatar_ax')) {
            await db.execute(
                'ALTER TABLE profile ADD COLUMN avatar_ax REAL NOT NULL DEFAULT 0');
          }
          if (!nomes.contains('avatar_ay')) {
            await db.execute(
                'ALTER TABLE profile ADD COLUMN avatar_ay REAL NOT NULL DEFAULT 0');
          }
          if (!nomes.contains('avatar_zoom')) {
            await db.execute(
                'ALTER TABLE profile ADD COLUMN avatar_zoom REAL NOT NULL DEFAULT 1');
          }
        }
      },
    );
  }

  Database get db {
    final d = _db;
    if (d == null) {
      throw StateError('DBHelper.init() precisa ser chamado antes de usar.');
    }
    return d;
  }

  // ---------------- expenses ----------------

  Future<int> insertExpense(Expense e) async {
    final map = e.toMap()..remove('id');
    return db.insert('expenses', map);
  }

  Future<void> updateExpense(Expense e) async {
    await db.update(
      'expenses',
      e.toMap(),
      where: 'id = ?',
      whereArgs: [e.id],
    );
  }

  Future<void> deleteExpense(int id) async {
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  /// Todos os gastos, do mais recente para o mais antigo.
  Future<List<Expense>> allExpenses() async {
    final rows = await db.query(
      'expenses',
      orderBy: 'data_hora DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  // ---------------- merchants (memória de categorização) ----------------

  Future<Map<String, Category>> merchantCategories() async {
    final rows = await db.query('merchants');
    return {
      for (final r in rows)
        (r['merchant'] as String): CategoryX.fromName(r['categoria'] as String),
    };
  }

  /// Memoriza estabelecimento → categoria (o app aprende com correções).
  Future<void> memorizeMerchant(String merchant, Category category) async {
    final key = merchant.trim();
    if (key.isEmpty) return;
    await db.insert(
      'merchants',
      {'merchant': key, 'categoria': category.name},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------- agregações para relatórios ----------------

  /// Soma (em centavos) por categoria no período [start, end).
  Future<Map<Category, int>> sumByCategory(
      DateTime start, DateTime end) async {
    return _sumBy('categoria', start, end, CategoryX.fromName);
  }

  /// Soma (em centavos) por forma de pagamento no período [start, end).
  Future<Map<PaymentMethod, int>> sumByPayment(
      DateTime start, DateTime end) async {
    return _sumBy('forma', start, end, PaymentMethodX.fromName);
  }

  Future<Map<T, int>> _sumBy<T>(
    String column,
    DateTime start,
    DateTime end,
    T Function(String) parse,
  ) async {
    final rows = await db.rawQuery(
      'SELECT $column AS k, SUM(valor) AS total '
      'FROM expenses WHERE data_hora >= ? AND data_hora < ? '
      'GROUP BY $column',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    return {
      for (final r in rows)
        parse(r['k'] as String): (r['total'] as int?) ?? 0,
    };
  }

  /// Total (em centavos) no período [start, end).
  Future<int> totalBetween(DateTime start, DateTime end) async {
    final rows = await db.rawQuery(
      'SELECT SUM(valor) AS total FROM expenses '
      'WHERE data_hora >= ? AND data_hora < ?',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  // ---------------- perfil do usuário ----------------

  /// Perfil salvo, ou `null` quando o usuário ainda não fez o cadastro
  /// (primeiro acesso → tela de boas-vindas).
  Future<UserProfile?> loadProfile() async {
    final rows = await db.query('profile', where: 'id = ?', whereArgs: [1]);
    if (rows.isEmpty) return null;
    return UserProfile.fromMap(rows.first);
  }

  /// Grava (ou atualiza) o perfil do usuário.
  Future<void> saveProfile(UserProfile profile) async {
    await db.insert(
      'profile',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Insere vários lançamentos em lote (importação de backup CSV).
  Future<void> insertExpensesBatch(List<Expense> expenses) async {
    final batch = db.batch();
    for (final e in expenses) {
      final map = e.toMap()..remove('id');
      batch.insert('expenses', map);
    }
    await batch.commit(noResult: true);
  }
}

/// Backup CSV dos lançamentos (exportar/importar).
///
/// Formato: cabeçalho `tipo;valor;data_hora;categoria;forma;descricao;
/// estabelecimento;origem` com `;` como separador (padrão BR, abre direto
/// no Excel/LibreOffice) e campos de texto entre aspas com escape `""`.
/// A data vai em ISO-8601 (`2026-03-15T12:30:00.000`) e o valor em
/// centavos (inteiro), para não perder precisão nem depender de locale.
class CsvBackup {
  static const header =
      'tipo;valor;data_hora;categoria;forma;descricao;estabelecimento;origem';

  static String _esc(String value) =>
      '"${value.replaceAll('"', '""')}"';

  /// Serializa os lançamentos para o texto CSV.
  static String export(List<Expense> expenses) {
    final sorted = expenses.toList()
      ..sort((a, b) => a.dataHora.compareTo(b.dataHora));
    final buf = StringBuffer(header);
    for (final e in sorted) {
      buf
        ..write('\n')
        ..write(e.tipo.name)
        ..write(';')
        ..write(e.valorCentavos)
        ..write(';')
        ..write(e.dataHora.toIso8601String())
        ..write(';')
        ..write(e.categoria.name)
        ..write(';')
        ..write(e.forma.name)
        ..write(';')
        ..write(_esc(e.descricao))
        ..write(';')
        ..write(_esc(e.estabelecimento))
        ..write(';')
        ..write(e.origem.name);
    }
    return buf.toString();
  }

  /// Resultado da importação: lançamentos válidos + linhas ignoradas.
  static CsvImportResult import(String csvText) {
    final lines = const LineSplitter().convert(csvText.trim());
    if (lines.isEmpty) {
      return const CsvImportResult(expenses: [], skipped: 0);
    }
    final expenses = <Expense>[];
    var skipped = 0;
    final start = lines.first.trim() == header ? 1 : 0;
    for (var i = start; i < lines.length; i++) {
      final expense = _parseLine(lines[i]);
      if (expense == null) {
        skipped++;
      } else {
        expenses.add(expense);
      }
    }
    return CsvImportResult(expenses: expenses, skipped: skipped);
  }

  /// Quebra a linha respeitando aspas (`;` dentro de `"..."` não separa).
  static List<String> _splitLine(String line) {
    final fields = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == ';') {
        fields.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    fields.add(buf.toString());
    return fields;
  }

  static Expense? _parseLine(String line) {
    if (line.trim().isEmpty) return null;
    final f = _splitLine(line);
    if (f.length != 8) return null;
    final valor = int.tryParse(f[1].trim());
    final data = DateTime.tryParse(f[2].trim());
    if (valor == null || valor <= 0 || data == null) return null;
    final tipo = EntryKindX.fromName(f[0].trim());
    return Expense(
      tipo: tipo,
      valorCentavos: valor,
      dataHora: data,
      categoria: CategoryX.fromName(f[3].trim(), tipo: tipo),
      forma: PaymentMethodX.fromName(f[4].trim()),
      descricao: f[5],
      estabelecimento: f[6],
      origem: f[7].trim() == 'ocr' ? ExpenseOrigin.ocr : ExpenseOrigin.manual,
    );
  }
}

/// Resultado de [CsvBackup.import].
class CsvImportResult {
  final List<Expense> expenses;
  final int skipped;

  const CsvImportResult({required this.expenses, required this.skipped});
}

/// Limites de período usados na Home e nos relatórios (semana começa na
/// segunda-feira, padrão brasileiro).
class Periods {
  static DateTime startOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static DateTime startOfWeek(DateTime d) {
    final today = startOfDay(d);
    // weekday: 1 = segunda ... 7 = domingo
    return today.subtract(Duration(days: today.weekday - 1));
  }

  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);
}
