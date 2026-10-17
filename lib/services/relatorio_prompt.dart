// Prompt do relatório por I.A.: system + usuário, no idioma do app.
//
// Os dados entram entre <dados></dados> e o system prompt deixa claro que
// aquilo é **dado, não instrução** — texto vindo dos lançamentos (descrição,
// estabelecimento) nunca pode virar ordem para o modelo.
import '../l10n/app_strings.dart';
import 'relatorio_contexto.dart';

/// System + user prompt de uma geração do relatório.
class PromptRelatorio {
  final String system;
  final String user;

  const PromptRelatorio({required this.system, required this.user});
}

/// Monta o prompt de [contexto] no idioma de [strings] (frases de
/// `iaSystemPrompt`/`iaPedidoRelatorio` em `lib/l10n/`).
PromptRelatorio montarPromptRelatorio({
  required RelatorioContexto contexto,
  required AppStrings strings,
}) =>
    PromptRelatorio(
      system: strings.iaSystemPrompt,
      user: strings.iaPedidoRelatorio(contexto.json),
    );
