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
  /// v6 muda o padrão do tema para escuro em bancos novos
  /// (`tema_claro DEFAULT 0`).
  static const _profileTable = '''
    CREATE TABLE profile (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      nome TEXT NOT NULL,
      avatar TEXT NOT NULL,
      cor INTEGER NOT NULL,
      tema_claro INTEGER NOT NULL DEFAULT 0,
      avatar_img TEXT,
      avatar_ax REAL NOT NULL DEFAULT 0,
      avatar_ay REAL NOT NULL DEFAULT 0,
      avatar_zoom REAL NOT NULL DEFAULT 1
    )
  ''';

  /// Bloqueio do app: PIN (só o hash PBKDF2) + preferência de biometria, mais
  /// a trava por tentativas erradas (v8). Linha única, como o perfil; não
  /// entra em exportação nenhuma.
  static const _segurancaTable = '''
    CREATE TABLE seguranca (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      pin_hash TEXT NOT NULL,
      pin_salt TEXT NOT NULL,
      pin_iter INTEGER NOT NULL,
      pin_len INTEGER NOT NULL,
      biometria INTEGER NOT NULL DEFAULT 0,
      tentativas_falhas INTEGER NOT NULL DEFAULT 0,
      bloqueado_ate INTEGER
    )
  ''';

  /// v1 = gastos + memória de categorias; v2 = perfil do usuário;
  /// v3 = coluna `tipo` (despesa/receita) em expenses;
  /// v4 = coluna `tema_claro` (tema claro/escuro) em profile;
  /// v5 = foto do avatar (`avatar_img`) + posição/zoom do recorte
  /// (`avatar_ax`, `avatar_ay`, `avatar_zoom`) em profile;
  /// v6 = padrão do tema passa a escuro em bancos novos
  /// (`tema_claro DEFAULT 0`);
  /// v7 = tabela `seguranca` (bloqueio com PIN + biometria);
  /// v8 = trava por tentativas erradas (`tentativas_falhas` e `bloqueado_ate`)
  /// em `seguranca`.
  static const _dbVersion = 8;

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
        await db.execute(_segurancaTable);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await db.execute(_profileTable);
        if (oldVersion < 3) {
          await db.execute(
              "ALTER TABLE expenses ADD COLUMN tipo TEXT NOT NULL DEFAULT 'despesa'");
        }
        if (oldVersion < 4) {
          // Perfis já salvos ganham a coluna do tema sem perder os dados:
          // quem não escolheu nada cai no padrão atual (escuro).
          final cols = await db.rawQuery('PRAGMA table_info(profile)');
          final temTema = cols.any((c) => c['name'] == 'tema_claro');
          if (!temTema) {
            await db.execute(
                'ALTER TABLE profile ADD COLUMN tema_claro INTEGER NOT NULL DEFAULT 0');
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
        if (oldVersion < 7) {
          // Bloqueio com PIN: a tabela nasce vazia (bloqueio desativado) —
          // quem já usava o app mantém os dados e ativa pelo menu.
          await db.execute(_segurancaTable);
        }
        if (oldVersion < 8) {
          // Trava por tentativas: bancos que já tinham o bloqueio (v7)
          // começam liberados (`tentativas_falhas` 0 e sem espera). Um banco
          // anterior à v7 acabou de criar a tabela já com as colunas.
          final cols = await db.rawQuery('PRAGMA table_info(seguranca)');
          final nomes = cols.map((c) => c['name'] as String?).toSet();
          if (!nomes.contains('tentativas_falhas')) {
            await db.execute('ALTER TABLE seguranca ADD COLUMN '
                'tentativas_falhas INTEGER NOT NULL DEFAULT 0');
          }
          if (!nomes.contains('bloqueado_ate')) {
            await db.execute(
                'ALTER TABLE seguranca ADD COLUMN bloqueado_ate INTEGER');
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

  // ---------------- bloqueio (PIN + biometria) ----------------

  /// Configuração do bloqueio, ou `null` quando desativado.
  Future<SegurancaConfig?> loadSeguranca() async {
    final rows = await db.query('seguranca', where: 'id = ?', whereArgs: [1]);
    if (rows.isEmpty) return null;
    final m = rows.first;
    return SegurancaConfig(
      pinHash: m['pin_hash'] as String,
      pinSalt: m['pin_salt'] as String,
      pinIteracoes: m['pin_iter'] as int,
      pinTamanho: m['pin_len'] as int,
      biometria: (m['biometria'] as int) != 0,
    );
  }

  /// Grava (ou atualiza) a configuração do bloqueio — linha única.
  ///
  /// O `replace` recria a linha, então qualquer mudança de configuração
  /// (criar, trocar ou desativar o PIN) também zera a trava por tentativas:
  /// quem mexeu na configuração está dentro do app e não tem o que esperar.
  Future<void> saveSeguranca(SegurancaConfig config) async {
    await db.insert(
      'seguranca',
      {
        'id': 1,
        'pin_hash': config.pinHash,
        'pin_salt': config.pinSalt,
        'pin_iter': config.pinIteracoes,
        'pin_len': config.pinTamanho,
        'biometria': config.biometria ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Remove a configuração: o app volta a abrir sem bloqueio.
  Future<void> apagarSeguranca() async {
    await db.delete('seguranca', where: 'id = ?', whereArgs: [1]);
  }

  /// Trava por tentativas erradas: contagem e espera em vigor. Sem bloqueio
  /// ativo (nem linha na tabela) devolve o estado liberado.
  Future<TentativasBloqueio> loadTentativas() async {
    final rows = await db.query(
      'seguranca',
      columns: ['tentativas_falhas', 'bloqueado_ate'],
      where: 'id = ?',
      whereArgs: [1],
    );
    if (rows.isEmpty) return const TentativasBloqueio();
    final m = rows.first;
    final ate = m['bloqueado_ate'] as int?;
    return TentativasBloqueio(
      falhas: m['tentativas_falhas'] as int,
      bloqueadoAte:
          ate == null ? null : DateTime.fromMillisecondsSinceEpoch(ate),
    );
  }

  /// Grava a contagem/espera da trava. É só `update`: sem linha na tabela
  /// (bloqueio desativado) não há o que contar.
  Future<void> saveTentativas(TentativasBloqueio tentativas) async {
    await db.update(
      'seguranca',
      {
        'tentativas_falhas': tentativas.falhas,
        'bloqueado_ate': tentativas.bloqueadoAte?.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [1],
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

/// Backup CSV dos lançamentos (+ perfil do usuário no topo).
///
/// Linhas `#` (ex.: `# MANGO_BACKUP v2`, `# AVISO;...` e `# PERFIL;...`) são
/// comentários:
/// ignoradas por planilhas e por backups antigos. O perfil guarda
/// `nome/avatar/corFundo (ARGB)/tema (claro|escuro)`; a foto do avatar não
/// entra no backup (caminho local) e deve ser recolocada na edição final.
///
/// Formato: cabeçalho `tipo;valor;data_hora;categoria;forma;descricao;
/// estabelecimento;origem` com `;` como separador (padrão BR, abre direto
/// no Excel/LibreOffice) e campos de texto entre aspas com escape `""`.
/// A data vai em ISO-8601 (`2026-03-15T12:30:00.000`) e o valor em
/// centavos (inteiro), para não perder precisão nem depender de locale.
class CsvBackup {
  static const header =
      'tipo;valor;data_hora;categoria;forma;descricao;estabelecimento;origem';
  static const backupMarker = '# MANGO_BACKUP v2';
  static const perfilMarker = '# PERFIL;';

  /// Aviso gravado no topo de todo arquivo exportado: o backup é **texto
  /// puro, sem senha**.
  ///
  /// Fica como linha de comentário (`#`), então quem abrir o CSV no
  /// Excel/LibreOffice lê o aviso e o importador segue ignorando a linha —
  /// a decisão de não criptografar o CSV é consciente (senha esquecida =
  /// backup perdido num app sem servidor) e está documentada no README.
  static const csvAviso =
      '# AVISO;Backup em texto puro, sem senha. Guarde em local seguro.';

  /// Tamanho máximo aceito no import (A2).
  ///
  /// Sem teto, um arquivo escolhido por engano (backup gigante, vídeo
  /// renomeado para `.csv`) era lido inteiro com `readAsBytes()` e ainda
  /// duplicado em `String` + lista de linhas, derrubando o app por falta de
  /// memória. 16 MiB ≈ 150 mil lançamentos reais (linha típica ~100 bytes).
  static const maxBytes = 16 * 1024 * 1024;

  /// Teto de linhas processadas: um arquivo dentro de [maxBytes] pode ter
  /// milhões de linhas minúsculas, e aí quem estoura a memória é a lista
  /// de linhas (e não o tamanho em bytes).
  static const maxLines = 200000;

  static const _umMb = 1024 * 1024;

  /// `null` quando o arquivo cabe no import; caso contrário, a mensagem
  /// pronta para mostrar ao usuário.
  ///
  /// Chamado **antes** de ler os bytes (pelo tamanho informado pelo seletor
  /// de arquivos), para nem encostar na memória em arquivos absurdos.
  static String? validateImportSize(int bytes) {
    if (bytes <= maxBytes) return null;
    final valor = bytes / _umMb;
    final mb = valor == valor.roundToDouble()
        ? valor.toStringAsFixed(0)
        : valor.toStringAsFixed(1).replaceAll('.', ',');
    return 'Arquivo muito grande para importar ($mb MB). '
        'O limite é ${maxBytes ~/ _umMb} MB — exporte o backup pelo próprio '
        'Mango ou divida o arquivo em partes.';
  }

  static String _esc(String value) =>
      '"${value.replaceAll('"', '""')}"';

  /// Serializa os lançamentos para o texto CSV, incluindo [perfil] no topo.
  static String export(List<Expense> expenses, {UserProfile? perfil}) {
    final sorted = expenses.toList()
      ..sort((a, b) => a.dataHora.compareTo(b.dataHora));
    final buf = StringBuffer(backupMarker);
    // Aviso de que o arquivo é texto puro: aparece para quem abrir o CSV em
    // qualquer editor/planilha e é ignorado pelo import (linha de comentário).
    buf
      ..write('\n')
      ..write(csvAviso);
    if (perfil != null) {
      buf
        ..write('\n')
        ..write(perfilMarker)
        ..write('nome=')
        ..write(_esc(perfil.nome))
        ..write(';avatar=')
        ..write(_esc(perfil.avatar))
        ..write(';cor=')
        ..write(perfil.corFundo)
        ..write(';tema=')
        ..write(perfil.temaClaro ? 'claro' : 'escuro');
    }
    buf.write('\n$header');
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

  /// Resultado da importação: lançamentos válidos + perfil + linhas ignoradas.
  ///
  /// Lança [CsvImportException] quando o texto passa de [maxBytes]/[maxLines]
  /// (A2): quem chama mostra a mensagem em vez de deixar o app morrer por
  /// falta de memória.
  static CsvImportResult import(String csvText) {
    _verificarLimites(csvText);
    final lines = const LineSplitter().convert(csvText.trim());
    if (lines.isEmpty) {
      return const CsvImportResult(expenses: [], skipped: 0);
    }
    final expenses = <Expense>[];
    var skipped = 0;
    UserProfile? perfil;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        final parsed = _parsePerfilLine(line);
        if (parsed != null) perfil = parsed;
        continue;
      }
      if (line == header) continue;
      final expense = _parseLine(line);
      if (expense == null) {
        skipped++;
      } else {
        expenses.add(expense);
      }
    }
    return CsvImportResult(expenses: expenses, skipped: skipped, perfil: perfil);
  }

  /// Recusa textos que estourariam a memória (A2).
  ///
  /// Todo caractere UTF-8 ocupa pelo menos 1 byte, então `length` maior que
  /// [maxBytes] só acontece em texto vindo de um arquivo já recusado pelo
  /// tamanho — mas a checagem fica aqui também para proteger qualquer outro
  /// chamador. As quebras são contadas antes de dividir o texto: com milhões
  /// de linhas minúsculas, quem estoura a memória é a lista de linhas.
  static void _verificarLimites(String csvText) {
    if (csvText.length > maxBytes) {
      throw CsvImportException(validateImportSize(csvText.length)!);
    }
    var quebras = 0;
    for (final unidade in csvText.codeUnits) {
      // Mesmos terminadores que o `LineSplitter` reconhece (\r\n conta duas).
      if (unidade == 0x0A ||
          unidade == 0x0D ||
          unidade == 0x85 ||
          unidade == 0x2028 ||
          unidade == 0x2029) {
        quebras++;
        if (quebras > maxLines) {
          throw const CsvImportException(
            'Arquivo com linhas demais para importar. '
            'Divida o backup em partes menores.',
          );
        }
      }
    }
  }

  /// Interpreta a linha `# PERFIL;nome=...;avatar=...;cor=...;tema=...`.
  /// Campos ausentes/inválidos caem nos padrões do app (tema escuro,
  /// cor escura, nome/avatar padrão). `null` = linha não é de perfil.
  ///
  /// Nome, avatar e cor passam pelas mesmas regras da tela de perfil (A4):
  /// o arquivo pode ter sido editado à mão, e o import é a porta de entrada
  /// desses valores — um nome gigante ou uma cor transparente (`cor=0`,
  /// `cor=4294967296`) deixariam a tela inicial lenta ou invisível.
  static UserProfile? _parsePerfilLine(String line) {
    if (!line.startsWith(perfilMarker)) return null;
    final resto = line.substring(perfilMarker.length);
    final campos = _splitPerfilFields(resto);
    final nome = UserProfile.sanitizarNome(campos['nome']);
    final avatarLimpo = UserProfile.sanitizarAvatar(campos['avatar']);
    final avatar =
        avatarLimpo.isEmpty ? UserProfile.avatarPadrao : avatarLimpo;
    final corLida = int.tryParse((campos['cor'] ?? '').trim());
    final cor = (corLida != null && UserProfile.corFundoValida(corLida))
        ? corLida
        : UserProfile.corFundoInicialPadrao;
    final temaClaro = (campos['tema'] ?? '').trim().toLowerCase() == 'claro';
    return UserProfile(nome: nome, avatar: avatar, corFundo: cor, temaClaro: temaClaro);
  }

  /// Quebra `chave=valor;...` respeitando aspas (`;` dentro de `"..."`).
  static Map<String, String> _splitPerfilFields(String text) {
    final map = <String, String>{};
    final buf = StringBuffer();
    final parts = <String>[];
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
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
        parts.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    parts.add(buf.toString());
    for (final part in parts) {
      final eq = part.indexOf('=');
      if (eq < 0) continue;
      map[part.substring(0, eq).trim().toLowerCase()] = part.substring(eq + 1).trim();
    }
    return map;
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
  final UserProfile? perfil;

  const CsvImportResult({required this.expenses, required this.skipped, this.perfil});
}

/// Erro de importação com mensagem pronta para o usuário (A2): arquivo
/// acima de [CsvBackup.maxBytes] ou com linhas demais.
class CsvImportException implements Exception {
  final String message;

  const CsvImportException(this.message);

  @override
  String toString() => message;
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
