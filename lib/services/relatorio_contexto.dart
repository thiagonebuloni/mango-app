// Resumo determinístico do período que alimenta o prompt do relatório por IA.
//
// O modelo de linguagem **apenas narra**: todos os números vêm daqui,
// calculados em Dart sobre o banco do app. Um modelo pequeno (0.5B) não
// precisa somar nada e não há risco de ele inventar valor — se o dado não
// está neste JSON, não pode aparecer no relatório.
import 'dart:convert';

import '../models/models.dart';
import '../state/providers.dart' show PeriodRange;

/// Um total do período com a participação percentual sobre as despesas.
class ItemValor {
  final String nome;
  final int centavos;
  final double percentual;

  const ItemValor({
    required this.nome,
    required this.centavos,
    required this.percentual,
  });
}

/// Resumo de um período, pronto para virar JSON no prompt.
class RelatorioContexto {
  final PeriodRange periodo;
  final PeriodRange periodoAnterior;
  final int despesas; // centavos no período
  final int receitas; // centavos no período
  final int despesasAnteriores; // centavos no período anterior
  final int lancamentos; // quantidade no período (despesas + receitas)
  final List<ItemValor> categorias; // despesas por categoria, maior primeiro
  final List<ItemValor> formas; // despesas por forma de pagamento
  final List<ItemValor> estabelecimentos; // maiores estabelecimentos
  final int maiorDiaCentavos; // maior gasto em um único dia
  final DateTime? maiorDia;

  const RelatorioContexto({
    required this.periodo,
    required this.periodoAnterior,
    required this.despesas,
    required this.receitas,
    required this.despesasAnteriores,
    required this.lancamentos,
    required this.categorias,
    required this.formas,
    required this.estabelecimentos,
    required this.maiorDiaCentavos,
    required this.maiorDia,
  });

  /// Janela imediatamente anterior a [p].
  ///
  /// Quando o período começa dia 1 (o filtro "Mês" da aba Relatórios), a
  /// comparação é com o **mês calendário anterior inteiro**. Nas demais
  /// janelas, uma janela da mesma duração logo antes — assim nenhum dia fica
  /// de fora da comparação.
  static PeriodRange anteriorDe(PeriodRange p) {
    if (p.start.day == 1) {
      return PeriodRange(
        start: DateTime(p.start.year, p.start.month - 1, 1),
        // Dia 0 do mês atual = último dia do mês anterior.
        end: DateTime(p.start.year, p.start.month, 0),
      );
    }
    final duracao = p.endExclusive.difference(p.start);
    return PeriodRange(
      start: p.start.subtract(duracao),
      end: p.start.subtract(const Duration(days: 1)),
    );
  }

  /// Monta o resumo de [periodo] a partir de todos os lançamentos [todas].
  ///
  /// [rotuloCategoria] e [rotuloPagamento] traduzem os nomes dos enums para
  /// o idioma do app (`strings.categoriaLabel` / `strings.pagamentoLabel`).
  /// [periodoAnterior] sobrepõe a janela de comparação (padrão:
  /// [anteriorDe]).
  factory RelatorioContexto.construir({
    required Iterable<Expense> todas,
    required PeriodRange periodo,
    required String Function(String) rotuloCategoria,
    required String Function(String) rotuloPagamento,
    PeriodRange? periodoAnterior,
  }) {
    final anterior = periodoAnterior ?? anteriorDe(periodo);

    var despesas = 0;
    var receitas = 0;
    var despesasAnteriores = 0;
    var lancamentos = 0;
    final porCategoria = <String, int>{};
    final porForma = <String, int>{};
    final porEstabelecimento = <String, int>{};
    final porDia = <DateTime, int>{};

    for (final e in todas) {
      if (anterior.contains(e.dataHora)) {
        if (!e.isReceita) despesasAnteriores += e.valorCentavos;
        continue;
      }
      if (!periodo.contains(e.dataHora)) continue;
      lancamentos++;
      if (e.isReceita) {
        receitas += e.valorCentavos;
        continue;
      }
      despesas += e.valorCentavos;
      final categoria = rotuloCategoria(e.categoria.name);
      porCategoria[categoria] = (porCategoria[categoria] ?? 0) + e.valorCentavos;
      final forma = rotuloPagamento(e.forma.name);
      porForma[forma] = (porForma[forma] ?? 0) + e.valorCentavos;
      final estabelecimento = e.estabelecimento.trim().isEmpty
          ? e.descricao.trim()
          : e.estabelecimento.trim();
      if (estabelecimento.isNotEmpty) {
        porEstabelecimento[estabelecimento] =
            (porEstabelecimento[estabelecimento] ?? 0) + e.valorCentavos;
      }
      final dia = DateTime(e.dataHora.year, e.dataHora.month, e.dataHora.day);
      porDia[dia] = (porDia[dia] ?? 0) + e.valorCentavos;
    }

    List<ItemValor> itens(Map<String, int> fonte, {int limite = 6}) {
      final ordenado = fonte.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return [
        for (final entrada in ordenado.take(limite))
          ItemValor(
            nome: entrada.key,
            centavos: entrada.value,
            percentual: despesas > 0
                ? _umDecimal(entrada.value * 100 / despesas)
                : 0,
          ),
      ];
    }

    DateTime? diaMaior;
    var maior = 0;
    for (final entrada in porDia.entries) {
      if (entrada.value > maior) {
        maior = entrada.value;
        diaMaior = entrada.key;
      }
    }

    return RelatorioContexto(
      periodo: periodo,
      periodoAnterior: anterior,
      despesas: despesas,
      receitas: receitas,
      despesasAnteriores: despesasAnteriores,
      lancamentos: lancamentos,
      categorias: itens(porCategoria),
      formas: itens(porForma),
      estabelecimentos: itens(porEstabelecimento, limite: 5),
      maiorDiaCentavos: maior,
      maiorDia: diaMaior,
    );
  }

  /// Variação das despesas em relação ao período anterior, em % (1 casa).
  /// `null` quando não há base para comparar (período anterior sem despesas).
  double? get variacaoDespesasPct {
    if (despesasAnteriores <= 0) return null;
    return _umDecimal(
      (despesas - despesasAnteriores) * 100 / despesasAnteriores,
    );
  }

  /// Forma pronta para o `jsonEncode` do prompt: datas ISO (AAAA-MM-DD) e
  /// valores em reais com 2 casas (o modelo lê melhor "1234.56" do que
  /// centavos inteiros).
  Map<String, Object?> toMap() => {
        'period': {
          'start': _data(periodo.start),
          'end': _data(periodo.end),
        },
        'entries_count': lancamentos,
        'expenses_total': _reais(despesas),
        'income_total': _reais(receitas),
        'balance': _reais(receitas - despesas),
        'previous_period': {
          'start': _data(periodoAnterior.start),
          'end': _data(periodoAnterior.end),
          'expenses_total': _reais(despesasAnteriores),
          'expenses_change_pct': variacaoDespesasPct,
        },
        'by_category': [
          for (final i in categorias)
            {
              'name': i.nome,
              'total': _reais(i.centavos),
              'share_pct': i.percentual,
            },
        ],
        'by_payment': [
          for (final i in formas)
            {
              'name': i.nome,
              'total': _reais(i.centavos),
              'share_pct': i.percentual,
            },
        ],
        'top_merchants': [
          for (final i in estabelecimentos)
            {'name': i.nome, 'total': _reais(i.centavos)},
        ],
        if (maiorDia != null)
          'biggest_day': {
            'date': _data(maiorDia!),
            'total': _reais(maiorDiaCentavos),
          },
      };

  String get json => jsonEncode(toMap());
}

/// Centavos → reais com 2 casas, sem resíduo de ponto flutuante no JSON.
double _reais(int centavos) =>
    double.parse((centavos / 100).toStringAsFixed(2));

double _umDecimal(double v) => double.parse(v.toStringAsFixed(1));

String _data(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
