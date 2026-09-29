import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

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
    try {
      await SharePlus.instance.share(
        ShareParams(text: _textoCompleto, title: 'Diagnóstico Mango'),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Não foi possível compartilhar: $e')),
      );
    }
  }

  Future<void> _copiar() async {
    if (_eventos == null || _eventos!.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: _textoCompleto));
      messenger.showSnackBar(const SnackBar(content: Text('Registro copiado.')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Não foi possível copiar: $e')),
      );
    }
  }

  Future<void> _limpar() async {
    if (_eventos == null || _eventos!.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apagar o registro?'),
        content: const Text(
          'As falhas listadas serão apagadas deste aparelho. Se você ainda '
          'precisar delas para um suporte, compartilhe antes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    await limparFalhas(dir: widget.dir);
    if (!mounted) return;
    setState(() => _eventos = const <EventoFalha>[]);
    messenger.showSnackBar(
      const SnackBar(content: Text('Registro de falhas apagado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventos = _eventos;
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnóstico')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Falhas acontecidas neste aparelho. Nada é enviado '
              'automaticamente: só sai daqui se você tocar em Compartilhar e '
              'escolher o destino. O backup em CSV não inclui este registro.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
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
              label: const Text('Compartilhar'),
            ),
            OutlinedButton.icon(
              onPressed: eventos != null && eventos.isNotEmpty ? _copiar : null,
              icon: const Icon(Icons.copy),
              label: const Text('Copiar'),
            ),
            TextButton.icon(
              onPressed: eventos != null && eventos.isNotEmpty ? _limpar : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Limpar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _corpo(List<EventoFalha>? eventos) {
    if (eventos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_falhaLeitura) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Não foi possível ler o registro de falhas neste aparelho.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (eventos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Nenhuma falha registrada',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'Quando algo quebrar por aqui, o detalhe aparece nesta tela — '
                'pronto para você compartilhar, se quiser.',
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
