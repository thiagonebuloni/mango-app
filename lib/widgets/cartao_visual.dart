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

/// Arte do cartão: degradê da cor do banco, nome do banco em cima, logo da
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
                  BandeiraLogo(bandeira: cartao.bandeira),
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

/// Selo da bandeira: distintivo branco com o logotipo da rede redesenhado
/// em vetor ([CustomPainter]), espelhando as marcas da imagem de referência
/// em `assets/bandeiras-cartao-11550720856zhnvqecku8.png`.
///
/// Vetor em vez de recorte do PNG por três motivos: o PNG é uma grade de
/// logos em fundo quadriculado (recortar em tempo de execução exigiria
/// alinhar pixels e o fundo nunca some direito), vetor não pixela em telas
/// densas e funciona offline sem declarar novo asset.
class BandeiraLogo extends StatelessWidget {
  final BandeiraCartao bandeira;

  const BandeiraLogo({super.key, required this.bandeira});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: bandeira.sigla,
      child: Container(
        width: 54,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 3),
          ],
        ),
        child: CustomPaint(
          painter: _pintorDa(bandeira),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

CustomPainter _pintorDa(BandeiraCartao bandeira) {
  switch (bandeira) {
    case BandeiraCartao.visa:
      return const _VisaPainter();
    case BandeiraCartao.mastercard:
      return const _MastercardPainter();
    case BandeiraCartao.elo:
      return const _EloPainter();
    case BandeiraCartao.amex:
      return const _AmexPainter();
    case BandeiraCartao.hipercard:
      return const _HipercardPainter();
    case BandeiraCartao.outras:
      return const _OutrasPainter();
  }
}

/// Desenha um texto centralizado ocupando [size], com escala para caber.
void _desenharTextoCentral(
  Canvas canvas,
  Size size,
  String texto,
  TextStyle estilo, {
  FontStyle? italico,
}) {
  final pintor = TextPainter(
    text: TextSpan(
      text: texto,
      style: estilo.copyWith(fontStyle: italico ?? estilo.fontStyle),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();
  final escala = (size.width / pintor.width)
      .clamp(0.1, 1.0)
      .clamp(0.1, size.height / pintor.height);
  canvas.save();
  // ignore: deprecated_member_use
  canvas.translate(size.width / 2, size.height / 2);
  // ignore: deprecated_member_use
  canvas.scale(escala);
  // ignore: deprecated_member_use
  canvas.translate(-pintor.width / 2, -pintor.height / 2);
  pintor.paint(canvas, Offset.zero);
  canvas.restore();
}

/// VISA: lettering azul-escuro em itálico com o filete amarelo no "V",
/// como no adesivo "VISA Electron" da referência.
class _VisaPainter extends CustomPainter {
  const _VisaPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Filete amarelo sob o "V" (faixa fina na base do texto).
    final faixa = Paint()..color = const Color(0xFFF7B500);
    final faixaAltura = size.height * 0.12;
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.06,
        size.height - faixaAltura - size.height * 0.16,
        size.width * 0.88,
        faixaAltura,
      ),
      faixa,
    );
    _desenharTextoCentral(
      canvas,
      Size(size.width, size.height * 0.84),
      'VISA',
      const TextStyle(
        color: Color(0xFF1A1F71),
        fontWeight: FontWeight.w900,
        fontStyle: FontStyle.italic,
        letterSpacing: 1.5,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Mastercard: dois círculos que se cruzam (vermelho + âmbar) com a
/// lente laranja na interseção — igual ao adesivo da referência.
class _MastercardPainter extends CustomPainter {
  const _MastercardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final raio = size.height * 0.38;
    final centroY = size.height / 2;
    final desloc = raio * 0.85;
    final centro = Offset(size.width / 2, centroY);
    canvas.drawCircle(
      centro + Offset(-desloc / 2, 0),
      raio,
      Paint()..color = const Color(0xFFEB001B),
    );
    canvas.drawCircle(
      centro + Offset(desloc / 2, 0),
      raio,
      Paint()..color = const Color(0xFFF79E1B),
    );
    canvas.drawCircle(
      centro + Offset(-desloc / 2, 0),
      raio,
      Paint()
        ..color = const Color(0xFFFF5F00).withValues(alpha: 0.85)
        ..blendMode = BlendMode.srcOver,
    );
    // Reforça a "lente" central sobre a interseção.
    final lente = Path()
      ..addOval(
        Rect.fromCenter(center: centro, width: desloc * 0.9, height: raio * 1.5),
      );
    canvas.drawPath(lente, Paint()..color = const Color(0xFFFF5F00));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Elo: anel tricolor (amarelo/vermelho/azul) + "elo" em minúsculas,
/// como nos dois adesivos da referência (fundo claro e escuro).
class _EloPainter extends CustomPainter {
  const _EloPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final raio = size.height * 0.4;
    final centro = Offset(size.height * 0.5, size.height / 2);
    const grossura = 0.34;
    final arcos = [
      (0.0, 2.2, const Color(0xFFFFCC00)),
      (2.2, 4.2, const Color(0xFFEE3524)),
      (4.2, 6.2832, const Color(0xFF0099D8)),
    ];
    for (final (inicio, fim, cor) in arcos) {
      canvas.drawArc(
        Rect.fromCircle(center: centro, radius: raio),
        inicio - 1.5708,
        fim - inicio,
        false,
        Paint()
          ..color = cor
          ..style = PaintingStyle.stroke
          ..strokeWidth = raio * grossura
          ..strokeCap = StrokeCap.butt,
      );
    }
    // Texto à direita do anel (o helper centraliza no retângulo dado,
    // então deslocamos o canvas para posicioná-lo).
    canvas.save();
    // ignore: deprecated_member_use
    canvas.translate(size.width * 0.30, 0);
    _desenharTextoCentral(
      canvas,
      Size(size.width * 0.62, size.height),
      'elo',
      const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Amex: retângulo azul com "AMEX" branco em condensed bold,
/// como o adesivo "AMERICAN EXPRESS" da referência.
class _AmexPainter extends CustomPainter {
  const _AmexPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF2E77BC),
    );
    _desenharTextoCentral(
      canvas,
      size,
      'AMEX',
      const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Hipercard/Hiper: faixa vermelha inclinada com "Hipercard" branco em
/// itálico — igual ao adesivo da segunda fileira da referência.
class _HipercardPainter extends CustomPainter {
  const _HipercardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final faixa = Path()
      ..moveTo(size.width * 0.12, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * 0.88, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(faixa, Paint()..color = const Color(0xFFB01C2E));
    _desenharTextoCentral(
      canvas,
      size,
      'Hipercard',
      const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Outras redes: três pontos cinza sobre o distintivo branco.
class _OutrasPainter extends CustomPainter {
  const _OutrasPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final tinta = Paint()..color = const Color(0xFF6B7280);
    final raio = size.height * 0.11;
    final y = size.height / 2;
    for (var i = -1; i <= 1; i++) {
      canvas.drawCircle(
        Offset(size.width / 2 + i * raio * 3, y),
        raio,
        tinta,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
