// Formatação sensível a locale: moeda e datas (intl).
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'app_locale.dart';
import 'app_strings.dart';

/// Formata centavos na moeda do locale (BRL / USD).
String formatMoney(int cents, [Locale? locale]) {
  final loc = locale ?? const Locale('pt', 'BR');
  final s = AppStrings.of(loc);
  final name = intlLocaleName(loc);
  final fmt = NumberFormat.currency(
    locale: name,
    symbol: s.currencySymbol,
    decimalDigits: 2,
  );
  return fmt.format(cents / 100);
}

/// Formata [date] com o padrão escolhido no locale dado.
String formatDate(DateTime date, String Function(DatePatterns p) pick,
    [Locale? locale]) {
  final loc = locale ?? const Locale('pt', 'BR');
  final s = AppStrings.of(loc);
  return DateFormat(pick(s.patterns), intlLocaleName(loc)).format(date);
}
