import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Registro **local** de falhas do app.
///
/// O Flutter engole exceções em release: elas viram um quadro cinza na tela e
/// o detalhe só vai para o `logcat`, que ninguém abre — nem o usuário, nem quem
/// desenvolve o app. Aqui os três pontos cegos (`FlutterError.onError`,
/// `PlatformDispatcher.onError` e `ErrorWidget.builder`) passam a gravar num
/// arquivo dentro da área privada do app.
///
/// Regras do módulo, todas alinhadas ao "100% local" do Mango:
///
/// - **nada sai daqui sozinho**: o arquivo só é exibido/compartilhado pela
///   tela *Diagnóstico*, e o compartilhamento começa com o toque do usuário;
/// - **nunca quebra o app**: gravar falha é *best-effort* — qualquer erro de
///   arquivo é engolido, porque pior do que uma falha não registrada é uma
///   falha que trava a gravação de outra falha;
/// - **nunca atrasa a tela**: o caminho síncrono (`registrarFalha`) só
///   enfileira a escrita, que roda fora do frame;
/// - **não cresce sem limite**: teto de tamanho com rotação e eventos
///   idênticos consecutivos somados (`×N`), para um erro em loop não inundar
///   o arquivo.

/// Nome do arquivo de log (uma falha por linha, formato JSON Lines).
const String kNomeArquivoFalhas = 'falhas.jsonl';

/// Teto do arquivo: passou disso e os eventos mais antigos são descartados.
const int kTetoFalhasBytes = 200 * 1024;

/// Teto do texto do erro (uma mensagem absurda não pode ocupar o arquivo inteiro).
const int kTetoErroChars = 1200;

/// Teto da pilha de chamadas (uma pilha completa já cabe; o que vem depois
/// costuma ser repetição de bootstrap).
const int kTetoStackChars = 4000;

/// Uma falha registrada.
class EventoFalha {
  const EventoFalha({
    required this.quando,
    required this.erro,
    this.stack,
    this.contexto,
    this.repetido = 1,
  });

  /// Quando aconteceu (primeira ocorrência, quando houve repetição).
  final DateTime quando;

  final String erro;
  final String? stack;

  /// De onde veio, ex.: `ocr`, `widgets library`, `não tratado`.
  final String? contexto;

  /// Quantas vezes o mesmo evento (erro + pilha + contexto) se repetiu em
  /// sequência; 1 = aconteceu uma vez.
  final int repetido;
}

/// Corta [texto] em [limite] caracteres, deixando nota do que ficou de fora.
///
/// Função pura: usada no erro e na pilha antes de gravar, para um objeto
/// gigante não ocupar o arquivo sozinho.
String cortarTexto(String texto, int limite) {
  if (texto.length <= limite) return texto;
  final restantes = texto.length - limite;
  return '${texto.substring(0, limite)}\n… (+$restantes caracteres cortados)';
}

/// `29/09/2026 08:15:03` — sem depender de locale, para o texto ficar
/// idêntico em teste e em aparelho.
String formatarQuando(DateTime quando) {
  String dois(int v) => v.toString().padLeft(2, '0');
  return '${dois(quando.day)}/${dois(quando.month)}/${quando.year} '
      '${dois(quando.hour)}:${dois(quando.minute)}:${dois(quando.second)}';
}

/// Serializa o evento para uma linha do arquivo (JSON Lines).
///
/// Aplica os cortes de tamanho; se mesmo assim o texto não for serializável
/// (caractere inválido no meio de uma exceção, por exemplo), grava uma versão
/// reduzida — perder detalhe é melhor que perder o evento.
String montarLinha(EventoFalha evento) {
  final quando = evento.quando.toIso8601String();
  final erro = cortarTexto(evento.erro, kTetoErroChars);
  final stack = evento.stack == null
      ? null
      : cortarTexto(evento.stack!, kTetoStackChars);
  try {
    return jsonEncode(<String, Object?>{
      'quando': quando,
      if (evento.contexto != null) 'contexto': evento.contexto,
      'erro': erro,
      if (stack != null) 'stack': stack,
      if (evento.repetido > 1) 'repetido': evento.repetido,
    });
  } catch (_) {
    return jsonEncode(<String, Object?>{
      'quando': quando,
      if (evento.contexto != null) 'contexto': evento.contexto,
      'erro': 'falha sem detalhes (texto não serializável)',
    });
  }
}

/// Lê uma linha do arquivo; `null` quando a linha não é um evento válido
/// (arquivo cortado no meio, corrompido, formato futuro...).
///
/// Linhas ruins são ignoradas por quem chama: um log quebrado nunca impede a
/// leitura do que restou dele.
EventoFalha? lerLinha(String linha) {
  try {
    final bruto = jsonDecode(linha);
    if (bruto is! Map<String, dynamic>) return null;
    final quando = DateTime.tryParse('${bruto['quando']}');
    final erro = bruto['erro'];
    if (quando == null || erro is! String || erro.isEmpty) return null;
    final stack = bruto['stack'];
    final contexto = bruto['contexto'];
    final repetido = bruto['repetido'];
    return EventoFalha(
      quando: quando,
      erro: erro,
      stack: stack is String && stack.isNotEmpty ? stack : null,
      contexto: contexto is String && contexto.isNotEmpty ? contexto : null,
      repetido: repetido is int && repetido > 1 ? repetido : 1,
    );
  } catch (_) {
    return null;
  }
}

/// `true` quando [a] e [b] são a **mesma** falha, ignorando quando aconteceu
/// e quantas vezes: é o que permite somar repetições seguidas em vez de
/// encher o arquivo com a mesma pilha.
bool mesmoEvento(EventoFalha a, EventoFalha b) =>
    a.erro == b.erro && a.stack == b.stack && a.contexto == b.contexto;

/// Texto legível de um evento — o que a tela *Diagnóstico* mostra e o que
/// vai no compartilhamento.
String formatarEvento(EventoFalha evento) {
  final vezes = evento.repetido > 1 ? ' (×${evento.repetido})' : '';
  final onde = evento.contexto == null ? '' : ' · ${evento.contexto}';
  final buffer = StringBuffer('${formatarQuando(evento.quando)}$onde$vezes\n');
  buffer.writeln(evento.erro);
  if (evento.stack != null && evento.stack!.trim().isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Pilha de chamadas:')
      ..write(evento.stack);
  }
  return buffer.toString();
}

/// Mantém o conteúdo dentro de [limiteBytes] descartando os eventos mais
/// antigos (nunca o mais novo). Com o arquivo só de um evento maior que o
/// teto, devolve vazio — os cortes de [montarLinha] tornam esse caso quase
/// impossível em produção.
///
/// Função pura, para o teste cobrir o limite sem precisar de um arquivo de
/// 200 KB.
String rotacionarConteudo(String conteudo, int limiteBytes) {
  final linhas =
      conteudo.split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (linhas.isEmpty) return '';
  var total = utf8.encode(linhas.join('\n')).length;
  while (linhas.length > 1 && total > limiteBytes) {
    total -= utf8.encode(linhas.first).length + 1; // linha + \n
    linhas.removeAt(0);
  }
  if (total > limiteBytes) return '';
  return linhas.join('\n');
}

/// Diretório resolvido uma vez (economiza `path_provider` em cada falha).
Directory? _dirResolvido;

/// Onde o log será gravado; [dir] existe para teste rodar sem plugin.
Future<File> arquivoDeFalhas({Directory? dir}) async {
  final destino =
      dir ?? _dirResolvido ?? await getApplicationDocumentsDirectory();
  if (dir == null) _dirResolvido = destino;
  await destino.create(recursive: true);
  return File(p.join(destino.path, kNomeArquivoFalhas));
}

/// Resolve o diretório e cria o arquivo vazio, para o primeiro erro do app
/// (inclusive dos primeiros frames) já ter onde cair.
Future<void> iniciarLogDeFalhas({Directory? dir}) async {
  try {
    final arquivo = await arquivoDeFalhas(dir: dir);
    if (!await arquivo.exists()) await arquivo.create();
  } catch (_) {
    // Best-effort: sem log ainda não é motivo para não abrir o app.
  }
}

/// Fila de escrita: uma falha atrás da outra, para o arquivo nunca ficar
/// meio-escrito por escritas concorrentes.
Future<void> _fila = Future<void>.value();

Future<void> _enfileirar(Future<void> Function() tarefa) {
  // A tarefa tem try/catch próprio, mas mesmo assim o futuro entregue aqui
  // tem erro engolido: quem chama um "registre esta falha" não pode acabar
  // recebendo uma nova falha em troca.
  final resultado = _fila.then((_) => tarefa());
  _fila = resultado.then<void>((_) {}, onError: (_) {});
  return _fila;
}

/// Registra [erro] com a pilha e o [contexto] (de onde veio).
///
/// Nunca lança exceção e nunca escreve no disco dentro do frame: a escrita é
/// enfileirada e o futuro devolvido só indica quando ela terminou (usado nos
/// testes). Falha de arquivo é engolida.
Future<void> registrarFalha(
  Object erro,
  StackTrace? stack, {
  String? contexto,
  Directory? dir,
}) {
  return _enfileirar(
    () => _registrar(erro, stack, contexto: contexto, dir: dir),
  );
}

Future<void> _registrar(
  Object erro,
  StackTrace? stack, {
  String? contexto,
  Directory? dir,
}) async {
  try {
    final evento = EventoFalha(
      quando: DateTime.now(),
      erro: erro.toString(),
      stack: stack?.toString(),
      contexto: contexto,
    );
    final arquivo = await arquivoDeFalhas(dir: dir);
    final linhas = <String>[];
    if (await arquivo.exists()) {
      // `allowMalformed`: um arquivo cortado no meio de um caractere não
      // pode derrubar a leitura do resto.
      final bruto =
          utf8.decode(await arquivo.readAsBytes(), allowMalformed: true);
      linhas.addAll(bruto.split('\n').where((l) => l.trim().isNotEmpty));
    }

    // Mesma falha seguida de novo: soma em vez de duplicar a linha.
    final anterior = linhas.isEmpty ? null : lerLinha(linhas.last);
    if (anterior != null && mesmoEvento(anterior, evento)) {
      linhas[linhas.length - 1] = montarLinha(
        EventoFalha(
          quando: anterior.quando,
          erro: anterior.erro,
          stack: anterior.stack,
          contexto: anterior.contexto,
          repetido: anterior.repetido + 1,
        ),
      );
    } else {
      linhas.add(montarLinha(evento));
    }

    await arquivo.writeAsString(
      rotacionarConteudo(linhas.join('\n'), kTetoFalhasBytes),
      flush: true,
    );
  } catch (_) {
    // Best-effort: registrar falha não pode virar outra falha.
  }
}

/// Eventos gravados, do mais antigo para o mais recente; linhas inválidas
/// são ignoradas.
///
/// Lança exceção se o arquivo não puder ser lido — quem chama (a tela de
/// diagnóstico) decide o que mostrar, porque dizer "nenhuma falha" quando na
/// verdade não deu para ler seria pior que uma mensagem de erro.
Future<List<EventoFalha>> lerFalhas({Directory? dir}) async {
  final arquivo = await arquivoDeFalhas(dir: dir);
  if (!await arquivo.exists()) return const [];
  final bruto = utf8.decode(await arquivo.readAsBytes(), allowMalformed: true);
  return bruto
      .split('\n')
      .map(lerLinha)
      .whereType<EventoFalha>()
      .toList(growable: false);
}

/// Apaga o log (botão *Limpar* da tela de diagnóstico).
Future<void> limparFalhas({Directory? dir}) async {
  await _enfileirar(() async {
    final arquivo = await arquivoDeFalhas(dir: dir);
    if (await arquivo.exists()) await arquivo.delete();
  });
}

/// Espera as escritas enfileiradas terminarem (testes).
Future<void> aguardarEscritas() => _fila;

/// Reinicia a fila de escrita.
///
/// **Somente para teste de widget:** um futuro criado dentro de um teste
/// nunca dispara em outro — a zona falsa morre com o teste —, então um teste
/// que encostasse na fila herdada de outro ficaria travado para sempre. A
/// produção tem uma única zona e nunca precisa disto.
@visibleForTesting
void reiniciarFila() => _fila = Future<void>.value();
