import 'package:flutter_test/flutter_test.dart';
import 'package:mango/models/models.dart';
import 'package:mango/services/categorizer.dart';
import 'package:mango/services/receipt_parser.dart';
import 'package:mango/state/providers.dart';

const satCupom = '''
SISTEMA AUTENTICADOR E TRANSMISSOR DE CUPOM FISCAL
DOCUMENTO AUXILIAR DE VENDA - CF-E SAT

EXTRATO N.o 123456

PADARIA PAO QUENTE LTDA
CNPJ 12.345.678/0001-90
IE 123456789012
Rua das Flores, 123 - Centro
Item Codigo        Qtde Un   VL Unit(R\$)     VL Total(R\$)
1    001234        1,000 kg  x  15,99         15,99
2    004321        2,000 UN  x   3,50          7,00

VALOR TOTAL R\$ 22,99
DESCONTO R\$ 0,00
VALOR A PAGAR R\$ 22,99

FORMAS DE PAGAMENTO
CARTAO DE CREDITO R\$ 22,99
TROCO R\$ 0,00
''';

const nfeCupom = '''
LOJA DO JOAO COMERCIO DE ALIMENTOS
CNPJ 98.765.432/0001-10
--------------------------------------------------
CODIGO  DESCRICAO          QTD  UN  VL UNIT   VL TOTAL
10      CAFE TORRADO 500G  1    UN    18,90     18,90
20      LEITE INTEGRAL     2    UN     4,99      9,98
--------------------------------------------------
SUBTOTAL 28,88
DINHEIRO 28,88
TROCO 0,12

TOTAL R\$ 28,88
20/03/2026 14:32:05
''';

void main() {
  group('ReceiptParser', () {
    test('extrai total, estabelecimento e forma de pagamento (SAT CF-e)', () {
      final draft = ReceiptParser.parse(satCupom);
      expect(draft.totalCentavos, 2299);
      expect(draft.estabelecimento, 'PADARIA PAO QUENTE LTDA');
      expect(draft.pagamento, PaymentMethod.credito);
      expect(draft.dataHora, isNull);
      expect(draft.itens, isNotEmpty);
    });

    test('extrai data/hora e total de cupom NFC-e', () {
      final draft = ReceiptParser.parse(nfeCupom);
      expect(draft.totalCentavos, 2888);
      expect(draft.estabelecimento, 'LOJA DO JOAO COMERCIO DE ALIMENTOS');
      expect(draft.pagamento, PaymentMethod.dinheiro);
      expect(draft.dataHora, DateTime(2026, 3, 20, 14, 32));
    });

    test('fallback: usa o maior valor quando não há linha de total', () {
      final text = '''
LOJINHA XYZ
CNPJ 00.000.000/0001-00
REFRIGERANTE 2L  9,90
SALGADO         5,50
''';
      final draft = ReceiptParser.parse(text);
      expect(draft.totalCentavos, 990);
    });

    test('identifica PIX', () {
      const text = 'MERCADO CENTRAL\nTOTAL R\$ 50,00\nPIX R\$ 50,00';
      final draft = ReceiptParser.parse(text);
      expect(draft.pagamento, PaymentMethod.pix);
      expect(draft.totalCentavos, 5000);
    });

    test('converte valores monetários brasileiros', () {
      expect(ReceiptParser.moneyToCentavos('1.234,56'), 123456);
      expect(ReceiptParser.moneyToCentavos('12,34'), 1234);
    });

    test('normaliza nome de estabelecimento', () {
      expect(
        ReceiptParser.normalizeMerchant('Padaria Pão Quente Ltda'),
        'padaria pao quente ltda',
      );
    });

    test('"À VISTA" é caracterizado como Dinheiro', () {
      const text = '''
PADARIA PAO QUENTE LTDA
CNPJ 12.345.678/0001-90
_______________________________________
VALOR TOTAL R\$ 22,99
FORMAS DE PAGAMENTO
À VISTA R\$ 22,99
20/03/2026 09:12:33
''';
      final draft = ReceiptParser.parse(text);
      expect(draft.pagamento, PaymentMethod.dinheiro);
      expect(draft.totalCentavos, 2299);
      expect(draft.estabelecimento, 'PADARIA PAO QUENTE LTDA');
    });

    test('"AVISTA" (OCR sem acento/espaço) também é Dinheiro', () {
      const text = 'MERCADO CENTRAL\nTOTAL R\$ 30,00\nPAGAMENTO AVISTA';
      expect(ReceiptParser.parse(text).pagamento, PaymentMethod.dinheiro);
    });

    test('"CREDITO A VISTA" continua sendo Crédito (não é dinheiro)', () {
      const text = 'LOJA TESTE\nTOTAL R\$ 40,00\nCREDITO A VISTA R\$ 40,00';
      expect(ReceiptParser.parse(text).pagamento, PaymentMethod.credito);
    });

    test('prioriza a data de emissão e ignora data de validade', () {
      const text = '''
SUPERMERCADO BOM PRECO
CNPJ 11.222.333/0001-44
PROMOCAO VALIDA ATE 05/04/2026
DATA DE EMISSAO 20/03/2026 14:32:05
TOTAL R\$ 100,00
''';
      final draft = ReceiptParser.parse(text);
      expect(draft.dataHora, DateTime(2026, 3, 20, 14, 32));
    });

    test('data e hora em linhas separadas (comum em cupons SAT)', () {
      const text = '''
PADARIA DO ZE
CNPJ 12.345.678/0001-90
20/09/2026
08:15:03
VALOR TOTAL R\$ 12,00
''';
      final draft = ReceiptParser.parse(text);
      expect(draft.dataHora, DateTime(2026, 9, 20, 8, 15));
    });

    test('aceita data com hífen e ano de 2 dígitos', () {
      const text = 'LOJA TESTE\nCNPJ 00.111.222/0001-33\nDATA 20-03-26\n'
          'TOTAL R\$ 5,00';
      expect(ReceiptParser.parse(text).dataHora, DateTime(2026, 3, 20));
    });

    test('ignora data inválida lida errado pelo OCR', () {
      const text = 'LANCHONETE X\nCNPJ 00.111.222/0001-33\nDATA 32/13/2026\n'
          'TOTAL R\$ 8,00\n20/03/2026 10:00';
      expect(ReceiptParser.parse(text).dataHora, DateTime(2026, 3, 20, 10));
    });

    test('detecta "PARCELA 2/10": sufixo no nome + Crédito', () {
      const text = 'LOJA XYZ\nCNPJ 00.111.222/0001-33\n'
          'PARCELA 02/10\nTOTAL R\$ 100,00\nCARTAO DE CREDITO R\$ 100,00';
      final draft = ReceiptParser.parse(text);
      expect(draft.estabelecimento, 'LOJA XYZ 2/10');
      expect(draft.pagamento, PaymentMethod.credito);
    });

    test('detecta "PARCELA 2 DE 10"', () {
      const text = 'LOJA XYZ\nCNPJ 00.111.222/0001-33\n'
          'PARCELA 2 DE 10\nTOTAL R\$ 100,00';
      final draft = ReceiptParser.parse(text);
      expect(draft.estabelecimento, 'LOJA XYZ 2/10');
      expect(draft.pagamento, PaymentMethod.credito);
    });

    test('"EM 10X" assume a 1ª parcela', () {
      const text = 'LOJA XYZ\nCNPJ 00.111.222/0001-33\n'
          'CREDITO EM 10X\nTOTAL R\$ 500,00';
      final draft = ReceiptParser.parse(text);
      expect(draft.estabelecimento, 'LOJA XYZ 1/10');
      expect(draft.pagamento, PaymentMethod.credito);
    });

    test('força Crédito mesmo sem a palavra "credito" legível', () {
      const text = 'LOJA XYZ\nCNPJ 00.111.222/0001-33\n'
          'PARCELA 01/03\nTOTAL R\$ 90,00';
      final draft = ReceiptParser.parse(text);
      expect(draft.estabelecimento, 'LOJA XYZ 1/3');
      expect(draft.pagamento, PaymentMethod.credito);
    });

    test('data "20/03/2026" não vira parcela', () {
      const text = 'LOJA TESTE\nCNPJ 00.111.222/0001-33\nDATA 20/03/2026\n'
          'TOTAL R\$ 5,00';
      final draft = ReceiptParser.parse(text);
      expect(draft.estabelecimento, 'LOJA TESTE');
      expect(ReceiptParser.parcelas(text), isNull);
    });

    test('"A VISTA" não vira parcela', () {
      const text = 'LOJA TESTE\nTOTAL R\$ 40,00\nA VISTA R\$ 40,00';
      expect(ReceiptParser.parcelas(text), isNull);
    });

    test('normaliza estabelecimento ignorando o sufixo de parcela', () {
      expect(
        ReceiptParser.normalizeMerchant('Loja XYZ 2/10'),
        'loja xyz',
      );
    });
  });

  group('Categorizer (regras locais)', () {
    final c = Categorizer(memoryLoader: () async => const {});

    test('padaria → alimentação', () {
      expect(c.guessByKeywords(text: 'PADARIA PAO QUENTE'),
          Category.alimentacao);
    });

    test('supermercado → mercado', () {
      expect(c.guessByKeywords(text: 'SUPERMERCADO BOM PRECO'),
          Category.mercado);
    });

    test('loja de roupas → vestuário', () {
      expect(c.guessByKeywords(text: 'LOJA DE ROUPAS E CALCADOS'),
          Category.vestuario);
    });

    test('posto → transporte', () {
      expect(c.guessByKeywords(text: 'POSTO SHELL COMBUSTIVEL'),
          Category.transporte);
    });

    test('drogaria → saúde', () {
      expect(c.guessByKeywords(text: 'DROGARIA SAO JOAO'),
          Category.saude);
    });

    test('desconhecido → outros', () {
      expect(c.guessByKeywords(text: 'XYZABC'), Category.outros);
    });

    test('memória de estabelecimento tem prioridade', () async {
      final withMemory = Categorizer(
        memoryLoader: () async => {
          'padaria pao quente': Category.transporte, // usuário corrigiu antes
        },
      );
      final result = await withMemory.categorize(
        estabelecimento: 'PADARIA PAO QUENTE',
        text: 'pao cafe',
      );
      expect(result, Category.transporte);
    });
  });

  group('Parcelas (x/y + expansão mensal)', () {
    Expense gastoBase({
      required String estabelecimento,
      required int centavos,
      required DateTime data,
    }) =>
        Expense(
          valorCentavos: centavos,
          dataHora: data,
          categoria: Category.outros,
          forma: PaymentMethod.credito,
          estabelecimento: estabelecimento,
        );

    test('R\$ 100,00 em 2x vira 2 lançamentos de R\$ 50,00', () {
      final lista = expandirParcelas(gastoBase(
        estabelecimento: 'LOJA XYZ 1/2',
        centavos: 10000,
        data: DateTime(2026, 3, 20, 14, 30),
      ));
      expect(lista.length, 2);
      expect(lista[0].estabelecimento, 'LOJA XYZ 1/2');
      expect(lista[1].estabelecimento, 'LOJA XYZ 2/2');
      expect(lista[0].valorCentavos, 5000);
      expect(lista[1].valorCentavos, 5000);
      expect(lista[0].dataHora, DateTime(2026, 3, 20, 14, 30));
      expect(lista[1].dataHora, DateTime(2026, 4, 20, 14, 30));
    });

    test('soma das parcelas bate com o total (resto na 1ª)', () {
      final lista = expandirParcelas(gastoBase(
        estabelecimento: 'LOJA XYZ 1/3',
        centavos: 10000,
        data: DateTime(2026, 3, 20),
      ));
      expect(lista.length, 3);
      final soma = lista.fold<int>(0, (t, e) => t + e.valorCentavos);
      expect(soma, 10000);
      // 10000 = 3334 + 3333 + 3333
      expect(lista[0].valorCentavos, 3334);
      expect(lista[1].valorCentavos, 3333);
      expect(lista[2].valorCentavos, 3333);
    });

    test('a partir da 2/10 cria só as 9 restantes', () {
      final lista = expandirParcelas(gastoBase(
        estabelecimento: 'LOJA XYZ 2/10',
        centavos: 9000,
        data: DateTime(2026, 3, 20),
      ));
      expect(lista.length, 9);
      expect(lista.first.estabelecimento, 'LOJA XYZ 2/10');
      expect(lista.last.estabelecimento, 'LOJA XYZ 10/10');
      expect(lista.last.dataHora.month, 11);
    });

    test('última parcela (y/y) não expande', () {
      final lista = expandirParcelas(gastoBase(
        estabelecimento: 'LOJA XYZ 10/10',
        centavos: 1000,
        data: DateTime(2026, 3, 20),
      ));
      expect(lista.length, 1);
    });

    test('sem sufixo não expande', () {
      final lista = expandirParcelas(gastoBase(
        estabelecimento: 'LOJA XYZ',
        centavos: 1000,
        data: DateTime(2026, 3, 20),
      ));
      expect(lista.length, 1);
    });

    test('addMonths trava no último dia do mês (31/01 → 28/02)', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2026, 3, 20, 14, 30), 2),
          DateTime(2026, 5, 20, 14, 30));
    });
  });
}
