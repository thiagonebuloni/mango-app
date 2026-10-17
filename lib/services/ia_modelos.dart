// Descoberta dos modelos de I.A. instalados no aparelho (formato LiteRT:
// `.litertlm` e o legado `.task`).
//
// Por enquanto o modelo chega por fora (tool/install_modelo_ia.sh, via adb):
// nenhuma permissão de rede é necessária e o app segue 100% offline. As duas
// pastas abaixo são específicas do app — legíveis sem permissão e escritas
// pelo script.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ia_aparelho.dart';

/// Um arquivo de modelo de I.A. (LiteRT) encontrado no aparelho.
class ModeloIa {
  final String caminho;
  final int tamanhoBytes;

  const ModeloIa({required this.caminho, required this.tamanhoBytes});

  String get nome => p.basename(caminho);

  String get tamanhoLabel => formatarTamanho(tamanhoBytes);
}

/// Extensão de modelo que o motor LiteRT carrega: o pacote `.litertlm`.
///
/// O legado `.task` (MediaPipe) não entra aqui — o motor registrado é só o
/// LiteRT-LM; se um dia precisar de `.task`, basta registrar também o
/// `MediaPipeEngine` do `flutter_edge_ai_mediapipe`.
const _extensoesModelo = {'.litertlm'};

/// Formata bytes em KB/MB/GB para mostrar no app.
String formatarTamanho(int bytes) {
  const kb = 1024.0;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(0)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// Pastas procuradas pelo app: documentos privados e a pasta externa do app
/// (ambas em `models/`). A externa é a que o `adb push` alcança em qualquer
/// build, inclusive release.
Future<List<Directory>> pastasModelosIa() async {
  final documentos = await getApplicationDocumentsDirectory();
  final pastas = [Directory(p.join(documentos.path, 'models'))];
  final externa = await AparelhoLocal.pastaAppExterna();
  if (externa != null) pastas.add(Directory(p.join(externa.path, 'models')));
  return pastas;
}

/// Lista os modelos disponíveis, **menor primeiro** — nos aparelhos de teste
/// a classe 0.6B é a prioritária, e o padrão da tela é o primeiro da lista.
///
/// A dedução é pelo **nome normalizado** do arquivo (minúsculas, `-` e `_`
/// tratados como iguais): o mesmo `qwen....litertlm` pode existir nas duas
/// pastas (por um push manual duplicado) e não pode aparecer duas vezes na
/// lista. Vale o da pasta de documentos (privada).
Future<List<ModeloIa>> descobrirModelosIa() async {
  final encontrados = <ModeloIa>[];
  final nomesVistos = <String>{};
  final pastas = await pastasModelosIa();
  // Documentos (privado) primeiro: tem prioridade no desempate de nome.
  final pastasOrdenadas = [
    ...pastas.where((pasta) => !externo(pasta.path)),
    ...pastas.where((pasta) => externo(pasta.path)),
  ];
  for (final pasta in pastasOrdenadas) {
    if (!await pasta.exists()) continue;
    await for (final entidade in pasta.list()) {
      if (entidade is! File) continue;
      final ext = p.extension(entidade.path).toLowerCase();
      if (!_extensoesModelo.contains(ext)) continue;
      // Mesmo nome em duas pastas = o mesmo modelo (cópia interna): uma vez só.
      if (!nomesVistos.add(normalizarNomeModelo(entidade.path))) continue;
      encontrados.add(
        ModeloIa(caminho: entidade.path, tamanhoBytes: await entidade.length()),
      );
    }
  }
  encontrados.sort((a, b) => a.tamanhoBytes.compareTo(b.tamanhoBytes));
  return encontrados;
}

/// Normaliza o nome do arquivo para dedução: um `.litertlm` digitado na mão
/// (`qwen3-0.6b.litertlm`) é o mesmo modelo que a cópia interna
/// (`qwen3_0_6b.litertlm`) — e não pode aparecer duas vezes na lista.
String normalizarNomeModelo(String caminho) =>
    p.basename(caminho).toLowerCase().replaceAll('-', '_');

/// `true` para caminhos no armazenamento externo/emulado (`/sdcard/...`,
/// `/storage/...`), onde o `mmap` nativo falha ou corrompe a leitura.
bool externo(String caminho) =>
    caminho.startsWith('/sdcard/') || caminho.startsWith('/storage/');
