import 'package:flutter/material.dart';

import '../models/models.dart';
import '../widgets/common.dart';

/// Cores de fundo do **tema claro** (claras, para o texto continuar legível).
const List<Color> kCoresTemaClaro = [
  Color(0xFFE0F2F1), // verde-água
  Color(0xFFE3F2FD), // azul
  Color(0xFFF3E5F5), // lilás
  Color(0xFFFCE4EC), // rosa
  Color(0xFFFFF3E0), // pêssego
  Color(0xFFE8F5E9), // verde
  Color(0xFFFFFDE7), // amarelo claro
  Color(0xFFEEEEEE), // cinza
];

/// Cores de fundo do **tema escuro**: mesmos matizes do tema claro, mas em
/// tons escuros e saturados. A posição corresponde à do tema claro
/// (`kCoresTemaEscuro[i]` é o tom escuro de `kCoresTemaClaro[i]`), para que
/// trocar de tema preserve a cor escolhida pelo usuário.
const List<Color> kCoresTemaEscuro = [
  Color(0xFF0E4F4A), // verde-água escuro
  Color(0xFF1E3A5F), // azul escuro
  Color(0xFF3B2366), // lilás escuro
  Color(0xFF6B1E3A), // rosa escuro
  Color(0xFF7A4A12), // pêssego/âmbar escuro
  Color(0xFF14532D), // verde escuro
  Color(0xFF5C4A0E), // amarelo/oliva escuro
  Color(0xFF33393B), // cinza escuro
];

/// Tema ativo no perfil (`true` = claro). Perfis antigos/nulos continuam no
/// tema claro.
bool temaClaroDoPerfil(UserProfile? perfil) => perfil?.temaClaro ?? true;

/// Fundo fixo do **tema escuro**: cinza escuro, independente da cor escolhida.
///
/// A cor escolhida pelo usuário continua valendo no tema escuro, mas só nas
/// caixas destacadas de Gastos/Relatórios (ver [corDestaqueDoPerfil]) — o
/// fundo do app é sempre este cinza para manter o contraste.
const Color kFundoTemaEscuro = Color(0xFF0d0f0f);

/// Índice da [cor] na [paleta], ou `-1` quando ela não é uma das opções.
int _indiceNaPaleta(Color cor, List<Color> paleta) {
  for (var i = 0; i < paleta.length; i++) {
    if (paleta[i].toARGB32() == cor.toARGB32()) return i;
  }
  return -1;
}

/// Cor armazenada no perfil convertida para a [paleta] destino, preservando a
/// posição (matiz) escolhida. Quando a cor atual não é uma das opções (perfil
/// antigo/editado à mão), mantém a cor original.
Color corNaPaleta(Color cor, List<Color> origem, List<Color> destino) {
  final i = _indiceNaPaleta(cor, origem);
  if (i < 0) return cor;
  return destino[i.clamp(0, destino.length - 1)];
}

/// Cor de fundo efetiva do app: a escolhida no perfil no tema claro; no tema
/// escuro, sempre o cinza escuro fixo ([kFundoTemaEscuro]).
///
/// Se um perfil antigo (ou editado à mão) combinar tema escuro com uma cor da
/// paleta clara, o fundo continua cinza escuro — a cor escolhida aparece só
/// nas caixas destacadas (ver [corDestaqueDoPerfil]). E vice-versa: tema
/// claro com cor da paleta escura volta para o tom claro correspondente.
Color corFundoDoPerfil(UserProfile? perfil) {
  if (perfil == null) return const Color(UserProfile.corFundoPadrao);
  final cor = Color(perfil.corFundo);
  if (perfil.temaClaro) {
    final i = _indiceNaPaleta(cor, kCoresTemaEscuro);
    if (i >= 0) return kCoresTemaClaro[i];
    return cor;
  }
  return kFundoTemaEscuro;
}

/// Cor de destaque do tema escuro: a cor escolhida pelo usuário, usada nas
/// caixas destacadas de Gastos/Relatórios. `null` no tema claro.
Color? corDestaqueDoPerfil(UserProfile? perfil) {
  if (perfil == null || perfil.temaClaro) return null;
  final cor = Color(perfil.corFundo);
  final i = _indiceNaPaleta(cor, kCoresTemaClaro);
  if (i >= 0) return kCoresTemaEscuro[i];
  return cor;
}

/// Cor de acento do app: deriva da cor escolhida no perfil e alimenta o
/// `seedColor` do tema. Assim o botão "+" de lançamento, as abas "Gastos" e
/// "Relatórios" (indicador da NavigationBar), a seleção de datas
/// (DatePicker/DateRangePicker), os botões "Tirar foto"/"Escolher da galeria"
/// e toda a tela de "Nova despesa"/"Nova receita" (SegmentedButton, campos
/// focados, "Salvar") — incluindo o diálogo "Cancelar lançamento" — seguem a
/// cor do perfil.
///
/// - Tema claro: a cor de fundo é pastel (clara demais para virar `seed`),
///   então devolve um tom saturado/escuro do mesmo matiz.
/// - Tema escuro: devolve a cor forte escolhida ([corDestaqueDoPerfil]).
Color corAcentoDoPerfil(UserProfile? perfil) {
  final destaque = corDestaqueDoPerfil(perfil);
  if (destaque != null) return destaque;
  return acentoDeFundoClaro(corFundoDoPerfil(perfil));
}

/// Deriva um tom de acento saturado a partir de um fundo claro (pastel).
/// Mantém o matiz do fundo, forçando saturação e luminosidade legíveis para
/// botões/seleções. Fundos acinzentados (sem matiz) caem no verde-água padrão.
Color acentoDeFundoClaro(Color fundo) {
  final hsl = HSLColor.fromColor(fundo);
  if (hsl.saturation < 0.15) return Colors.teal;
  return hsl
      .withSaturation(hsl.saturation.clamp(0.55, 0.9))
      .withLightness(0.38)
      .toColor();
}

/// Tema do app construído a partir do perfil do usuário (cor de fundo + modo
/// claro/escuro). A cor vale para todo o app: fundo dos Scaffolds, AppBar,
/// barra de navegação inferior, diálogos e bottom sheets.
///
/// O [seedColor] (botões, indicador da NavigationBar, seleção de datas,
/// SegmentedButton, campos focados) deriva da cor do perfil via
/// [corAcentoDoPerfil]: passe `corAcento` quando o tema claro usa um tom
/// saturado em vez do fundo pastel.
///
/// É aplicado em `MaterialApp.theme` (ver `FinancApp`), então trocar a cor ou
/// o tema no perfil repinta todas as telas na hora.
ThemeData buildAppTheme(Color corFundo,
    {bool temaClaro = true, Color? corAcento}) {
  final seed =
      corAcento ?? (temaClaro ? acentoDeFundoClaro(corFundo) : corFundo);
  final base = ThemeData(
    useMaterial3: true,
    brightness: temaClaro ? Brightness.light : Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: temaClaro ? Brightness.light : Brightness.dark,
    ),
  );
  final onCor = onBackgroundColor(corFundo);

  return base.copyWith(
    scaffoldBackgroundColor: corFundo,
    canvasColor: corFundo,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: corFundo,
      foregroundColor: onCor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: corFundo,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: corFundo,
      modalBackgroundColor: corFundo,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: corFundo,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
  );
}
