import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Foto do cupom fiscal no aparelho.
///
/// O `image_picker` entrega a imagem num arquivo do **cache** do app, que o
/// sistema pode apagar quando precisar de espaço. Guardar esse caminho no
/// banco (como o app fazia) deixava uma referência que podia apodrecer: a foto
/// "do cupom" simplesmente desaparecia. Aqui a imagem é copiada para os
/// documentos do app — mesmo tratamento da foto do avatar
/// (`lib/widgets/avatar.dart`) — e é essa cópia que vai para o banco.
///
/// Tudo é **best-effort**: a foto é um extra do lançamento, então nenhuma
/// falha de arquivo pode impedir o usuário de salvar (ou excluir) um gasto.

/// Prefixo dos arquivos guardados pelo app (`cupom_<carimbo>.<ext>`).
///
/// Serve de assinatura do arquivo: só é apagado o que tem esse prefixo **e**
/// está dentro dos documentos do app, então um caminho estranho vindo do banco
/// (backup editado à mão, por exemplo) nunca apaga um arquivo qualquer do
/// aparelho.
const String kPrefixoFotoCupom = 'cupom_';

/// Pasta onde o app guarda as fotos de cupom (documentos do app).
Future<Directory> pastaFotosCupom() => getApplicationDocumentsDirectory();

/// Copia [origem] para [destino] com nome próprio do app e devolve o caminho
/// definitivo.
///
/// O nome leva um carimbo de tempo (microssegundos) e, se por acaso já existir
/// um arquivo com esse nome, um sufixo numérico — nada é sobrescrito.
/// O diretório é criado se ainda não existir.
///
/// Recebe o [destino] por parâmetro (em vez de resolver o diretório aqui) para
/// poder ser testada sem plugins.
Future<String> salvarFotoCupom(File origem, Directory destino) async {
  await destino.create(recursive: true);
  final ext =
      p.extension(origem.path).isEmpty ? '.jpg' : p.extension(origem.path);
  final carimbo = DateTime.now().microsecondsSinceEpoch;
  var arquivo = File(p.join(destino.path, '$kPrefixoFotoCupom$carimbo$ext'));
  var sufixo = 1;
  while (await arquivo.exists()) {
    arquivo =
        File(p.join(destino.path, '$kPrefixoFotoCupom$carimbo-$sufixo$ext'));
    sufixo++;
  }
  return (await origem.copy(arquivo.path)).path;
}

/// `true` quando [caminho] aponta para um arquivo dentro de [dir].
///
/// Caminhos são normalizados antes da comparação, então `..` e caminhos
/// relativos não escapam da checagem (`dir/../outro.jpg` conta como fora).
bool arquivoDentroDe(String caminho, Directory dir) {
  if (caminho.trim().isEmpty) return false;
  final alvo = p.normalize(p.absolute(caminho));
  final raiz = p.normalize(p.absolute(dir.path));
  return p.isWithin(raiz, alvo);
}

/// `true` quando dá para apagar [caminho] com segurança: é uma foto guardada
/// **pelo app** (prefixo [kPrefixoFotoCupom]) dentro de [dir].
bool fotoCupomPodeSerApagada(String caminho, Directory dir) =>
    p.basename(caminho).startsWith(kPrefixoFotoCupom) &&
    arquivoDentroDe(caminho, dir);

/// Apaga a foto do cupom guardada pelo app (ex.: lançamento excluído).
///
/// Recusa caminhos que não sejam fotos do app (veja
/// [fotoCupomPodeSerApagada]) e ignora falhas: o pior caso é um arquivo órfão
/// de alguns KB. Vale para a foto compartilhada pelas parcelas — quem decide
/// se ela ainda é usada é o chamador.
///
/// [dir] existe para o teste rodar sem o `path_provider`; em produção fica
/// `null` e a pasta é resolvida por [pastaFotosCupom].
Future<void> apagarFotoCupom(String? caminho, {Directory? dir}) async {
  if (caminho == null || caminho.trim().isEmpty) return;
  try {
    final destino = dir ?? await pastaFotosCupom();
    if (!fotoCupomPodeSerApagada(caminho, destino)) return;
    final arquivo = File(caminho);
    if (await arquivo.exists()) await arquivo.delete();
  } catch (_) {
    // Best-effort: nunca deve impedir a exclusão do lançamento.
  }
}

/// Apaga a cópia temporária deixada pelo `image_picker` depois que a foto já
/// foi guardada nos documentos do app.
///
/// Só apaga arquivos de dentro do diretório temporário do app — em qualquer
/// outro caminho não encosta (a foto pode ter sido escolhida de um local que o
/// sistema gerencia). Best-effort: o cache é limpo pelo Android de qualquer
/// forma.
///
/// [dir] existe para o teste rodar sem o `path_provider`; em produção fica
/// `null` e o diretório é o cache do app.
Future<void> apagarCopiaTemporaria(String? caminho, {Directory? dir}) async {
  if (caminho == null || caminho.trim().isEmpty) return;
  try {
    final cache = dir ?? await getTemporaryDirectory();
    if (!arquivoDentroDe(caminho, cache)) return;
    final arquivo = File(caminho);
    if (await arquivo.exists()) await arquivo.delete();
  } catch (_) {
    // Best-effort: o sistema também limpa o cache por conta própria.
  }
}
