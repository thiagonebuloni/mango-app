import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
String _mensagemErro(Object e) {
  if (e is ArgumentError) return '${e.message}';
  if (e is FormatException) return e.message;
  if (e is StateError) return e.message;
  return 'Não foi possível salvar: $e';
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
      appBar: AppBar(title: const Text('Segurança')),
      body: ref.watch(segurancaProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Não foi possível ler a configuração de segurança: $e',
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

  List<Widget> _semBloqueio() => [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Icon(Icons.lock_open_outlined, size: 64, color: Colors.grey),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'O bloqueio do app está desativado',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Text(
            'Com um PIN de 4 a 6 dígitos, o Mango pede a senha toda vez que '
            'abre ou volta do segundo plano. Os dados continuam só neste '
            'aparelho — o PIN só evita que quem pegar o celular destravado '
            'veja seus lançamentos.',
            textAlign: TextAlign.center,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: FilledButton.icon(
            onPressed: _criarPin,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Criar PIN'),
          ),
        ),
      ];

  // ---------------- bloqueio ativo ----------------

  List<Widget> _comBloqueio(SegurancaConfig config) => [
        ListTile(
          leading: const Icon(Icons.dialpad),
          title: const Text('PIN ativo'),
          subtitle: Text('${config.pinTamanho} dígitos'),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint),
          title: const Text('Desbloquear com biometria'),
          subtitle: Text(_legendaBiometria()),
          value: config.biometria,
          onChanged:
              _biometriaDisponivel == false ? null : _alternarBiometria,
        ),
        ListTile(
          leading: const Icon(Icons.password),
          title: const Text('Alterar PIN'),
          onTap: _alterarPin,
        ),
        ListTile(
          leading: const Icon(Icons.lock_open_outlined),
          title: const Text('Desativar bloqueio'),
          onTap: _desativar,
        ),
      ];

  String _legendaBiometria() {
    switch (_biometriaDisponivel) {
      case null:
        return 'Conferindo o aparelho…';
      case false:
        return 'Este aparelho não tem biometria cadastrada';
      case true:
        return 'Digital/rosto do aparelho, com o PIN como reserva';
    }
  }

  Future<void> _alternarBiometria(bool valor) async {
    try {
      await ref.read(segurancaProvider.notifier).setBiometria(valor);
    } catch (e) {
      _avisar(_mensagemErro(e));
    }
  }

  // ---------------- ações ----------------

  Future<void> _criarPin() async {
    final criado = await _pedirPin(
      titulo: 'Criar PIN',
      campos: const ['Novo PIN (4 a 6 dígitos)', 'Confirme o PIN'],
      rotuloAcao: 'Criar',
      confirmarUltimo: true,
      aoConfirmar: (valores) => ref
          .read(segurancaProvider.notifier)
          .ativar(pin: valores.first, biometria: false),
    );
    if (criado != true) return;
    _avisar('Bloqueio ativado.');
    // Só oferece a biometria se o aparelho realmente tiver uma cadastrada.
    if (_biometriaDisponivel == true) await _oferecerBiometria();
  }

  Future<void> _oferecerBiometria() async {
    final aceitou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usar biometria?'),
        content: const Text(
          'Além do PIN, o Mango pode pedir a digital/rosto do aparelho para '
          'desbloquear. O PIN continua valendo como reserva.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ativar'),
          ),
        ],
      ),
    );
    if (aceitou != true) return;
    try {
      await ref.read(segurancaProvider.notifier).setBiometria(true);
      _avisar('Biometria ativada.');
    } catch (e) {
      _avisar(_mensagemErro(e));
    }
  }

  Future<void> _alterarPin() async {
    final alterado = await _pedirPin(
      titulo: 'Alterar PIN',
      campos: const [
        'PIN atual',
        'Novo PIN (4 a 6 dígitos)',
        'Confirme o novo PIN',
      ],
      rotuloAcao: 'Alterar',
      confirmarUltimo: true,
      aoConfirmar: (valores) => ref
          .read(segurancaProvider.notifier)
          .alterarPin(atual: valores[0], novo: valores[1]),
    );
    if (alterado == true) _avisar('PIN alterado.');
  }

  Future<void> _desativar() async {
    final desativado = await _pedirPin(
      titulo: 'Desativar bloqueio',
      campos: const ['PIN atual'],
      rotuloAcao: 'Desativar',
      aoConfirmar: (valores) => ref
          .read(segurancaProvider.notifier)
          .desativar(atual: valores.first),
    );
    if (desativado == true) _avisar('Bloqueio desativado.');
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
        _erro = _mensagemErro(e);
      });
    }
  }
  @override
  Widget build(BuildContext context) {
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
                      return 'Use de $kPinMinimo a $kPinMaximo dígitos.';
                    }
                    if (widget.confirmarUltimo &&
                        i == widget.campos.length - 1 &&
                        texto != _controladores[i - 1].text) {
                      return 'Os PINs não conferem.';
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
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _ocupado ? null : _enviar,
          child: Text(widget.rotuloAcao),
        ),
      ],
    );
  }
}
