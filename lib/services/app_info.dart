import 'package:package_info_plus/package_info_plus.dart';

/// Informações do app exibidas na interface.
///
/// A versão vinha **fixa no código** na janela "Sobre" (`'1.0.0'`): bastava
/// subir a versão no `pubspec.yaml` para a tela passar a mentir. Aqui ela é
/// lida do **próprio pacote instalado** — a mesma fonte que o build usa —,
/// então nunca fica defasada em relação ao APK.

/// Versão instalada no formato `1.0.0 (1)` (versão + build number).
///
/// Devolve `null` quando não é possível ler (plugin indisponível, como em
/// teste de widget): melhor não mostrar versão nenhuma do que mostrar uma
/// errada.
Future<String?> versaoDoApp() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return formatarVersao(info.version, info.buildNumber);
  } catch (_) {
    return null;
  }
}

/// Monta o texto da versão: `1.0.0 (1)`.
///
/// Sem build number devolve só a versão; sem versão devolve `null` (nada a
/// mostrar). Função pura, para o teste não depender do plugin.
String? formatarVersao(String version, String buildNumber) {
  final v = version.trim();
  if (v.isEmpty) return null;
  final b = buildNumber.trim();
  return b.isEmpty ? v : '$v ($b)';
}
