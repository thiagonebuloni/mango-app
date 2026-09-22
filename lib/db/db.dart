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

  /// Perfil do usuário (nome, avatar e cor de fundo): uma única linha.
  static const _profileTable = '''
    CREATE TABLE profile (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      nome TEXT NOT NULL,
      avatar TEXT NOT NULL,
      cor INTEGER NOT NULL
    )
  ''';

  /// v1 = gastos + memória de categorias; v2 = perfil do usuário.
  static const _dbVersion = 2;

  Future<void> init() async {
    if (_db != null) return;
    final path = join(await getDatabasesPath(), 'financ.db');
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
