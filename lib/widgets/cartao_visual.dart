import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../models/models.dart';

/// Cores conhecidas dos bancos/emissores mais comuns do Brasil, usadas na
/// arte do cartão. A chave é o nome **normalizado** (sem caixa, acentos,
/// "banco" ou "s.a.") — use [normalizarBanco] antes de consultar.
const Map<String, Color> coresDosBancos = {
  'itau': Color(0xFFFF9900),
  'nubank': Color(0xFF820AD1),
  'bradesco': Color(0xFFDA291C),
  'santander': Color(0xFFEC0000),
  'bb': Color(0xFF003399),
  'brasil': Color(0xFF003399),
  'caixa': Color(0xFF0066B3),
  'cef': Color(0xFF0066B3),
  'inter': Color(0xFFFF7A00),
  'c6': Color(0xFF242424),
  'pan': Color(0xFF004B87),
  'picpay': Color(0xFF21C25E),
  'sicredi': Color(0xFF00A54F),
  'sicoob': Color(0xFF0066B1),
  'btg': Color(0xFF1C1C1C),
  'neon': Color(0xFF3A3A3A),
  'xp': Color(0xFF00A0DF),
  'original': Color(0xFF005CA9),
  'banrisul': Color(0xFF0033A0),
  'safra': Color(0xFF003D7C),
};

/// Normaliza o nome do banco para comparação: minúsculas, sem acentos e sem
/// palavras genéricas ("banco", "s.a.", "ltda").
String normalizarBanco(String banco) {
  var s = banco
      .toLowerCase()
      .replaceAll(RegExp(r'[áàâãä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòôõö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll(RegExp(r'[ç]'), 'c');
  s = s.replaceAll(RegExp(r'[^a-z0-9]'), '');
  return s;
}

/// Cor da marca do [banco]: a conhecida da lista ou, para nome livre, uma
/// cor estável derivada do próprio texto (o mesmo nome sempre dá a mesma
/// cor, sem depender da ordem dos cartões).
Color corDoBanco(String banco) {
  final normal = normalizarBanco(banco);
  for (final entry in coresDosBancos.entries) {
    if (normal == entry.key || normal.contains(entry.key)) {
      return entry.value;
    }
  }
  const paleta = [
    Color(0xFF6D28D9),
    Color(0xFF0F766E),
    Color(0xFFB45309),
    Color(0xFF1D4ED8),
    Color(0xFFBE123C),
    Color(0xFF047857),
  ];
  var hash = 0;
  for (final r in banco.runes) {
    hash = (hash * 31 + r) & 0x7FFFFFFF;
  }
  return paleta[hash % paleta.length];
}

/// Cor da bandeira (selo no canto do cartão).
Color corDaBandeira(BandeiraCartao bandeira) {
  switch (bandeira) {
    case BandeiraCartao.visa:
      return const Color(0xFF1A1F71);
    case BandeiraCartao.mastercard:
      return const Color(0xFFEB001B);
    case BandeiraCartao.elo:
      return const Color(0xFF000000);
    case BandeiraCartao.amex:
      return const Color(0xFF006FCF);
    case BandeiraCartao.hipercard:
      return const Color(0xFFDA291C);
    case BandeiraCartao.outras:
      return const Color(0xFF374151);
  }
}

/// Escurece [cor] em [fator] (0..1) para o degradê da arte do cartão.
Color escurecer(Color cor, double fator) =>
    Color.lerp(cor, Colors.black, fator)!;

/// Largura e altura padrão de um cartão de crédito, em milímetros
/// (ISO 7810 ID-1).
const double cartaoLarguraMm = 85.6;
const double cartaoAlturaMm = 53.98;

/// Proporção largura:altura do cartão (85,6 mm × 53,98 mm ≈ 1,58:1).
const double razaoCartao = cartaoLarguraMm / cartaoAlturaMm;

/// Arte do cartão: degradê da cor do banco, nome do banco em cima, selo da
/// bandeira à direita e o nome escolhido pelo usuário embaixo.
///
/// O formato segue a proporção real de um cartão ([razaoCartao]): a altura é
/// derivada da largura disponível, e não fixa em pixels.
///
/// **Não desenha número, validade ou nome do titular** — o app guarda só o
/// que é não-sensível.
class CartaoVisual extends StatelessWidget {
  final CartaoCredito cartao;

  /// Altura usada só quando a largura do espaço não é limitada (fora de
  /// coluna/lista): assim o cartão mantém a proporção [razaoCartao] em vez
  /// de estourar a tela.
  final double altura;

  const CartaoVisual({super.key, required this.cartao, this.altura = 150});

  @override
  Widget build(BuildContext context) {
    final cor = corDoBanco(cartao.banco);
    return LayoutBuilder(
      builder: (context, constraints) {
        final largura =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : altura * razaoCartao;
        return Container(
          width: largura,
          height: largura / razaoCartao,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cor, escurecer(cor, 0.35)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: cor.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      cartao.banco,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  _SeloBandeira(bandeira: cartao.bandeira),
                ],
              ),
              const Spacer(),
              Text(
                cartao.nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${context.strings.diaFechamento}: ${cartao.diaFechamento} · '
                '${context.strings.diaPagamento}: ${cartao.diaPagamento}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Selo da bandeira: fundo próprio + sigla curta em branco.
class _SeloBandeira extends StatelessWidget {
  final BandeiraCartao bandeira;

  const _SeloBandeira({required this.bandeira});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: corDaBandeira(bandeira),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        bandeira.sigla,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
