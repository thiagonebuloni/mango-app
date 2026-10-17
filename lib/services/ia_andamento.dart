// Marca de geração em andamento para o Diagnóstico capturar crash NATIVO.
//
// Um `abort()` no motor (falha nativa) mata o processo antes de qualquer
// `try/catch` do Dart: a tela de Diagnóstico ficaria vazia justamente na
// falha que mais importa ver. Enquanto a geração roda, um arquivo de marca
// fica no disco; se ele ainda existir na próxima abertura, foi porque o app
// morreu no meio — e aí a falha vira uma entrada legível no log local.
//
// O fluxo (todos best-effort, nunca lançam):
// - `marcarGeracaoIa` — antes de chamar o motor;
// - `limparGeracaoIa` — quando a geração termina, falha ou é cancelada;
// - `verificarGeracaoIaInterrompida` — na abertura do app (chamada pelo
//   `main`): se a marca estiver órfã, registra a falha e apaga a marca.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'crash_log.dart';

/// Nome do arquivo-marca (fora do `falhas.jsonl`, que é só leitura aqui).
const kNomeMarcaGeracaoIa = 'ia_geracao_em_andamento.txt';

/// Contexto usado nas falhas registradas por este módulo (mesmo texto que a
/// tela passa para `registrarFalha` na geração com erro Dart).
const kContextoGeracaoIa = 'relatório por I.A.';

Future<File> _marca({Directory? dir}) async {
  final destino = dir ?? await getApplicationDocumentsDirectory();
  await destino.create(recursive: true);
  return File(p.join(destino.path, kNomeMarcaGeracaoIa));
}

/// Anota que uma geração de relatório começou (gravando o modelo usado).
Future<void> marcarGeracaoIa({required String modelo, Directory? dir}) async {
  try {
    final marca = await _marca(dir: dir);
    await marca.writeAsString(
      '${DateTime.now().toIso8601String()} $modelo',
      flush: true,
    );
  } catch (_) {
    // Best-effort: a marca não pode travar a geração.
  }
}

/// Apaga a marca — geração terminou (bem, com erro ou cancelada).
Future<void> limparGeracaoIa({Directory? dir}) async {
  try {
    final marca = await _marca(dir: dir);
    if (await marca.exists()) await marca.delete();
  } catch (_) {
    // Best-effort.
  }
}

/// Na abertura do app: se sobrou marca, o processo morreu durante a
/// inferência nativa — registra no Diagnóstico e limpa.
///
/// Devolve `true` quando uma interrupção foi registrada (para teste).
Future<bool> verificarGeracaoIaInterrompida({Directory? dir}) async {
  try {
    final marca = await _marca(dir: dir);
    if (!await marca.exists()) return false;
    final detalhe = await marca.readAsString();
    await marca.delete();
    await registrarFalha(
      'O app foi encerrado no meio da geração do relatório por I.A. '
      '(falha nativa do motor, antes de qualquer erro Dart). '
      'Marca: ${detalhe.trim()}',
      null,
      contexto: kContextoGeracaoIa,
      dir: dir,
    );
    return true;
  } catch (_) {
    // Best-effort: nunca quebrar a abertura do app por causa da marca.
    return false;
  }
}