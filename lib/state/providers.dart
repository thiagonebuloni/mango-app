import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db.dart';
import '../models/models.dart';
import '../services/receipt_parser.dart';
import '../services/receipt_photo.dart';
import '../services/seguranca.dart';
import '../services/notificacoes.dart';

/// Estado reativo dos gastos: carrega do SQLite e re-carrega após mutações.
class ExpensesNotifier extends AsyncNotifier<List<Expense>> {
  @override
  Future<List<Expense>> build() => DBHelper.instance.allExpenses();

  Future<void> _reload() async {
    state = AsyncData(await DBHelper.instance.allExpenses());
  }

  Future<int> add(Expense expense) async {
    // Estabelecimento com sufixo "x/y" (ex.: "LOJA 2/10"): divide o valor
    // total entre as parcelas restantes e cria uma cópia por mês.
    final parcelas = expandirParcelas(expense);
    if (parcelas.length == 1) {
      await DBHelper.instance.insertExpense(expense);
    } else {
      await DBHelper.instance.insertExpensesBatch(parcelas);
    }
    if (expense.estabelecimento.trim().isNotEmpty) {
      await DBHelper.instance.memorizeMerchant(
              ReceiptParser.normalizeMerchant(expense.estabelecimento),
              expense.categoria);
    }
    await _reload();
    return parcelas.length;
  }

  /// Edita um gasto existente ("update" colide com a API do AsyncNotifier).
  Future<void> edit(Expense expense) async {
    await DBHelper.instance.updateExpense(expense);
    if (expense.estabelecimento.trim().isNotEmpty) {
      await DBHelper.instance.memorizeMerchant(
              ReceiptParser.normalizeMerchant(expense.estabelecimento),
              expense.categoria);
    }
    await _reload();
  }

  Future<void> delete(int id) async {
    // A foto do cupom é **compartilhada** pelas parcelas do mesmo lançamento
    // ("LOJA 1/10", "2/10"...): o arquivo só é apagado quando nenhum outro
    // lançamento ainda aponta para ele.
    final atuais = state.value ?? const <Expense>[];
    Expense? alvo;
    for (final e in atuais) {
      if (e.id == id) alvo = e;
    }
    await DBHelper.instance.deleteExpense(id);
    final foto = alvo?.fotoPath;
    if (foto != null && foto.trim().isNotEmpty) {
      var aindaUsada = false;
      for (final e in atuais) {
        if (e.id != id && e.fotoPath == foto) {
          aindaUsada = true;
          break;
        }
      }
      if (!aindaUsada) await apagarFotoCupom(foto);
    }
    await _reload();
  }

  /// Agrega um backup CSV importado aos lançamentos já existentes.
  ///
  /// Por segurança **não apaga nada**: só insere o que ainda não está no
  /// app — duplicatas vindas do arquivo ou já cadastradas (mesma
  /// [Expense.chaveUnica]) são ignoradas, e registros únicos do aparelho
  /// são preservados. Retorna quantos lançamentos novos foram inseridos.
  Future<int> mergeAll(List<Expense> imported) async {
    final existentes = await DBHelper.instance.allExpenses();
    final chaves = existentes.map((e) => e.chaveUnica).toSet();
    final novos = <Expense>[];
    for (final e in imported) {
      if (chaves.add(e.chaveUnica)) novos.add(e);
    }
    if (novos.isNotEmpty) {
      await DBHelper.instance.insertExpensesBatch(novos);
    }
    await _reload();
    return novos.length;
  }
}

/// Expande um lançamento parcelado ("LOJA 2/10") na lista de lançamentos
/// mensais: o valor total informado é dividido entre as parcelas restantes
/// (x..y), cada uma caindo no mesmo dia dos meses seguintes.
///
/// Sem sufixo "x/y" válido (ou última parcela `y/y`): retorna só [base].
/// Função pura (sem banco) para facilitar testes.
List<Expense> expandirParcelas(Expense base) {
  final parcela =
      ReceiptParser.parseParcelaSuffix(base.estabelecimento.trim());
  if (parcela == null || parcela.atual >= parcela.total) return [base];
  final nomeBase = ReceiptParser.stripParcelaSuffix(base.estabelecimento);
  final restantes = parcela.total - parcela.atual + 1;
  // Divisão inteira em centavos: o resto (0..restantes-1 centavos) fica
  // todo na parcela atual para a soma bater exatamente com o total.
  final valorParcela = base.valorCentavos ~/ restantes;
  final resto = base.valorCentavos - valorParcela * restantes;
  final lista = <Expense>[];
  for (var i = 0; i < restantes; i++) {
    final numero = parcela.atual + i;
    final atual = base.copyWith(
      id: null,
      valorCentavos: valorParcela + (i == 0 ? resto : 0),
      dataHora: addMonths(base.dataHora, i),
      estabelecimento: '$nomeBase $numero/${parcela.total}',
    );
    // Só a parcela atual guarda a foto do cupom; as futuras são projeções
    // (`copyWith` não limpa `fotoPath`, então reconstrói sem a foto).
    lista.add(i == 0
        ? atual
        : Expense(
            valorCentavos: atual.valorCentavos,
            dataHora: atual.dataHora,
            categoria: atual.categoria,
            forma: atual.forma,
            descricao: atual.descricao,
            estabelecimento: atual.estabelecimento,
            origem: atual.origem,
            tipo: atual.tipo,
            fotoPath: null,
            rawText: atual.rawText,
          ));
  }
  return lista;
}

/// Soma [meses] a [data] preservando dia/hora; trava no último dia do mês
/// (ex.: 31/01 + 1 mês = 28/02).
///
/// O ano também é travado nos limites construíveis do `DateTime`
/// (range absoluto: -271821-04-20 .. 275760-09-13): sem isso, datas
/// extremas fariam `DateTime()` lançar `ArgumentError` e derrubar a
/// expansão de parcelas. A distorção só ocorre a um ano das bordas
/// absolutas, inalcançável pelos fluxos do app.
DateTime addMonths(DateTime data, int meses) {
  if (meses == 0) return data;
  final totalMeses = (data.month - 1) + meses;
  final ano = _clampAno(data.year + totalMeses ~/ 12);
  final mes = totalMeses % 12 + 1;
  final ultimoDia = DateTime(ano, mes + 1, 0).day;
  final dia = data.day > ultimoDia ? ultimoDia : data.day;
  return DateTime(
      ano, mes, dia, data.hour, data.minute, data.second, data.millisecond);
}

/// Ano mínimo/máximo construídos com folga de segurança (meses e dias
/// normalizados nas bordas permanecem dentro do range do `DateTime`).
const int _anoMinSeguro = -271820;
const int _anoMaxSeguro = 275759;

int _clampAno(int ano) {
  if (ano < _anoMinSeguro) return _anoMinSeguro;
  if (ano > _anoMaxSeguro) return _anoMaxSeguro;
  return ano;
}

final expensesProvider =
    AsyncNotifierProvider<ExpensesNotifier, List<Expense>>(
        ExpensesNotifier.new);

/// Perfil já lido do banco em `main()`, antes do primeiro frame.
///
/// Serve de valor inicial enquanto o [profileProvider] carrega: sem ele o app
/// abriria com a cor de fundo padrão e só depois mudaria para a do usuário.
final perfilInicialProvider = Provider<UserProfile?>((ref) => null);

/// Perfil do usuário (nome, avatar e cor de fundo do app).
///
/// `null` = primeiro acesso: o app abre a tela de cadastro do perfil.
class ProfileNotifier extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() async {
    final inicial = ref.read(perfilInicialProvider);
    if (inicial != null) return inicial;
    return DBHelper.instance.loadProfile();
  }

  Future<void> save(UserProfile profile) async {
    await DBHelper.instance.saveProfile(profile);
    state = AsyncData(profile);
  }
}

final profileProvider =
    AsyncNotifierProvider<ProfileNotifier, UserProfile?>(ProfileNotifier.new);

/// Sumários diário/semanal/mensal derivados da lista carregada.
///
/// [dia]/[semana]/[mes] somam só despesas; [receitasDia]/[receitasSemana]/
/// [receitasMes] somam só receitas e [saldo*] = receitas − despesas.
class PeriodSummary {
  final int dia;
  final int semana;
  final int mes;
  final int receitasDia;
  final int receitasSemana;
  final int receitasMes;

  const PeriodSummary({
    required this.dia,
    required this.semana,
    required this.mes,
    this.receitasDia = 0,
    this.receitasSemana = 0,
    this.receitasMes = 0,
  });

  int get saldoDia => receitasDia - dia;
  int get saldoSemana => receitasSemana - semana;
  int get saldoMes => receitasMes - mes;
}

PeriodSummary summarize(List<Expense> expenses, DateTime now) {
  final d0 = Periods.startOfDay(now);
  final w0 = Periods.startOfWeek(now);
  final m0 = Periods.startOfMonth(now);
  int dia = 0, semana = 0, mes = 0;
  int rDia = 0, rSemana = 0, rMes = 0;
  for (final e in expenses) {
    if (!e.dataHora.isBefore(d0)) {
      if (e.isReceita) {
        rDia += e.valorCentavos;
      } else {
        dia += e.valorCentavos;
      }
    }
    if (!e.dataHora.isBefore(w0)) {
      if (e.isReceita) {
        rSemana += e.valorCentavos;
      } else {
        semana += e.valorCentavos;
      }
    }
    if (!e.dataHora.isBefore(m0)) {
      if (e.isReceita) {
        rMes += e.valorCentavos;
      } else {
        mes += e.valorCentavos;
      }
    }
  }
  return PeriodSummary(
    dia: dia,
    semana: semana,
    mes: mes,
    receitasDia: rDia,
    receitasSemana: rSemana,
    receitasMes: rMes,
  );
}

/// Relatórios: gastos do período em aberto, reativos ao expensesProvider.
class ExpensesForReports extends AsyncNotifier<List<Expense>> {
  @override
  Future<List<Expense>> build() {
    // Observa os lançamentos: despesa/receita inserida, editada, excluída ou
    // importada recarrega os relatórios na hora, sem depender de FAB ou
    // pull-to-refresh (os lançamentos sempre passam pelo expensesProvider).
    ref.watch(expensesProvider);
    return DBHelper.instance.allExpenses();
  }
}

final expensesForReportsProvider =
    AsyncNotifierProvider<ExpensesForReports, List<Expense>>(
        ExpensesForReports.new);

PeriodRange periodRange(DateTime now, dynamic period, DateTimeRange? custom) {
  final m0 = DateTime(now.year, now.month);
  final w0 = Periods.startOfDay(now).subtract(const Duration(days: 29));
  final y0 = DateTime(now.year);
  switch (period) {
    case 0:
      return PeriodRange(start: m0, end: now);
    case 1:
      return PeriodRange(start: w0, end: now);
    case 2:
      return PeriodRange(start: y0, end: now);
    case 3:
      final c = custom ?? DateTimeRange(start: m0, end: now);
      return PeriodRange(start: c.start, end: c.end);
  }
  return PeriodRange(start: m0, end: now);
}

Map<Category, int> sumByCategory(Iterable<Expense> expenses,
    {bool receitas = false}) {
  final map = <Category, int>{};
  for (final e in expenses) {
    if (e.isReceita != receitas) continue;
    map[e.categoria] = (map[e.categoria] ?? 0) + e.valorCentavos;
  }
  return map;
}

Map<PaymentMethod, int> sumByPayment(Iterable<Expense> expenses,
    {bool receitas = false}) {
  final map = <PaymentMethod, int>{};
  for (final e in expenses) {
    if (e.isReceita != receitas) continue;
    map[e.forma] = (map[e.forma] ?? 0) + e.valorCentavos;
  }
  return map;
}

/// Soma só despesas (receitas entram separadas via [totalReceitas]).
int totalOf(Iterable<Expense> expenses) {
  int t = 0;
  for (final e in expenses) {
    if (!e.isReceita) t += e.valorCentavos;
  }
  return t;
}

/// Soma só receitas no iterável.
int totalReceitas(Iterable<Expense> expenses) {
  int t = 0;
  for (final e in expenses) {
    if (e.isReceita) t += e.valorCentavos;
  }
  return t;
}

/// Saldo = receitas − despesas.
int saldoOf(Iterable<Expense> expenses) =>
    totalReceitas(expenses) - totalOf(expenses);

/// Agrupa gastos por dia, retornando um mapa onde a chave é a data (sem hora)
/// e o valor é o total em centavos daquele dia.
Map<DateTime, int> sumByDay(Iterable<Expense> expenses) {
  final map = <DateTime, int>{};
  for (final e in expenses) {
    final day = DateTime(e.dataHora.year, e.dataHora.month, e.dataHora.day);
    map[day] = (map[day] ?? 0) + e.valorCentavos;
  }
  return map;
}

/// Retorna uma lista de [DateTime] chaveados por dia, ordenados do mais
/// recente para o mais antigo.
List<DateTime> sortedDays(Map<DateTime, int> dayMap) {
  return dayMap.keys.toList()
    ..sort((a, b) => b.compareTo(a));
}

/// Despesas **no crédito** vinculadas ao cartão [cartaoId] dentro do mês de
/// [mes] (o dia de [mes] é ignorado): é a base da fatura e dos relatórios por
/// categoria/dia da tela de cartões.
///
/// A checagem da forma protege os dados de um `cartao_id` órfão (lançamento
/// editado para PIX/dinheiro, backup importado): fatura é só o que foi
/// comprado no crédito.
List<Expense> gastosDoCartao(
    Iterable<Expense> expenses, int cartaoId, DateTime mes) {
  final inicio = Periods.startOfMonth(mes);
  final fim = DateTime(inicio.year, inicio.month + 1);
  return [
    for (final e in expenses)
      if (e.cartaoId == cartaoId &&
          e.forma == PaymentMethod.credito &&
          !e.isReceita &&
          !e.dataHora.isBefore(inicio) &&
          e.dataHora.isBefore(fim))
        e,
  ];
}

/// Religa os lançamentos de um backup CSV aos cartões do aparelho.
///
/// [vinculosCartao] traz, na mesma ordem de [expenses], o nome da coluna
/// `cartao` de cada linha (`''` = sem cartão); [idsPorNome] mapeia nome → id
/// local, montado depois de fundir os cartões do arquivo com os já
/// cadastrados (mesmo nome não duplica). Nome fora do mapa vira `null`: o
/// gasto fica sem cartão em vez de apontar para o errado. Comparação por
/// nome entre minúsculas, a mesma regra do [CartoesNotifier.mergeAll].
List<Expense> religarCartoes(List<Expense> expenses,
    List<String> vinculosCartao, Map<String, int> idsPorNome) {
  if (vinculosCartao.isEmpty) return expenses;
  return [
    for (var i = 0; i < expenses.length; i++)
      i < vinculosCartao.length
          ? expenses[i].copyWith(
              cartaoId: idsPorNome[vinculosCartao[i].trim().toLowerCase()])
          : expenses[i],
  ];
}

/// Serviço de notificações do app: fica em provedor para os testes
/// conseguirem trocar por um falso (o real só existe em aparelho).
final notificacoesProvider =
    Provider<NotificacoesService>((ref) => NotificacoesService());

/// Estado reativo dos cartões de crédito cadastrados.
final cartoesProvider =
    AsyncNotifierProvider<CartoesNotifier, List<CartaoCredito>>(
        CartoesNotifier.new);

class CartoesNotifier extends AsyncNotifier<List<CartaoCredito>> {
  @override
  Future<List<CartaoCredito>> build() => DBHelper.instance.allCartoes();

  Future<void> _reload() async {
    state = AsyncData(await DBHelper.instance.allCartoes());
  }

  /// Cadastra o cartão, agenda os lembretes e devolve a cópia com o id
  /// gerado pelo banco (as notificações precisam dele).
  Future<CartaoCredito> add(CartaoCredito cartao) async {
    final id = await DBHelper.instance.insertCartao(cartao);
    final salvo = cartao.copyWith(id: id);
    await _reload();
    final notificacoes = ref.read(notificacoesProvider);
    // Permissão pedida só aqui, quando o usuário acabou de cadastrar o
    // cartão e o motivo do pedido está na tela.
    await notificacoes.solicitarPermissao();
    await notificacoes.agendarLembretes(salvo);
    return salvo;
  }

  Future<void> edit(CartaoCredito cartao) async {
    await DBHelper.instance.updateCartao(cartao);
    await _reload();
    // Dias alterados: reagenda os dois lembretes.
    await ref.read(notificacoesProvider).agendarLembretes(cartao);
  }

  /// Agrega os cartões de um backup CSV aos já cadastrados, sem apagar nada.
  ///
  /// O cruzamento é pelo **nome** (mesma regra da coluna `cartao` do CSV):
  /// cartão já cadastrado não duplica. Os novos entram com id gerado e ganham
  /// os lembretes de fechamento/pagamento. Retorna a lista completa após a
  /// fusão — o chamador monta o mapa nome→id para religar os gastos.
  Future<List<CartaoCredito>> mergeAll(List<CartaoCredito> importados) async {
    final atuais = await DBHelper.instance.allCartoes();
    final porNome = <String, CartaoCredito>{
      for (final c in atuais) c.nome.trim().toLowerCase(): c,
    };
    for (final cartao in importados) {
      final chave = cartao.nome.trim().toLowerCase();
      if (chave.isEmpty || porNome.containsKey(chave)) continue;
      final id = await DBHelper.instance.insertCartao(cartao);
      final salvo = cartao.copyWith(id: id);
      atuais.add(salvo);
      porNome[chave] = salvo;
      await ref.read(notificacoesProvider).agendarLembretes(salvo);
    }
    await _reload();
    return atuais;
  }

  /// Apaga o cartão. Os gastos ficam (só perdem o vínculo), então os
  /// relatórios também recarregam.
  Future<void> delete(int id) async {
    await DBHelper.instance.deleteCartao(id);
    await _reload();
    await ref.read(notificacoesProvider).cancelarLembretes(id);
    ref.invalidate(expensesProvider);
    ref.invalidate(expensesForReportsProvider);
  }
}

class PeriodRange {
  final DateTime start;
  final DateTime end;
  const PeriodRange({required this.start, required this.end});

  DateTime get endExclusive => end.add(const Duration(days: 1));

  bool contains(DateTime dt) => !dt.isBefore(start) && dt.isBefore(endExclusive);
}

// ---------------- mês em exibição por tela ----------------

/// Mês mostrado por uma tela com seletor de mês (sempre dia 1).
///
/// Cada tela guarda o seu em um provedor próprio ([mesGastosProvider] na tela
/// Gastos e [mesCartoesProvider] na tela Cartões): trocar o mês de uma não
/// mexe no da outra. O estado vive no `ProviderScope`, acima da navegação —
/// trocar de aba, sair para outra tela e voltar mantêm o período escolhido.
class MesVisivelNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => Periods.startOfMonth(DateTime.now());

  /// Passa a exibir [mes] (o dia é normalizado para o dia 1).
  void mostrar(DateTime mes) => state = Periods.startOfMonth(mes);

  /// Avança/retrocede [delta] meses (negativo = meses passados).
  void mudarPor(int delta) =>
      mostrar(DateTime(state.year, state.month + delta));

  /// `true` quando o mês exibido é o corrente — não existe mês futuro a
  /// mostrar, então o botão de "próximo mês" fica desligado.
  bool get eMesAtual {
    final agora = DateTime.now();
    return state.year == agora.year && state.month == agora.month;
  }
}

/// Mês em exibição na tela **Gastos**.
final mesGastosProvider = NotifierProvider<MesVisivelNotifier, DateTime>(
  MesVisivelNotifier.new,
);

/// Mês em exibição na tela **Cartões** — independente do de Gastos.
final mesCartoesProvider = NotifierProvider<MesVisivelNotifier, DateTime>(
  MesVisivelNotifier.new,
);

// ---------------- bloqueio do app (PIN + biometria) ----------------

/// Configuração do bloqueio; `null` = desativado (app abre direto).
final segurancaProvider =
    AsyncNotifierProvider<SegurancaNotifier, SegurancaConfig?>(
        SegurancaNotifier.new);

class SegurancaNotifier extends AsyncNotifier<SegurancaConfig?> {
  @override
  Future<SegurancaConfig?> build() => DBHelper.instance.loadSeguranca();

  Future<void> _gravar(SegurancaConfig config) async {
    await DBHelper.instance.saveSeguranca(config);
    state = AsyncData(config);
    // O `saveSeguranca` zera a trava por tentativas: recarrega a memória para
    // ela não ficar mostrando uma espera que o banco já não tem.
    ref.invalidate(tentativasProvider);
  }

  /// Ativa o bloqueio criando o PIN (e opcionalmente a biometria).
  Future<void> ativar({required String pin, required bool biometria}) async {
    await _gravar(await criarConfigPin(pin, biometria: biometria));
  }

  /// Troca o PIN depois de conferir o atual.
  Future<void> alterarPin({
    required String atual,
    required String novo,
  }) async {
    final config = state.value;
    if (config == null) {
      throw StateError('O bloqueio não está ativo.');
    }
    if (!await verificarPin(atual, config)) {
      throw const FormatException('PIN atual incorreto.');
    }
    await _gravar(await rehashearPin(config, novo));
  }

  /// Liga/desliga a preferência de biometria (o PIN continua obrigatório).
  Future<void> setBiometria(bool valor) async {
    final config = state.value;
    if (config == null) {
      throw StateError('O bloqueio não está ativo.');
    }
    await _gravar(config.copyWith(biometria: valor));
  }

  /// Desativa o bloqueio por completo, conferindo o PIN atual.
  Future<void> desativar({required String atual}) async {
    final config = state.value;
    if (config == null) return;
    if (!await verificarPin(atual, config)) {
      throw const FormatException('PIN incorreto.');
    }
    await DBHelper.instance.apagarSeguranca();
    state = const AsyncData(null);
    ref.invalidate(tentativasProvider);
  }
}

/// A tranca em si: `true` = travado. Nasce **travada** — toda abertura do
/// app passa por aqui quando o bloqueio está ativo.
final bloqueioProvider = NotifierProvider<BloqueioNotifier, bool>(
  BloqueioNotifier.new,
);

class BloqueioNotifier extends Notifier<bool> {
  /// [janelaCorrida] existe para os testes conseguirem zerá-la e conferir a
  /// re-tranca sem esperar três segundos de verdade.
  BloqueioNotifier({this.janelaCorrida = const Duration(seconds: 3)});

  /// Tempo em que uma volta ao primeiro plano logo **depois** de destravar é
  /// ignorada: algumas OEMs entregam o `resumed` por conta do sucesso da
  /// biometria, e re-trancar aí travaria na cara de quem acabou de destravar.
  final Duration janelaCorrida;

  /// Instante da última destrava; `null` = ainda não destravou nesta sessão.
  DateTime? _destravouEm;

  @override
  bool build() => true;

  void destravar() {
    _destravouEm = DateTime.now();
    state = false;
  }

  /// Re-tranca quando o app volta para primeiro plano. Ignora quando o
  /// bloqueio está desligado ([config] nulo) e dentro da janela de corrida
  /// pós-desbloqueio.
  void reaoVoltar(SegurancaConfig? config) {
    if (config == null) return;
    final ultimo = _destravouEm;
    if (ultimo != null && DateTime.now().difference(ultimo) < janelaCorrida) {
      return;
    }
    state = true;
  }
}

/// Autenticador biométrico usado pelas telas (os testes injetam um falso).
final autenticadorBiometricoProvider = Provider<AutenticadorBiometrico>(
  (ref) => LocalAuthBiometrico(),
);

/// Relógio do app: usado pela trava por tentativas e pela contagem regressiva
/// da tela de bloqueio. Vive em um provedor para os testes conseguirem
/// avançar o tempo sem dormir de verdade.
final relogioProvider = Provider<DateTime Function()>((ref) => DateTime.now);

// ---------------- trava por tentativas erradas ----------------

/// Contagem de PINs errados e a espera em vigor (persistidas no banco, para
/// fechar e reabrir o app não zerar a conta).
final tentativasProvider =
    AsyncNotifierProvider<TentativasNotifier, TentativasBloqueio>(
        TentativasNotifier.new);

class TentativasNotifier extends AsyncNotifier<TentativasBloqueio> {
  @override
  Future<TentativasBloqueio> build() => DBHelper.instance.loadTentativas();

  /// Conta um PIN errado e liga/estende a espera. Devolve o estado novo — a
  /// tela usa `restanteEm` para desenhar a contagem regressiva.
  Future<TentativasBloqueio> registrarFalha() async {
    final atual = state.value ?? const TentativasBloqueio();
    final novo = registrarFalhaDePin(atual, ref.read(relogioProvider)());
    await DBHelper.instance.saveTentativas(novo);
    state = AsyncData(novo);
    return novo;
  }

  /// Zera a contagem: desbloqueio bem-sucedido. Grava sempre, porque o estado
  /// em memória pode nem ter carregado ainda quando o usuário acerta o PIN.
  Future<void> limpar() async {
    await DBHelper.instance.saveTentativas(const TentativasBloqueio());
    state = const AsyncData(TentativasBloqueio());
  }
}
