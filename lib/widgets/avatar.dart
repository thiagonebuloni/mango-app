import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n/app_strings.dart';

import '../models/models.dart';

/// Tamanho máximo aceito para a foto do avatar (em bytes).
///
/// O limite existe pelo mesmo motivo do cupom fiscal: recusar arquivos
/// enormes **antes** de decodificar — decodificar uma imagem de dezenas de MB
/// aloca muito mais memória e pode travar o app em aparelhos simples. Fotos de
/// avatar são redimensionadas na origem (`maxWidth`), então este limite só
/// costuma pegar arquivos gigantes da galeria.
const int kMaxAvatarImageBytes = 5 * 1024 * 1024;

/// Largura máxima da foto do avatar ao escolher da galeria/câmera. Reduzir na
/// origem economiza disco e memória: o avatar é exibido pequeno e circular.
const double kAvatarMaxWidth = 1024;

/// Mensagem de erro quando a foto passa do limite, ou `null` se aceitável.
String? validarTamanhoAvatar(int tamanhoBytes, [AppStrings? strings]) {
  if (tamanhoBytes <= kMaxAvatarImageBytes) return null;
  final s = strings ?? AppStrings.of(null);
  return s.imagemAvatarGrande(
      (tamanhoBytes / (1024 * 1024)).toStringAsFixed(1),
      (kMaxAvatarImageBytes / (1024 * 1024)).toStringAsFixed(0));
}

/// Copia a imagem escolhida para a pasta de documentos do app e devolve o
/// caminho definitivo.
///
/// Copiar (em vez de guardar o caminho temporário do `image_picker`) garante
/// que o avatar continue existindo depois que o cache do sistema for limpo.
Future<String> salvarCopiaAvatar(XFile picked) async {
  final dir = await getApplicationDocumentsDirectory();
  final ext = p.extension(picked.path).isEmpty
      ? '.jpg'
      : p.extension(picked.path);
  final destino = p.join(
    dir.path,
    'avatar_${DateTime.now().millisecondsSinceEpoch}$ext',
  );
  await File(picked.path).copy(destino);
  await _limparCopiasAntigas(dir, manter: destino);
  return destino;
}

/// Apaga cópias antigas do avatar, mantendo só o arquivo atual (evita acumular
/// uma foto órfã a cada troca).
Future<void> _limparCopiasAntigas(Directory dir, {required String manter}) async {
  try {
    await for (final f in dir.list()) {
      final nome = p.basename(f.path);
      if (f.path != manter && nome.startsWith('avatar_') && f is File) {
        await f.delete();
      }
    }
  } catch (_) {
    // Limpeza best-effort: nunca deve impedir o salvamento do perfil.
  }
}

/// Tenta apagar um arquivo de avatar (ao remover/trocar a foto). Falhas são
/// ignoradas — o pior caso é um arquivo órfão de poucos KB.
Future<void> apagarArquivoAvatar(String? path) async {
  if (path == null || path.trim().isEmpty) return;
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {
    // Best-effort.
  }
}

/// Avatar do perfil: foto recortada em círculo quando há imagem, emoticon
/// caso contrário (ou se a foto não puder ser lida — arquivo apagado fora do
/// app, por exemplo).
///
/// O "recorte" é a combinação de [UserProfile.avatarAlignX]/[avatarAlignY]
/// (posição) com [UserProfile.avatarZoom] (zoom), aplicados sobre a imagem com
/// `BoxFit.cover` dentro de um círculo.
class ProfileAvatar extends StatelessWidget {
  final UserProfile? perfil;
  final double radius;
  final double fontSize;
  final Color backgroundColor;

  const ProfileAvatar({
    super.key,
    required this.perfil,
    required this.radius,
    required this.fontSize,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = perfil?.avatar ?? UserProfile.avatarPadrao;
    final foto = perfil?.avatarImagePath;
    if (foto == null || foto.trim().isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: Text(avatar, style: TextStyle(fontSize: fontSize)),
      );
    }
    final ax = (perfil?.avatarAlignX ?? 0).clamp(-1.0, 1.0);
    final ay = (perfil?.avatarAlignY ?? 0).clamp(-1.0, 1.0);
    final zoom = (perfil?.avatarZoom ?? 1).clamp(1.0, 3.0);
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: Transform.scale(
            scale: zoom,
            child: Image.file(
              File(foto),
              fit: BoxFit.cover,
              alignment: Alignment(ax, ay),
              errorBuilder: (_, _, _) =>
                  Text(avatar, style: TextStyle(fontSize: fontSize)),
            ),
          ),
        ),
      ),
    );
  }
}
