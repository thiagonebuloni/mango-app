import 'package:flutter_test/flutter_test.dart';
import 'package:mango/models/models.dart';
import 'package:mango/services/seguranca.dart';

/// Iterações baixas: o PBKDF2 é caro de propósito, e aqui só a lógica importa.
const _iteracoes = 500;

void main() {
  group('pinValido', () {
    test('aceita de 4 a 6 dígitos', () {
      for (final pin in ['1234', '00000', '123456']) {
        expect(pinValido(pin), isTrue, reason: pin);
      }
    });

    test('recusa curto, longo e não numérico', () {
      for (final pin in ['', '1', '123', '1234567', '12a4', '12 34', '-123']) {
        expect(pinValido(pin), isFalse, reason: pin);
      }
    });
  });

  group('criarConfigPin', () {
    test('guarda tamanho e iterações, sem o PIN em claro', () async {
      final config = await criarConfigPin('123456', iteracoes: _iteracoes);

      expect(config.pinTamanho, 6);
      expect(config.pinIteracoes, _iteracoes);
      expect(config.biometria, isFalse);
      expect(config.pinHash, isNot(contains('123456')));
      expect(config.pinSalt, hasLength(32)); // 16 bytes em hexadecimal
      expect(config.pinHash, hasLength(64)); // 32 bytes em hexadecimal
    });

    test('mesmo PIN gera hash diferente (sal novo a cada criação)', () async {
      final a = await criarConfigPin('1234', iteracoes: _iteracoes);
      final b = await criarConfigPin('1234', iteracoes: _iteracoes);

      expect(a.pinSalt, isNot(b.pinSalt));
      expect(a.pinHash, isNot(b.pinHash));
    });

    test('PIN fora do padrão → ArgumentError', () async {
      await expectLater(
        criarConfigPin('12', iteracoes: _iteracoes),
        throwsArgumentError,
      );
      await expectLater(
        criarConfigPin('1234567', iteracoes: _iteracoes),
        throwsArgumentError,
      );
    });

    test('biometria vai junto quando pedida', () async {
      final config =
          await criarConfigPin('1234', biometria: true, iteracoes: _iteracoes);

      expect(config.biometria, isTrue);
    });
  });

  group('verificarPin', () {
    test('aceita o PIN certo e recusa o errado', () async {
      final config = await criarConfigPin('4321', iteracoes: _iteracoes);

      expect(await verificarPin('4321', config), isTrue);
      expect(await verificarPin('1234', config), isFalse);
    });

    test('recusa PIN com tamanho diferente do configurado', () async {
      // Configurado com 6 dígitos: "1234" nem chega a ser derivado.
      final config = await criarConfigPin('123456', iteracoes: _iteracoes);

      expect(await verificarPin('1234', config), isFalse);
    });

    test('recusa quando o hash gravado não corresponde', () async {
      final config = await criarConfigPin('1234', iteracoes: _iteracoes);
      final adulterado = SegurancaConfig(
        pinHash: '0' * 64,
        pinSalt: config.pinSalt,
        pinIteracoes: config.pinIteracoes,
        pinTamanho: config.pinTamanho,
      );

      expect(await verificarPin('1234', adulterado), isFalse);
    });

    test('funciona com PIN de 4 e de 6 dígitos', () async {
      for (final pin in ['0000', '987654']) {
        final config = await criarConfigPin(pin, iteracoes: _iteracoes);
        expect(await verificarPin(pin, config), isTrue, reason: pin);
      }
    });
  });

  group('rehashearPin', () {
    test('troca o PIN preservando a biometria', () async {
      final antes =
          await criarConfigPin('1111', biometria: true, iteracoes: _iteracoes);
      final depois = await rehashearPin(antes, '222222', iteracoes: _iteracoes);

      expect(depois.biometria, isTrue);
      expect(depois.pinTamanho, 6);
      expect(await verificarPin('222222', depois), isTrue);
      expect(await verificarPin('1111', depois), isFalse);
    });

    test('usa sal novo a cada troca', () async {
      final antes = await criarConfigPin('1111', iteracoes: _iteracoes);
      final depois = await rehashearPin(antes, '2222', iteracoes: _iteracoes);

      expect(depois.pinSalt, isNot(antes.pinSalt));
    });
  });

  group('duracaoTrava', () {
    test('não espera nada dentro das tentativas livres', () {
      for (var falhas = 0; falhas < kTentativasLivres; falhas++) {
        expect(duracaoTrava(falhas), Duration.zero, reason: 'falhas=$falhas');
      }
    });

    test('a última tentativa livre já liga a espera, que dobra a cada erro', () {
      expect(duracaoTrava(kTentativasLivres), const Duration(seconds: 30));
      expect(duracaoTrava(kTentativasLivres + 1), const Duration(minutes: 1));
      expect(duracaoTrava(kTentativasLivres + 2), const Duration(minutes: 2));
      expect(duracaoTrava(kTentativasLivres + 3), const Duration(minutes: 4));
    });

    test('não passa do teto, por mais erros que aconteçam', () {
      expect(duracaoTrava(30), kTravaMaxima);
      expect(duracaoTrava(1000), kTravaMaxima);
    });
  });

  group('registrarFalhaDePin', () {
    final agora = DateTime(2026, 1, 1, 12);

    test('conta o erro e agenda a espera a partir de agora', () {
      var tentativas = const TentativasBloqueio();

      for (var i = 1; i < kTentativasLivres; i++) {
        tentativas = registrarFalhaDePin(tentativas, agora);
        expect(tentativas.falhas, i);
        expect(tentativas.bloqueadoAte, isNull, reason: 'erro $i');
        expect(tentativas.travadoEm(agora), isFalse, reason: 'erro $i');
      }

      tentativas = registrarFalhaDePin(tentativas, agora);

      expect(tentativas.falhas, kTentativasLivres);
      expect(tentativas.bloqueadoAte, agora.add(kTravaBase));
      expect(tentativas.travadoEm(agora), isTrue);
      expect(tentativas.restanteEm(agora), kTravaBase);
      // No instante em que a espera termina já está liberado de novo.
      expect(tentativas.travadoEm(agora.add(kTravaBase)), isFalse);
      expect(
        tentativas.restanteEm(agora.add(const Duration(minutes: 5))),
        Duration.zero,
      );
    });

    test('espera vencida não zera a contagem: o erro novo espera mais', () {
      var tentativas = const TentativasBloqueio();
      for (var i = 0; i < kTentativasLivres; i++) {
        tentativas = registrarFalhaDePin(tentativas, agora);
      }

      final depoisDaEspera = agora.add(kTravaBase);
      tentativas = registrarFalhaDePin(tentativas, depoisDaEspera);

      expect(tentativas.falhas, kTentativasLivres + 1);
      expect(
        tentativas.bloqueadoAte,
        depoisDaEspera.add(const Duration(minutes: 1)),
      );
    });
  });

  group('SegurancaConfig', () {
    test('toString não expõe hash nem sal', () async {
      final config = await criarConfigPin('1234', iteracoes: _iteracoes);
      final texto = config.toString();

      expect(texto, isNot(contains(config.pinHash)));
      expect(texto, isNot(contains(config.pinSalt)));
    });

    test('copyWith troca só a biometria', () async {
      final config = await criarConfigPin('1234', iteracoes: _iteracoes);
      final comBio = config.copyWith(biometria: true);

      expect(comBio.biometria, isTrue);
      expect(comBio.pinHash, config.pinHash);
      expect(comBio.pinSalt, config.pinSalt);
      expect(comBio.pinTamanho, config.pinTamanho);
      expect(comBio.pinIteracoes, config.pinIteracoes);
    });
  });
}
