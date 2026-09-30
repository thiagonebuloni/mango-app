import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:local_auth/local_auth.dart';

import '../models/models.dart';

/// Tamanho do PIN do app: de 4 a 6 dígitos.
const int kPinMinimo = 4;
const int kPinMaximo = 6;

/// Iterações do PBKDF2 na criação do PIN. O valor vai junto de cada hash,
/// então dá para subir o custo no futuro sem invalidar PINs já gravados.
const int kPinIteracoesPadrao = 100000;

/// `true` quando [pin] é um PIN aceito pelo app: só dígitos, com tamanho
/// entre [kPinMinimo] e [kPinMaximo].
bool pinValido(String pin) =>
    RegExp(r'^\d+$').hasMatch(pin) &&
    pin.length >= kPinMinimo &&
    pin.length <= kPinMaximo;

/// Deriva o hash do PIN com PBKDF2-HMAC-SHA256.
Future<List<int>> _derivar(String pin, List<int> sal, int iteracoes) async {
  final pbkdf2 = Pbkdf2.hmacSha256(iterations: iteracoes, bits: 256);
  final chave = await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(pin)),
    nonce: sal,
  );
  return chave.extractBytes();
}

/// Sal novo, aleatório e criptograficamente seguro (16 bytes).
List<int> _salAleatorio() {
  final rand = Random.secure();
  return List<int>.generate(16, (_) => rand.nextInt(256));
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _deHex(String hex) => [
      for (var i = 0; i + 1 < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];

/// Compara dois bytes em tempo constante (XOR acumulado): evita que a
/// medição do tempo da comparação revele quantos bytes já batiam.
bool _iguaisTempoConstante(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Cria a configuração de um PIN novo: sal aleatório + hash PBKDF2.
///
/// Lança [ArgumentError] se [pin] não for válido (ver [pinValido]).
Future<SegurancaConfig> criarConfigPin(
  String pin, {
  bool biometria = false,
  int iteracoes = kPinIteracoesPadrao,
}) async {
  if (!pinValido(pin)) {
    throw ArgumentError.value(
      pin,
      'pin',
      'PIN deve ter $kPinMinimo a $kPinMaximo dígitos.',
    );
  }
  final sal = _salAleatorio();
  final hash = await _derivar(pin, sal, iteracoes);
  return SegurancaConfig(
    pinHash: _hex(hash),
    pinSalt: _hex(sal),
    pinIteracoes: iteracoes,
    pinTamanho: pin.length,
    biometria: biometria,
  );
}

/// Recria o hash para um PIN novo, preservando a biometria da configuração
/// atual (usado na troca de PIN).
Future<SegurancaConfig> rehashearPin(
  SegurancaConfig atual,
  String pin, {
  int? iteracoes,
}) =>
    criarConfigPin(
      pin,
      biometria: atual.biometria,
      iteracoes: iteracoes ?? kPinIteracoesPadrao,
    );

/// Verifica [pin] contra a configuração salva.
///
/// O tamanho é conferido antes (é informação pública: os slots da tela de
/// bloqueio já mostram) e a comparação do hash é em tempo constante.
Future<bool> verificarPin(String pin, SegurancaConfig config) async {
  if (!pinValido(pin) || pin.length != config.pinTamanho) return false;
  final hash = await _derivar(pin, _deHex(config.pinSalt), config.pinIteracoes);
  return _iguaisTempoConstante(hash, _deHex(config.pinHash));
}

/// Tentativas de PIN erradas permitidas antes da primeira espera.
const int kTentativasLivres = 5;

/// Primeira espera, aplicada na [kTentativasLivres]ésima tentativa errada.
const Duration kTravaBase = Duration(seconds: 30);

/// Teto da espera: 30 minutos.
const Duration kTravaMaxima = Duration(minutes: 30);

/// Espera imposta depois de [falhas] erros consecutivos.
///
/// Zero enquanto o usuário ainda está dentro das [kTentativasLivres]
/// tentativas; da [kTentativasLivres]ésima em diante dobra a cada erro novo —
/// 30 s, 1 min, 2 min, 4 min… até o teto de [kTravaMaxima]. A espera **não**
/// zera sozinha: só um desbloqueio bem-sucedido (ou a troca da configuração)
/// limpa a contagem, senão bastaria esperar passar para voltar às 5 livres.
Duration duracaoTrava(int falhas) {
  if (falhas < kTentativasLivres) return Duration.zero;
  final passos = falhas - kTentativasLivres + 1; // 1 = primeira espera
  // Guarda de sanidade: a partir daqui a espera já está no teto, e um `<<`
  // grande demais só serviria para estourar a conta.
  if (passos > 20) return kTravaMaxima;
  final espera = kTravaBase * (1 << (passos - 1));
  return espera > kTravaMaxima ? kTravaMaxima : espera;
}

/// Aplica um PIN errado sobre [atual]: conta a falha e, quando for o caso,
/// agenda a espera a partir de [agora].
TentativasBloqueio registrarFalhaDePin(
  TentativasBloqueio atual,
  DateTime agora,
) {
  final falhas = atual.falhas + 1;
  final espera = duracaoTrava(falhas);
  return TentativasBloqueio(
    falhas: falhas,
    bloqueadoAte: espera == Duration.zero ? null : agora.add(espera),
  );
}

/// Abstração da biometria do aparelho — os testes injetam um falso.
abstract class AutenticadorBiometrico {
  /// `true` quando há biometria **cadastrada** no aparelho.
  Future<bool> disponivel();

  /// Tenta autenticar com [motivo]; qualquer falha/cancelamento → `false`.
  Future<bool> autenticar(String motivo);
}

/// Implementação real com `local_auth`: quem valida é o sistema do
/// aparelho — nenhum dado biométrico passa pelo app.
class LocalAuthBiometrico implements AutenticadorBiometrico {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> disponivel() async {
    try {
      // Diferente de canCheckBiometrics (só hardware), esta lista só vem
      // não-vazia quando o usuário realmente cadastrou digital/rosto.
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false; // sem hardware/serviço: nunca derruba o fluxo
    }
  }

  @override
  Future<bool> autenticar(String motivo) async {
    try {
      return await _auth.authenticate(
        localizedReason: motivo,
        // O fallback é o PIN do Mango, não o PIN/cena do sistema: um
        // único caminho de desbloqueio, com as regras todas no app.
        biometricOnly: true,
        // Se o app for para o fundo com o diálogo aberto (ex.: ligação),
        // o plugin espera voltar e retenta em vez de falhar.
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
