import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_locale.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../services/seguranca.dart';
import '../state/providers.dart';

/// Tela **Segurança**: o bloqueio do app (PIN + biometria).
///
/// Toda a configuração vive na tabela `seguranca` do banco local e **não**
/// entra no CSV nem no backup: não é dado financeiro e carrega hash de PIN.
/// Sem PIN criado, a tela só explica e oferece criar.
class SegurancaScreen extends ConsumerStatefulWidget {
  const SegurancaScreen({super.key});

  @override
  ConsumerState<SegurancaScreen> createState() => _SegurancaScreenState();
}

/// Mensagem legível para os erros que os diálogos podem devolver.
///
/// [strings] entra como parâmetro para que o texto de rede (o único que o
/// app traduz) saia no idioma vigente.
String _mensagemErro(Object e, [AppStrings? strings]) {
  if (e is ArgumentError) return '${e.message}';
  if (e is FormatException) return e.message;
  if (e is StateError) return e.message;
  return '${(strings ?? AppStrings.of(null)).naoSalvarConfig}$e';
}

class _SegurancaScreenState extends ConsumerState<SegurancaScreen> {
  /// `null` = ainda conferindo se o aparelho tem biometria cadastrada.
  bool? _biometriaDisponivel;

  @override
  void initState() {
    super.initState();
    _checarBiometria();
  }

  Future<void> _checarBiometria() async {
    final disponivel =
        await ref.read(autenticadorBiometricoProvider).disponivel();
    if (!mounted) return;
    setState(() => _biometriaDisponivel = disponivel);
  }

  void _avisar(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensagem)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.strings.seguranca)),
      body: ref.watch(segurancaProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '${context.strings.erroSalvarConfig} $e',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (config) => ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children:
                  config == null ? _semBloqueio() : _comBloqueio(config),
            ),
          ),
    );
  }

  // ---------------- bloqueio desativado ----------------

  List<Widget> _semBloqueio() {
    final s = context.strings;
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
        child: Icon(Icons.lock_open_outlined, size: 64, color: Colors.grey),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          s.bloqueioDesativado,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Text(
          s.bloqueioDesativadoDetalhe,
          textAlign: TextAlign.center,
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: FilledButton.icon(
          onPressed: _criarPin,
          icon: const Icon(Icons.lock_outline),
          label: Text(s.criarPin),
        ),
      ),
    ];
  }

  // ---------------- bloqueio ativo ----------------

  List<Widget> _comBloqueio(SegurancaConfig config) {
    final s = context.strings;
    return [
      ListTile(
        leading: const Icon(Icons.dialpad),
        title: Text(s.pinAtivo),
        subtitle: Text(s.pinDigitos(config.pinTamanho)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.fingerprint),
        title: Text(s.desbloquearBiometria),
        subtitle: Text(_legendaBiometria()),
        value: config.biometria,
        onChanged:
            _biometriaDisponivel == false ? null : _alternarBiometria,
      ),
      ListTile(
        leading: const Icon(Icons.password),
        title: Text(s.alterarPin),
        onTap: _alterarPin,
      ),
      ListTile(
        leading: const Icon(Icons.lock_open_outlined),
        title: Text(s.desativarBloqueio),
        onTap: _desativar,
      ),
    ];
  }

  String _legendaBiometria() {
    final s = context.strings;
    switch (_biometriaDisponivel) {
      case null:
        return s.conferindoAparelho;
      case false:
        return s.semBiometria;
      case true:
        return s.biometriaReserva;
    }
  }

  Future<void> _alternarBiometria(bool valor) async {
    // Frases capturadas antes do await: o context não cruza gap assíncrono.
    final s = context.strings;
    try {
      await ref.read(segurancaProvider.notifier).setBiometria(valor);
    } catch (e) {
      _avisar(_mensagemErro(e, s));
    }
  }

  // ---------------- ações ----------------

  Future<void> _criarPin() async {
    final s = context.strings;
    final criado = await _pedirPin(
      titulo: s.criarPin,
      campos: [s.novoPin, s.confirmePin],
      rotuloAcao: s.criar,
      confirmarUltimo: true,
      aoConfirmar: (valores) => ref
          .read(segurancaProvider.notifier)
          .ativar(pin: valores.first, biometria: false),
    );
    if (criado != true) return;
    _avisar(s.bloqueioAtivado);
    // Só oferece a biometria se o aparelho realmente tiver uma cadastrada.
    if (_biometriaDisponivel == true) await _oferecerBiometria();
  }

  Future<void> _oferecerBiometria() async {
    final s = context.strings;
    final aceitou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.usarBiometria),
        content: Text(s.biometriaTituloMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.agoraNao),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.ativar),
          ),
        ],
      ),
    );
    if (aceitou != true) return;
    try {
      await ref.read(segurancaProvider.notifier).setBiometria(true);
      _avisar(s.biometriaAtivada);
    } catch (e) {
      _avisar(_mensagemErro(e, s));
    }
  }

  Future<void> _alterarPin() async {
    final s = context.strings;
    final alterado = await _pedirPin(
      titulo: s.alterarPin,
      campos: [
        s.pinAtual,
        s.novoPin,
        s.confirmeNovoPin,
      ],
      rotuloAcao: s.alterar,
      confirmarUltimo: true,
      aoConfirmar: (valores) => ref
          .read(segurancaProvider.notifier)
          .alterarPin(atual: valores[0], novo: valores[1]),
    );
    if (alterado == true) _avisar(s.pinAlterado);
  }

  Future<void> _desativar() async {
    final s = context.strings;
    final desativado = await _pedirPin(
      titulo: s.desativarBloqueio,
      campos: [s.pinAtual],
      rotuloAcao: s.desativar,
      aoConfirmar: (valores) => ref
          .read(segurancaProvider.notifier)
          .desativar(atual: valores.first),
    );
    if (desativado == true) _avisar(s.bloqueioDesativadoOk);
  }

  /// Diálogo de PIN com [campos] entradas mascaradas.
  ///
  /// Devolve `true` quando [aoConfirmar] concluiu sem erro. As falhas que só
  /// o provedor conhece (PIN atual errado, por exemplo) aparecem dentro do
  /// próprio diálogo, que continua aberto.
  Future<bool?> _pedirPin({
    required String titulo,
    required List<String> campos,
    required String rotuloAcao,
    required Future<void> Function(List<String> valores) aoConfirmar,
    bool confirmarUltimo = false,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (_) => _DialogoPin(
          titulo: titulo,
          campos: campos,
          rotuloAcao: rotuloAcao,
          aoConfirmar: aoConfirmar,
          confirmarUltimo: confirmarUltimo,
        ),
      );
}

/// Formulário de PIN do diálogo.
///
/// É um widget à parte (e não um `StatefulBuilder` embutido) porque só ele
/// sabe quando pode descartar os controladores de texto: soltá-los ao fim do
/// `showDialog` quebraria a animação de saída, que ainda redesenha os campos.
class _DialogoPin extends StatefulWidget {
  const _DialogoPin({
    required this.titulo,
    required this.campos,
    required this.rotuloAcao,
    required this.aoConfirmar,
    required this.confirmarUltimo,
  });

  final String titulo;
  final List<String> campos;
  final String rotuloAcao;
  final Future<void> Function(List<String> valores) aoConfirmar;
  final bool confirmarUltimo;

  @override
  State<_DialogoPin> createState() => _DialogoPinState();
}

class _DialogoPinState extends State<_DialogoPin> {
  final _formKey = GlobalKey<FormState>();
  late final List<TextEditingController> _controladores = [
    for (var i = 0; i < widget.campos.length; i++) TextEditingController(),
  ];

  /// Erro que só o provedor conhece (ex.: PIN atual incorreto).
  String _erro = '';

  /// `true` enquanto o provedor trabalha: evita toque duplo.
  bool _ocupado = false;

  @override
  void dispose() {
    for (final controlador in _controladores) {
      controlador.dispose();
    }
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_ocupado || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _ocupado = true;
      _erro = '';
    });
    try {
      await widget.aoConfirmar([for (final c in _controladores) c.text]);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _erro = _mensagemErro(e, context.strings);
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return AlertDialog(
      title: Text(widget.titulo),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.campos.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextFormField(
                  controller: _controladores[i],
                  autofocus: i == 0,
                  obscureText: true,
                  maxLength: kPinMaximo,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(kPinMaximo),
                  ],
                  decoration: InputDecoration(
                    labelText: widget.campos[i],
                    counterText: '',
                  ),
                  validator: (valor) {
                    final texto = valor ?? '';
                    if (!pinValido(texto)) {
                      return s.pinRegra(kPinMinimo, kPinMaximo);
                    }
                    if (widget.confirmarUltimo &&
                        i == widget.campos.length - 1 &&
                        texto != _controladores[i - 1].text) {
                      return s.pinsNaoConferem;
                    }
                    return null;
                  },
                ),
              ),
            if (_erro.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _erro,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _ocupado ? null : () => Navigator.of(context).pop(false),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: _ocupado ? null : _enviar,
          child: Text(widget.rotuloAcao),
        ),
      ],
    );
  }
}
