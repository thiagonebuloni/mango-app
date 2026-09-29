// Versão exibida no app: a janela "Sobre" já mostrou um valor fixo no código
// ('1.0.0'), que passaria a mentir na primeira subida de versão. Agora o texto
// é montado a partir do que o próprio pacote instalado informa.
import 'package:flutter_test/flutter_test.dart';
import 'package:mango/services/app_info.dart';

void main() {
  group('formatarVersao', () {
    test('junta versão e build number', () {
      expect(formatarVersao('1.0.0', '1'), '1.0.0 (1)');
      expect(formatarVersao('2.3.4', '57'), '2.3.4 (57)');
    });

    test('sem build number mostra só a versão', () {
      expect(formatarVersao('1.2.3', ''), '1.2.3');
      expect(formatarVersao('1.2.3', '   '), '1.2.3');
    });

    test('sem versão não há o que mostrar', () {
      expect(formatarVersao('', '1'), isNull);
      expect(formatarVersao('   ', '1'), isNull);
    });

    test('espaços em volta não entram no texto', () {
      expect(formatarVersao(' 1.0.0 ', ' 2 '), '1.0.0 (2)');
    });
  });
}
