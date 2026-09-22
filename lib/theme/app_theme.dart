import 'package:flutter/material.dart';

import '../models/models.dart';
import '../widgets/common.dart';

/// Cor de fundo do app: a escolhida no perfil ou o padrão antes do cadastro.
Color corFundoDoPerfil(UserProfile? perfil) =>
    Color(perfil?.corFundo ?? UserProfile.corFundoPadrao);

/// Tema do app construído a partir da **cor de fundo escolhida pelo usuário**
/// no perfil. A cor vale para todo o app: fundo dos Scaffolds, AppBar, barra de
/// navegação inferior, diálogos e bottom sheets.
///
/// É aplicado em `MaterialApp.theme` (ver `FinancApp`), então trocar a cor no
/// perfil repinta todas as telas na hora.
ThemeData buildAppTheme(Color corFundo) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
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
