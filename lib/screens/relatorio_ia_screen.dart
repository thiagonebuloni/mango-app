// Tela do relatório do período gerada por I.A. local (botão da aba
// Relatórios). O modelo só narra: todos os números vêm do
// `RelatorioContexto`, calculado em Dart sobre o banco — e nada sai do
// aparelho.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_locale.dart';
import '../l10n/app_strings.dart';
import '../l10n/l10n_format.dart';
import '../services/ia_aparelho.dart';
import '../services/ia_andamento.dart';
import '../services/ia_modelos.dart';
import '../services/ia_narrador.dart';
import '../services/crash_log.dart';
import '../services/relatorio_contexto.dart';
import '../services/relatorio_prompt.dart';
import '../state/providers.dart';

/// Relatório de [periodo] escrito por um modelo de I.A. rodando no aparelho.
class RelatorioIaScreen extends ConsumerStatefulWidget {
  final PeriodRange periodo;

  const RelatorioIaScreen({super.key, required this.periodo});

  @override
  ConsumerState<RelatorioIaScreen> createState() => _RelatorioIaScreenState();
}

class _RelatorioIaScreenState extends ConsumerState<RelatorioIaScreen> {
  String? _caminhoEscolhido;
  NarradorIa? _narrador;
  StreamSubscription<String>? _inscricao;
  final _texto = StringBuffer();
  bool _gerando = false;
  Object? _erro;
  int? _memoriaLivre;

  @override
  void initState() {
    super.initState();
    // Aviso de memória é best-effort: sem canal (testes/iOS) segue sem aviso.
    AparelhoLocal.memoriaLivreBytes().then((livre) {
      if (mounted) setState(() => _memoriaLivre = livre);
    });
  }

  @override
  void dispose() {
    _inscricao?.cancel();
    _narrador?.cancelar();
    // Sair da tela encerra a geração de propósito: sem marca órfã no
    // próximo lançamento.
    unawaited(limparGeracaoIa());
    super.dispose();
  }

  ModeloIa? _modeloEfetivo(List<ModeloIa> modelos) {
    for (final m in modelos) {
      if (m.caminho == _caminhoEscolhido) return m;
    }
    return modelos.isEmpty ? null : modelos.first;
  }

  void _escolherCaminho(List<ModeloIa> modelos, String? caminho) {
    if (_gerando || caminho == null) return;
    for (final m in modelos) {
      if (m.caminho == caminho) {
        setState(() => _caminhoEscolhido = caminho);
        return;
      }
    }
  }

  Future<void> _gerar(List<ModeloIa> modelos) async {
    final modelo = _modeloEfetivo(modelos);
    if (modelo == null || _gerando) return;
    final gastos = ref.read(expensesForReportsProvider).value;
    if (gastos == null || gastos.isEmpty) return;

    final s = context.strings;
    final contexto = RelatorioContexto.construir(
      todas: gastos,
      periodo: widget.periodo,
      rotuloCategoria: s.categoriaLabel,
      rotuloPagamento: s.pagamentoLabel,
    );
    final prompt = montarPromptRelatorio(contexto: contexto, strings: s);
    final narrador = ref.read(fabricaNarradorIaProvider)(modelo.caminho);
    _narrador = narrador;
    // Marca no disco: se o motor derrubar o processo (falha nativa, sem
    // chance de `catch`), a próxima abertura registra no Diagnóstico.
    unawaited(marcarGeracaoIa(modelo: modelo.nome));
    setState(() {
      _gerando = true;
      _erro = null;
      _texto.clear();
    });
    _inscricao = narrador
        .narrar(system: prompt.system, user: prompt.user)
        .listen(
          (pedaco) {
            if (mounted) setState(() => _texto.write(pedaco));
          },
          onError: (Object e, StackTrace pilha) {
            // O erro da geração é tratado aqui (tela mostra e continua) — mas
            // também vai para o Diagnóstico, senão ninguém saberia o detalhe.
            unawaited(limparGeracaoIa());
            registrarFalha(e, pilha, contexto: kContextoGeracaoIa);
            if (mounted) {
              setState(() {
                _erro = e;
                _gerando = false;
              });
            }
          },
          onDone: () {
            unawaited(limparGeracaoIa());
            if (mounted) setState(() => _gerando = false);
          },
          cancelOnError: true,
        );
  }

  void _cancelar() {
    _narrador?.cancelar();
    // Sem `await`: o futuro do cancelamento só fecha quando a engine entrega
    // o evento pendente — esperar aqui seguraria o estado "gerando" na tela.
    unawaited(_inscricao?.cancel());
    unawaited(limparGeracaoIa());
    if (mounted) setState(() => _gerando = false);
  }

  Future<void> _compartilhar() async {
    if (_texto.isEmpty) return;
    // Captura o messenger antes do `await`: depois de abrir a folha do
    // sistema o contexto pode já não estar mais montado.
    final messenger = ScaffoldMessenger.of(context);
    final s = context.strings;
    try {
      await SharePlus.instance.share(
        ShareParams(text: _texto.toString(), title: '${s.relatorioPorIa} Mango'),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.naoCompartilhar('$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final modelosAsync = ref.watch(modelosIaProvider);
    final gastos = ref.watch(expensesForReportsProvider).value;
    final periodo = widget.periodo;
    final periodoLabel =
        '${formatDate(periodo.start, (p) => p.dayMonthYear)} — '
        '${formatDate(periodo.end, (p) => p.dayMonthYear)}';

    return Scaffold(
      appBar: AppBar(title: Text(s.relatorioPorIa)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Center(
            child: Text(
              periodoLabel,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 8),
          if (gastos == null || gastos.isEmpty)
            Center(child: Text(s.semGastosPeriodo))
          else
            modelosAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _erroCarregarModelos(s, e),
              data: (modelos) => _conteudo(s, modelos),
            ),
        ],
      ),
    );
  }

  Widget _erroCarregarModelos(AppStrings s, Object e) => Column(
        children: [
          Text(s.iaErroRelatorio('$e'), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(s.iaAtualizar),
            onPressed: () => ref.invalidate(modelosIaProvider),
          ),
        ],
      );

  Widget _conteudo(AppStrings s, List<ModeloIa> modelos) {
    if (modelos.isEmpty) return _semModelo(s);
    final modelo = _modeloEfetivo(modelos)!;
    final avisoMemoria = _avisoMemoria(s, modelo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (modelos.length > 1)
          // Com mais de um modelo, o grupo de rádio escolhe qual rodar.
          // `RadioGroup` guarda a escolha: o `RadioListTile` só reage via
          // grupo (API atual do Flutter).
          RadioGroup<String>(
            groupValue: modelo.caminho,
            onChanged: (caminho) {
              if (_gerando) return;
              _escolherCaminho(modelos, caminho);
            },
            child: Column(
              children: [
                for (final m in modelos)
                  RadioListTile<String>(
                    value: m.caminho,
                    title: Text('${m.nome} · ${m.tamanhoLabel}'),
                  ),
              ],
            ),
          )
        else
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: Text(modelo.nome),
            subtitle: Text(modelo.tamanhoLabel),
            contentPadding: EdgeInsets.zero,
          ),
        if (avisoMemoria != null)
          _cartaoAviso(Icons.warning_amber_rounded, avisoMemoria),
        _cartaoAviso(Icons.offline_bolt_outlined, s.iaAvisoLocal),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _gerando ? null : () => _gerar(modelos),
            icon: const Icon(Icons.auto_awesome),
            label: Text(s.gerarRelatorioIa),
          ),
        ),
        if (_gerando) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(s.iaGerando, style: const TextStyle(fontSize: 13)),
              TextButton(
                onPressed: _cancelar,
                child: Text(s.cancel),
              ),
            ],
          ),
        ],
        if (_erro != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              s.iaErroRelatorio('$_erro'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_texto.isNotEmpty) ...[
          const SizedBox(height: 16),
          SelectableText(_texto.toString()),
          if (!_gerando)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _compartilhar,
                    icon: const Icon(Icons.share),
                    label: Text(s.compartilhar),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _gerar(modelos),
                    icon: const Icon(Icons.refresh),
                    label: Text(s.iaGerarNovamente),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  /// `null` quando há memória de sobra ou quando o aparelho não informa.
  /// O limite é o péssimo cenário: modelo + mais um tanto de folga, i.e.
  /// menos que o dobro do arquivo livre já é motivo de cautela com 0.5B+.
  String? _avisoMemoria(AppStrings s, ModeloIa modelo) {
    final livre = _memoriaLivre;
    if (livre == null || livre >= modelo.tamanhoBytes * 2) return null;
    return s.iaMemoriaBaixa(
      formatarTamanho(livre),
      modelo.tamanhoLabel,
    );
  }

  Widget _semModelo(AppStrings s) => Column(
        children: [
          const SizedBox(height: 16),
          const Icon(Icons.smart_toy_outlined, size: 40, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            s.iaSemModelo,
            style: const TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(s.iaComoInstalarModelo, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(s.iaAtualizar),
            onPressed: () => ref.invalidate(modelosIaProvider),
          ),
        ],
      );

  Widget _cartaoAviso(IconData icone, String texto) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      );
}
