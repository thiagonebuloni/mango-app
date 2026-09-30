// Base da localização: resolve o idioma (pt-BR padrão, en-US quando o
// sistema está em inglês) e define o contrato de frases [AppStrings].
import 'package:flutter/widgets.dart';

import 'app_strings.dart';

/// Locales suportados pelo app.
const supportedAppLocales = [Locale('pt', 'BR'), Locale('en', 'US')];

/// Nome de locale do `intl` para cada [Locale] suportado.
String intlLocaleName(Locale locale) =>
    locale.languageCode == 'en' ? 'en_US' : 'pt_BR';

/// Resolve o locale do app a partir do locale do sistema:
/// inglês (qualquer `en_*`) → en_US; todo o resto → pt_BR (padrão atual).
Locale resolveAppLocale(Locale? system) {
  if (system != null && system.languageCode.toLowerCase() == 'en') {
    return const Locale('en', 'US');
  }
  return const Locale('pt', 'BR');
}

/// Atalho: `context.strings` devolve as frases do idioma atual.
extension StringsContext on BuildContext {
  AppStrings get strings => stringsOf(this);
}

/// Devolve as frases para o locale vigente no [context].
AppStrings stringsOf(BuildContext context) {
  final locale = Localizations.maybeLocaleOf(context);
  return AppStrings.of(locale);
}
