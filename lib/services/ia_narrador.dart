// Narrador do relatório: transforma o prompt preparado em texto corrido.
//
// Abstração proposital: trocar a engine de inferência (Flutter Edge AI /
// LiteRT-LM hoje) não mexe em quem chama a tela — e os testes usam um
// narrador fake.
import 'dart:async';
import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:path/path.dart' as p;

/// Narrador de relatórios por I.A.
abstract class NarradorIa {
  /// Gera o relatório devolvendo o texto em pedaços (streaming).
  ///
  /// Os pedaços são **deltas** (só o texto novo): quem chama acumula.
  Stream<String> narrar({required String system, required String user});

  /// Para a geração em andamento, se houver.
  void cancelar();
}

/// Implementação com Flutter Edge AI + motor LiteRT-LM
/// (`flutter_edge_ai` / `flutter_edge_ai_litertlm`): inferência no aparelho
/// via `dart:ffi` sobre a API C do LiteRT-LM, sem binário C/C++ gerenciado à
/// mão — a biblioteca nativa chega por *native assets* no build, verificada
/// por SHA-256, com permissões e regras de release resolvidas pelo pacote.
///
/// Ciclo de uma geração (todos os passos com erro legível em Dart):
/// 1. valida o arquivo do modelo (assinatura `LITERTLM`, tamanho);
/// 2. registra o motor (uma vez por processo);
/// 3. instala/ativa o arquivo (`FileSource` **não copia**: registra o
///    caminho direto — sem duplicar centenas de MB);
/// 4. abre o modelo nativo (contexto de 2048 tokens) e a conversa com o
///    system prompt do app, teto de [maxTokensSaida] tokens de resposta e
///    semente fixa (mesmo relatório, mesma saída);
/// 5. faz o stream dos deltas e libera chat + modelo no fim — a RAM do
///    modelo não fica presa entre gerações (o próximo recarrega).
///
/// `cancelar` é de verdade: chama `stopGeneration()` (para o decode no
/// nativo), fecha chat e modelo e encerra o stream.
///
/// Limitação conhecida: a família do modelo ([ModelType]) é escolhida pelo
/// nome do arquivo — um modelo renomeado além do reconhecível cai em
/// [ModelType.general] (para `.litertlm` o template de chat vem do próprio
/// bundle, então o efeito é só na amostragem padrão).
class NarradorLiteRt implements NarradorIa {
  NarradorLiteRt({
    required this.caminhoModelo,
    this.temperatura = 0.4,
    this.maxTokensSaida = 350,
    this.semente = 42,
  });

  final String caminhoModelo;

  /// Amostragem com viés para conteúdo (relatório, não criatividade).
  final double temperatura;

  /// Teto de tokens gerados (resposta — não confundir com o contexto).
  final int maxTokensSaida;

  /// Semente da amostragem: relatório é conteúdo, não criatividade.
  final int semente;

  /// Registro do motor: uma vez por processo, compartilhado entre gerações.
  static Future<void>? _motorPronto;

  /// Caminho já registrado como modelo ativo nesta sessão (o registro
  /// persiste em disco; reinstalar é barato, mas evita trabalho à toa).
  static String? _caminhoInstalado;

  static Future<void> _inicializarMotor() => _motorPronto ??=
      FlutterEdgeAi.initialize(inferenceEngines: const [LiteRtLmEngine()]);

  InferenceModel? _modelo;
  InferenceChat? _chat;
  bool _cancelado = false;

  @override
  Stream<String> narrar({
    required String system,
    required String user,
  }) async* {
    _cancelado = false;
    // Validação local antes de qualquer chamada nativa: arquivo corrompido,
    // incompleto ou de outro motor vira mensagem legível — falha Dart
    // (registrada no Diagnóstico), não crash mudo como um abort nativo.
    final caminho = await _prepararModelo(caminhoModelo);

    await _inicializarMotor();

    if (_caminhoInstalado != caminho) {
      await FlutterEdgeAi.installModel(
        modelType: tipoModeloPeloNome(caminho),
        fileType: ModelFileType.litertlm,
      ).fromFile(caminho).install();
      _caminhoInstalado = caminho;
    }
    if (_cancelado) return;

    final modelo = await FlutterEdgeAi.getActiveModel(maxTokens: 2048);
    if (_cancelado) {
      await modelo.close();
      return;
    }
    _modelo = modelo;

    final chat = await modelo.createChat(
      systemInstruction: system,
      temperature: temperatura,
      randomSeed: semente,
      maxOutputTokens: maxTokensSaida,
    );
    _chat = chat;
    try {
      await chat.addQueryChunk(Message.text(text: user, isUser: true));
      await for (final resposta in chat.generateChatResponseAsync()) {
        // Delta de texto puro: o filtro do pacote já esconde o raciocínio
        // (ThinkingResponse) — quem chama nunca vê <think>.
        if (resposta is TextResponse && resposta.token.isNotEmpty) {
          yield resposta.token;
        }
      }
    } finally {
      await _liberar();
    }
  }

  @override
  void cancelar() {
    _cancelado = true;
    // Sem esperar na tela: para o decode no nativo (quando já existe chat)
    // e solta a RAM do modelo; o `finally` de `narrar` reforça (idempotente).
    unawaited(_parar());
  }

  Future<void> _parar() async {
    try {
      await _chat?.stopGeneration();
    } catch (_) {
      // Parar não pode virar outra falha.
    }
    await _liberar();
  }

  /// Descarta chat e modelo (idempotente — `_parar` e o `finally` de
  /// `narrar` podem correr um logo após o outro).
  Future<void> _liberar() async {
    final chat = _chat;
    final modelo = _modelo;
    _chat = null;
    _modelo = null;
    try {
      await chat?.close();
      await modelo?.close();
    } catch (_) {
      // Liberar recursos não pode virar outra falha na tela.
    }
  }
}

/// Família do modelo pelo nome do arquivo — escolhe o template/amostragem
/// ([ModelType]), não o formato (isso é [ModelFileType], fixo em
/// `.litertlm` aqui). A ordem importa: `qwen35` precisa ser testado antes de
/// `qwen3` (um "Qwen3.5" contém "qwen3").
ModelType tipoModeloPeloNome(String caminho) {
  final n = p.basename(caminho).toLowerCase();
  if (n.contains('qwen3.5') || n.contains('qwen35')) return ModelType.qwen35;
  if (n.contains('qwen3')) return ModelType.qwen3;
  if (n.contains('qwen')) return ModelType.qwen;
  if (n.contains('gemma-4') || n.contains('gemma4')) return ModelType.gemma4;
  if (n.contains('gemma')) return ModelType.gemmaIt;
  if (n.contains('deepseek')) return ModelType.deepSeek;
  if (n.contains('hammer')) return ModelType.hammer;
  if (n.contains('phi')) return ModelType.phi;
  return ModelType.general;
}

/// Valida o arquivo do modelo e devolve o caminho que o motor deve carregar.
///
/// A validação é só local (sem cópia e sem nativo): existe, formato
/// reconhecido, tamanho razoável e assinatura do contêiner — para que um
/// download truncado ou um arquivo de outro motor vire mensagem legível.
Future<String> _prepararModelo(String caminho) async {
  final arquivo = File(caminho);
  final extensao = p.extension(caminho).toLowerCase();
  if (extensao == '.gguf') {
    // Formato do motor antigo (llama.cpp), não lido pelo LiteRT — deixar claro
    // em vez de um erro genérico de arquivo inválido.
    throw ModeloIaException(
      '$caminho é um modelo GGUF, do motor antigo do app — o motor atual '
      'lê arquivos .litertlm. Baixe o modelo certo com '
      'sh tool/install_modelo_ia.sh',
    );
  }
  if (extensao == '.task' || extensao == '.tflite') {
    throw ModeloIaException(
      'o arquivo $caminho é ${extensao.substring(1)}, formato que o motor '
      'atual não roda — o app usa .litertlm: rode '
      'sh tool/install_modelo_ia.sh',
    );
  }
  if (!await arquivo.exists()) {
    throw ModeloIaException('arquivo de modelo não encontrado: $caminho');
  }
  final tamanho = await arquivo.length();
  if (tamanho < 1024 * 1024) {
    throw ModeloIaException(
      'arquivo de modelo muito pequeno ($tamanho bytes): '
      'o download pode estar incompleto — rode de novo '
      'sh tool/install_modelo_ia.sh',
    );
  }
  final acesso = await arquivo.open();
  try {
    final cabeca = await acesso.read(8);
    final ok = switch (extensao) {
      // Assinatura ASCII `LITERTLM` (8 bytes) do pacote LiteRT-LM.
      '.litertlm' => cabeca.length >= 8 &&
          String.fromCharCodes(cabeca.sublist(0, 8)) == 'LITERTLM',
      // Extensão desconhecida: só o tamanho acima garante algo razoável.
      _ => true,
    };
    if (!ok) {
      throw ModeloIaException(
        'o arquivo $caminho não bate com a assinatura do formato '
        '${extensao.isEmpty ? 'de modelo' : extensao.substring(1)} — '
        'baixe de novo com sh tool/install_modelo_ia.sh',
      );
    }
  } finally {
    await acesso.close();
  }
  return arquivo.path;
}

/// Erro legível da validação local do modelo (antes da engine nativa).
class ModeloIaException implements Exception {
  const ModeloIaException(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}
