import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/seguranca.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Tela de bloqueio: PIN do próprio app (teclado numérico) + biometria do
/// aparelho quando ativa. É o que o [LockGate] mostra enquanto o bloqueio
/// está ligado — o conteúdo do app fica desmontado atrás dela, então nada
/// aparece nem na visão de "app recentes" do Android.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.config});

  /// Configuração atual: tamanho do PIN, hash e se a biometria está ligada.
  final SegurancaConfig config;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  /// Dígitos digitados até agora (validados ao completar o PIN).
  String _pin = '';

  /// Mensagem sob os pontos (ex.: "PIN incorreto"); `null` = sem erro.
  String? _erro;

  /// Impede uma segunda verificação enquanto a primeira está em voo.
  bool _verificando = false;

  /// Tique da contagem regressiva da espera por tentativas; `null` = parado.
  Timer? _ticker;

  bool get _biometriaLigada => widget.config.biometria;

  @override
  void initState() {
    super.initState();
    if (_biometriaLigada) {
      // Oferece a biometria no primeiro frame: é o caminho de entrada mais
      // rápido e não exige tocar em nada.
      WidgetsBinding.instance.addPostFrameCallback((_) => _tentarBiometria());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _tentarBiometria() async {
    // A espera por tentativas vale para a biometria também: senão bastaria
    // errar o PIN cinco vezes e usar a digital para furar a trava.
    if (await _travadoAgora()) return;
    final ok = await ref
        .read(autenticadorBiometricoProvider)
        .autenticar('Desbloquear o Mango');
    if (!mounted || !ok) return; // cancelou/erro: fica no PIN
    // O diálogo do sistema pode ter demorado: confere a espera de novo.
    if (await _travadoAgora()) return;
    if (!mounted) return;
    _destravar();
  }

  /// Lê a trava do banco (e não do estado observado): no primeiro frame o
  /// estado ainda pode estar carregando, e aí a biometria passaria por cima
  /// de uma espera que começou antes de o app abrir.
  Future<bool> _travadoAgora() async {
    final agora = ref.read(relogioProvider)();
    final futura = ref.read(tentativasProvider.future);
    try {
      final tentativas = await futura;
      return tentativas.travadoEm(agora);
    } catch (_) {
      // Sem leitura da trava, o PIN continua valendo: a configuração do
      // bloqueio, essa sim, já foi lida antes de a tela existir.
      return false;
    }
  }

  Future<void> _digitar(String digito) async {
    if (_verificando) return;
    setState(() {
      _erro = null;
      _pin += digito;
    });
    if (_pin.length < widget.config.pinTamanho) return;
    setState(() => _verificando = true);
    final ok = await verificarPin(_pin, widget.config);
    if (!mounted) return;
    if (ok) {
      _destravar();
      return;
    }
    // O erro conta antes de limpar os pontos: é ele que liga/estende a espera.
    await ref.read(tentativasProvider.notifier).registrarFalha();
    if (!mounted) return;
    setState(() {
      _verificando = false;
      _pin = '';
      _erro = 'PIN incorreto';
    });
  }

  void _apagar() {
    if (_verificando || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  /// Desbloqueia e zera a contagem de erros. Uma falha ao gravar a contagem
  /// não pode impedir a entrada: ela é só uma proteção extra.
  void _destravar() {
    ref.read(tentativasProvider.notifier).limpar().catchError((_) {});
    ref.read(bloqueioProvider.notifier).destravar();
  }

  void _esqueciMeuPin() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Esqueci meu PIN'),
        content: const Text(
          'O Mango é local: não existe e-mail nem servidor para recuperar '
          'um PIN esquecido.\n\n'
          '• Se a biometria estiver ativa, use a digital/rosto para entrar '
          'e trocar o PIN em Menu → Segurança.\n\n'
          '• Sem biometria, a saída é desinstalar o app — o que apaga os '
          'lançamentos. Se você exportou o CSV antes (Menu → Exportar em '
          'CSV), dá para importar de volta depois.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A cor de fundo do perfil já está no tema do MaterialApp; daqui só sai
    // o tom legível para o texto e os ícones.
    final onCor = onBackgroundColor(Theme.of(context).scaffoldBackgroundColor);

    // A espera por tentativas vem do provedor e o tempo que falta é medido no
    // relógio do app (o mesmo que os testes controlam).
    final tentativas =
        ref.watch(tentativasProvider).value ?? const TentativasBloqueio();
    final restante = tentativas.restanteEm(ref.watch(relogioProvider)());
    final travado = restante > Duration.zero;
    _sincronizarTicker(travado);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 64, color: onCor),
                const SizedBox(height: 16),
                Text(
                  'Mango bloqueado',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: onCor,
                  ),
                ),
                const SizedBox(height: 24),
                _pontos(onCor, travado),
                SizedBox(
                  height: 28,
                  child: Center(
                    child: Text(
                      _mensagem(restante),
                      key: const ValueKey('erro-pin'),
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                _teclado(onCor, travado),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _esqueciMeuPin,
                  child: Text(
                    'Esqueci meu PIN',
                    style: TextStyle(color: onCor.withValues(alpha: 0.8)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Texto sob os pontos: a espera por tentativas tem prioridade sobre a
  /// mensagem de erro — durante a espera, o erro é justamente o motivo dela.
  String _mensagem(Duration restante) {
    if (restante > Duration.zero) {
      return 'Muitas tentativas. Tente de novo em ${_tempoLegivel(restante)}';
    }
    return _erro ?? '';
  }

  /// Espera em texto curto: `45 s`, `1 min`, `2 min 30 s`.
  String _tempoLegivel(Duration restante) {
    // Arredonda para cima: com 29,2 s restantes ainda é "30 s" na tela.
    final segundos = (restante.inMilliseconds / 1000).ceil();
    if (segundos < 60) return '$segundos s';
    final minutos = segundos ~/ 60;
    final sobra = segundos % 60;
    return sobra == 0 ? '$minutos min' : '$minutos min $sobra s';
  }

  /// Enquanto a espera estiver ligada, um tique por segundo redesenha a
  /// contagem regressiva. Fora da espera não fica nada agendado — o que
  /// também mantém os testes de widget livres de cronômetros eternos.
  void _sincronizarTicker(bool travado) {
    if (travado && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!travado && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  /// Slots dos dígitos: um círculo por casa do PIN (vermelho no erro).
  Widget _pontos(Color onCor, bool travado) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.config.pinTamanho, (i) {
        final preenchido = i < _pin.length;
        return AnimatedContainer(
          key: ValueKey('slot-$i'),
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _erro != null && !travado
                ? Colors.redAccent
                : preenchido
                    ? onCor
                    : onCor.withValues(alpha: 0.25),
          ),
        );
      }),
    );
  }

  /// Teclado 3×4: 1-9, biometria (quando ligada), 0 e apagar.
  ///
  /// O PIN é digitado aqui mesmo, dentro do app: nenhum teclado do sistema
  /// entra em cena e o valor não passa por clipboard/histórico. Durante a
  /// espera por tentativas ([travado]), todas as teclas ficam sem toque.
  Widget _teclado(Color onCor, bool travado) {
    return SizedBox(
      width: 288,
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.5,
        children: [
          for (var n = 1; n <= 9; n++)
            _tecla('$n', onCor, () => _digitar('$n'), habilitado: !travado),
          if (_biometriaLigada)
            _teclaIcone(
              Icons.fingerprint,
              onCor,
              _tentarBiometria,
              chave: 'biometria',
              tooltip: 'Usar biometria',
              habilitado: !travado,
            )
          else
            const SizedBox.shrink(),
          _tecla('0', onCor, () => _digitar('0'), habilitado: !travado),
          _teclaIcone(
            Icons.backspace_outlined,
            onCor,
            _apagar,
            chave: 'apagar',
            tooltip: 'Apagar',
            habilitado: !travado,
          ),
        ],
      ),
    );
  }

  Widget _tecla(
    String digito,
    Color onCor,
    VoidCallback onTap, {
    required bool habilitado,
  }) {
    return Material(
      color: onCor.withValues(alpha: 0.08),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _verificando || !habilitado ? null : onTap,
        child: Center(
          child: Text(
            digito,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: onCor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _teclaIcone(
    IconData icone,
    Color onCor,
    VoidCallback onTap, {
    required String chave,
    required String tooltip,
    required bool habilitado,
  }) {
    return Material(
      key: ValueKey(chave),
      color: onCor.withValues(alpha: 0.08),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _verificando || !habilitado ? null : onTap,
        child: Tooltip(
          message: tooltip,
          child: Center(child: Icon(icone, color: onCor)),
        ),
      ),
    );
  }
}
