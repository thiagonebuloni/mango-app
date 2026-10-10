/// Gera `ic_notificacao_grande.png` (large icon colorido das notificações)
/// a partir da arte do ícone do app (`assets/icon/app_icon_master.png`).
///
/// Uso: `flutter test tool/gerar_icone_notificacao.dart`
/// (precisa do `flutter_tester`, pois usa `dart:ui` para redimensionar).
///
/// Por que um script e não um PNG commitado: o large icon precisa ser um
/// `drawable` quadrado legível em 48-192dp — o master 1024x1024 já tem esse
/// conteúdo (gradiente manga + emoji 🥭), então o script só redimensiona.
/// Se a arte do app mudar (`tool/generate_icon.py`), rode este script de
/// novo para acompanhar.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gera ic_notificacao_grande.png', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const master = 'assets/icon/app_icon_master.png';
    final bytes = await File(master).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final original = frame.image;
    const lado = 192;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      original,
      Rect.fromLTWH(
        0,
        0,
        original.width.toDouble(),
        original.height.toDouble(),
      ),
      Rect.fromLTWH(0, 0, lado.toDouble(), lado.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final saida = await picture.toImage(lado, lado);
    final png = await saida.toByteData(format: ui.ImageByteFormat.png);
    final destino = File(
      'android/app/src/main/res/drawable/ic_notificacao_grande.png',
    );
    await destino.writeAsBytes(png!.buffer.asUint8List());
    expect(await destino.exists(), isTrue);
  });
}
