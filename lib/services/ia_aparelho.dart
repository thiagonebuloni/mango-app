// Leituras simples do aparelho para a tela do relatório por I.A. (aviso de
// memória e pasta externa do app, onde o tool/install_modelo_ia.sh deixa o
// modelo). Canal interno `mango/aparelho`, implementado na MainActivity.kt —
// só números/caminhos do próprio sistema, nada sai do aparelho. Fora do
// Android (ou em ambiente sem canal) tudo devolve `null` e o app segue.
import 'dart:io';

import 'package:flutter/services.dart';

class AparelhoLocal {
  static const MethodChannel _canal = MethodChannel('mango/aparelho');

  /// Memória livre em bytes, ou `null` quando a plataforma não responde.
  static Future<int?> memoriaLivreBytes() => _pedir<int>('memoriaLivre');

  /// Pasta externa do app (`Android/data/<pkg>/files`), legível sem
  /// permissão — o destino do script de instalação do modelo.
  static Future<Directory?> pastaAppExterna() async {
    final caminho = await _pedir<String>('pastaExterna');
    return caminho == null ? null : Directory(caminho);
  }

  static Future<T?> _pedir<T>(String metodo) async {
    try {
      return await _canal.invokeMethod<T>(metodo);
    } catch (_) {
      return null;
    }
  }
}
