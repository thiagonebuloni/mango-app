import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_locale.dart';
import '../services/crash_log.dart';

/// Tela **Diagnóstico**: as falhas registradas no próprio aparelho.
///
/// É o único lugar que lê o log de falhas, e ela não faz nada sozinha: o
/// arquivo só sai do aparelho quando o usuário toca em *Compartilhar* e
/// escolhe o destino na folha do sistema. O backup em CSV não inclui este
/// registro — ele é material de suporte, não dado do app.
class DiagnosticoScreen extends StatefulWidget {
  const DiagnosticoScreen({super.key, this.dir});

  /// Onde o log está; `null` = documentos do app. Existe para o teste rodar
  /// com um diretório próprio, sem `path_provider`.
  final Directory? dir;

  @override
  State<DiagnosticoScreen> createState() => _DiagnosticoScreenState();
}

class _DiagnosticoScreenState extends State<DiagnosticoScreen> {
  /// `null` = ainda carregando.
  List<EventoFalha>? _eventos;
  bool _falhaLeitura = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      // Espera escrita pendente: um toque aqui logo depois de um erro não
      // pode mostrar a tela vazia.
      await aguardarEscritas();
      final eventos = await lerFalhas(dir: widget.dir);
      if (!mounted) return;
      setState(() => _eventos = eventos.reversed.toList(growable: false));
    } catch (_) {
      // Não dá para ler: mostrar "nenhuma falha" seria mentir.
      if (!mounted) return;
      setState(() {
        _eventos = const <EventoFalha>[];
        _falhaLeitura = true;
      });
    }
  }

  String get _textoCompleto => (_eventos ?? const <EventoFalha>[])
      .map(formatarEvento)
      .join('\n\n──────────\n\n');

  Future<void> _compartilhar() async {
    if (_eventos == null || _eventos!.isEmpty) return;
    // Captura o messenger antes do `await`: depois de abrir a folha do
    // sistema o contexto pode já não estar mais montado.
    final messenger = ScaffoldMessenger.of(context);
    final s = context.strings;
    try {
      await SharePlus.instance.share(
        ShareParams(text: _textoCompleto, title: '${s.diagnostico} Mango'),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.naoCompartilhar('$e'))),
      );
    }
  }

  Future<void> _copiar() async {
    if (_eventos == null || _eventos!.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final s = context.strings;
    try {
      await Clipboard.setData(ClipboardData(text: _textoCompleto));
      messenger.showSnackBar(SnackBar(content: Text(s.registroCopiado)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.naoCopiar('$e'))),
      );
    }
  }

  Future<void> _limpar() async {
    if (_eventos == null || _eventos!.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final s = context.strings;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.apagarRegistro),
        content: Text(s.apagarRegistroMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.nao),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.apagar),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    await limparFalhas(dir: widget.dir);
    if (!mounted) return;
    setState(() => _eventos = const <EventoFalha>[]);
    messenger.showSnackBar(
      SnackBar(content: Text(s.registroApagado)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventos = _eventos;
    final s = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(s.diagnostico)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              s.diagnosticoDetalhe,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(child: _corpo(eventos)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed:
                  eventos != null && eventos.isNotEmpty ? _compartilhar : null,
              icon: const Icon(Icons.share),
              label: Text(s.compartilhar),
            ),
            OutlinedButton.icon(
              onPressed: eventos != null && eventos.isNotEmpty ? _copiar : null,
              icon: const Icon(Icons.copy),
              label: Text(s.copiar),
            ),
            TextButton.icon(
              onPressed: eventos != null && eventos.isNotEmpty ? _limpar : null,
              icon: const Icon(Icons.delete_outline),
              label: Text(s.limpar),
            ),
          ],
        ),
      ),
    );
  }

  Widget _corpo(List<EventoFalha>? eventos) {
    final s = context.strings;
    if (eventos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_falhaLeitura) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            s.falhaLeitura,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (eventos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                s.nenhumaFalha,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                s.nenhumaFalhaDetalhe,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      itemCount: eventos.length,
      itemBuilder: (context, i) => _cartao(eventos[i]),
    );
  }

  Widget _cartao(EventoFalha evento) {
    final primeiraLinha = evento.erro.split('\n').first;
    final vezes = evento.repetido > 1 ? ' (×${evento.repetido})' : '';
    final titulo = evento.contexto == null
        ? formatarQuando(evento.quando)
        : '${formatarQuando(evento.quando)} · ${evento.contexto}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ExpansionTile(
        shape: const Border(),
        title: Text(titulo, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          '$primeiraLinha$vezes',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SelectableText(
              formatarEvento(evento),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
