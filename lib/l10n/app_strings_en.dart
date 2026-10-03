part of 'app_strings.dart';
// en-US: full translation.
class EnUsStrings extends AppStrings {
  const EnUsStrings();
  @override Locale get locale => const Locale('en', 'US');
  @override String get appName => 'Mango';
  @override String get ok => 'OK';
  @override String get cancel => 'Cancel';
  @override String get voltar => 'Back';
  @override String get nao => 'No';
  @override String get salvar => 'Save';
  @override String get excluir => 'Delete';
  @override String get limpar => 'Clear';
  @override String get menu => 'Menu';
  @override String get gastos => 'Expenses';
  @override String get relatorios => 'Reports';
  @override String get meusGastos => 'My expenses';
  @override String get continuarEditando => 'Keep editing';
  @override String erroCarregar(String e) => 'Failed to load: $e';

  @override String erroPerfil(String e) => 'Could not load the profile: $e';
  @override
  String erroSegurancaApp(String e) =>
      'Could not load the app security settings: $e';
  @override
  String imagemAvatarGrande(String a, String m) =>
      'Image too large ($a MB, max $m MB). Choose a smaller image.';
  @override String get desbloqueioMango => 'Unlock Mango';
  @override
  String get parteNaoDesenhada =>
      'This part of the screen could not be drawn.\n'
      'Menu → Diagnostics shows the detail.';
  @override String get ola => 'Hello!';
  @override String olaNome(String n) => 'Hello, $n!';
  @override String get bemVindoMango => 'Welcome to Mango!';
  @override String get temBackup => 'Do you have a backup file?';
  @override String get restaurarBackup => 'Restore backup';
  @override String get criarPerfilNovo => 'Create new profile';
  @override String get escolherBackup => 'Choose backup file';
  @override String erroAbrirSeletor(String e) => 'Could not open picker: $e';
  @override String erroLerArquivo(String e) => 'Could not read file: $e';
  @override String get nenhumDadoBackup => 'No valid data found in backup file';
  @override String get backupSemPerfil => 'Backup without profile';
  @override String backupSemPerfilMsg(int n) => 'File has $n entries but no profile. Import and continue?';
  @override String get importar => 'Import';
  @override String get restaurarBackupTitulo => 'Restore backup?';
  @override String restaurarBackupMsg(String n, String t, int q) => 'Profile ${n.isEmpty ? "user" : n} ($t theme) with $q entries. Restore?';
  @override String get restaurar => 'Restore';
  @override String backupRestaurado(int n) => 'Backup restored: $n new. Check your profile.';
  @override String lancamentosImportados(int n) => '$n imported. Complete your profile.';
  @override String get usuario => 'user';
  @override String get selecionarAno => 'Select year';
  @override String selecionarMesDe(int y) => 'Select month of $y';
  @override String get excluirGasto => 'Delete expense?';
  @override String excluirGastoMsg(String v) => 'Delete this expense of $v?';
  @override String get gastoExcluido => 'Expense deleted';
  @override String get hoje => 'today';
  @override String gastosDoDia(String d) => 'Expenses for $d';
  @override String gastosDeSemana(String i, String f) => 'Expenses from $i to $f';
  @override String gastosDeMes(String m) => 'Expenses for $m';
  @override String get dia => 'Day';
  @override String get semana => 'Week';
  @override String get mes => 'Month';
  @override String get mesAnterior => 'Previous month';
  @override String get proximoMes => 'Next month';
  @override String get nenhumGastoMes => 'No expenses this month.\nUse the + button to start.';
  @override String get nenhumGastoPeriodo => 'No expenses in this period.\nTap the filter to see the month.';
  @override String get semGastosPeriodo => 'No expenses in the period.';
  @override String get excluirAcao => 'Delete';
  @override String get novaDespesa => 'New expense';
  @override String get novaReceita => 'New income';
  @override String get editarGasto => 'Edit expense';
  @override String get editarReceita => 'Edit income';
  @override String get despesa => 'Expense';
  @override String get receita => 'Income';
  @override String get dadosCupom => 'Data from the receipt.\nReview before saving.';
  @override String valorLabel(String s) => 'Amount ($s)';
  @override String get valorHint => '0.00';
  @override String get informeValor => 'Enter the amount';
  @override String get estabelecimento => 'Place';
  @override String get origem => 'Source';
  @override String get descricaoOpcional => 'Description (optional)';
  @override String get categoria => 'Category';
  @override String get formaPagamento => 'Payment method';
  @override String get dataHora => 'Date & time';
  @override String get textoCupom => 'Receipt text';
  @override
  String get dadosExtraidos =>
      'Data extracted from the receipt.\nCheck it before saving.';
  @override String get fotoCupom => 'Receipt photo';
  @override String get toqueAmpliar => 'Tap to enlarge';
  @override String get fotoCupomErro => 'Receipt photo could not be shown.';
  @override String get salvarAlteracoes => 'Save changes';
  @override String get salvarGasto => 'Save expense';
  @override String get salvarReceita => 'Save income';
  @override String get cancelarLancamento => 'Discard entry?';
  @override String get cancelarLancamentoMsg => 'You have unsaved info. Discard it?';
  @override String get simCancelar => 'Yes, discard';
  @override String get lancamentoSalvoFotoNao => 'Saved, but the photo was not kept.';
  @override String lancamentoSalvoParcelas(int n) => 'amount split into $n monthly entries.';
  @override String parcelaAvisoSemValor(int r, String a, String t) =>
      '$r monthly entries will be created ($a to $t), one per month.';
  @override
  String parcelaAvisoComValor(int r, String v, String a, String t) =>
      '$r monthly entries of $v will be created ($a to $t), one per month.';
  @override
  String parcelaSalva(int a, int t, int n) =>
      'Installment $a/$t saved: amount split into $n monthly entries.';
  @override String get fotoCupomTitulo => 'Receipt photo';
  @override String get lendoCupom => 'Reading receipt...';
  @override String get dicaFoto => 'Shoot the receipt from above, with good light.';
  @override String get tirarFoto => 'Take photo';
  @override String get escolherGaleria => 'Choose from gallery';
  @override String imagemGrandeMsg(String a, String m) => 'Image too large ($a MB, max $m MB).';
  @override String get cupomIlegivel => 'Could not read the receipt. Try a sharper photo.';
  @override String falhaLerCupom(String e) => 'Failed to read receipt: $e';
  @override String get periodoMes => 'Month';
  @override String get periodo30 => '30 days';
  @override String get periodoAno => 'Year';
  @override String get periodoCustom => 'Custom';
  @override String get semDados => 'No data to display.';
  @override String get despesasXReceitas => 'Expenses vs Income';
  @override String get totalPeriodo => 'Total period';
  @override String get saldo => 'Balance';
  @override String get despesas => 'Expenses';
  @override String get receitas => 'Income';
  @override String get gastosPorDia => 'Spending per day';
  @override String get porCategoria => 'By category';
  @override String get porPagamento => 'By payment method';
  @override String graficoAcessivel(String d, String r, String s) => 'Bar chart: expenses $d, income $r, balance $s';
  @override String get editarPerfil => 'Edit profile';
  @override String get bemVindo => 'Welcome!';
  @override String get ajustePerfil => 'Adjust your name, avatar and background color.';
  @override String get vamosCriarPerfil => 'Create your profile to personalize the app.';
  @override String get escolhaAvatar => 'Choose your avatar';
  @override String get avatar => 'Avatar';
  @override String get usarFoto => 'Use photo';
  @override String get trocarFotoCurto => 'Change photo';
  @override String get semEmojisRecentes => 'No recent emojis';
  @override String get buscarEmoji => 'Search emoji';
  @override String get toqueTrocarAvatar => 'Tap to change the avatar';
  @override String get nomeUsuario => 'User name';
  @override String get informeNome => 'Enter your name';
  @override String get nomeCurto => 'Use at least 2 letters';
  @override String get outroEmoji => 'Another emoji';
  @override String get digiteOutroEmoji => 'Type another emoji';
  @override String get emojiInvalido => 'Type a single valid emoji';
  @override String get tema => 'Theme';
  @override String get claro => 'Light';
  @override String get escuro => 'Dark';
  @override String get corFundo => 'Background color';
  @override String get comecar => 'Get started';
  @override String get perfilAtualizado => 'Profile updated';
  @override String get descartarAlteracoes => 'Discard changes?';
  @override String get descartarAlteracoesMsg => 'You changed the profile. Leaving discards the changes.';
  @override String get descartarSair => 'Discard & leave';
  @override String get trocarFoto => 'Change avatar photo';
  @override String get escolherEmoji => 'Pick an emoji';
  @override String get escolhaEmoji => 'Pick an emoji';
  @override String get fotoGaleria => 'Photo from gallery';
  @override String get gradeEmojis => 'Grid with every emoji';
  @override String get arrastarRecorte => 'Drag to position, zoom below';
  @override String get voltarEmoticon => 'Go back to the emoji';
  @override String get seuNome => 'Your name';
  @override String get ajustarFoto => 'Adjust photo';
  @override
  String get ajustarFotoDica => 'Drag the photo to position the crop.';
  @override String get removerFoto => 'Remove photo (use emoji)';
  @override String get imagemAte5MB => 'Image up to 5 MB';
  @override String get ajustarRecorte => 'Adjust position and crop';
  @override String get aplicar => 'Apply';
  @override String imagemInvalida(String e) => 'Could not use image: $e';
  @override String get seguranca => 'Security';
  @override String get bloqueioDesativado => 'App lock is off';
  @override String get bloqueioDesativadoMsg => 'With a 4-6 digit PIN, Mango asks for it on every open.';
  @override String get criarPin => 'Create PIN';
  @override String get pinAtivo => 'PIN on';
  @override String pinDigitos(int n) => '$n digits';
  @override String get desbloquearBiometria => 'Unlock with biometrics';
  @override String get conferindoAparelho => 'Checking device...';
  @override String get semBiometria => 'No biometrics enrolled on this device';
  @override String get comBiometria => 'Device fingerprint/face, PIN as backup';
  @override String get alterarPin => 'Change PIN';
  @override String get desativarBloqueio => 'Turn off lock';
  @override String get usarBiometria => 'Use biometrics?';
  @override String get usarBiometriaMsg => 'Mango can also use device biometrics to unlock.';
  @override String get agoraNao => 'Not now';
  @override String get ativar => 'Enable';
  @override String get alterar => 'Change';
  @override String get desativar => 'Disable';
  @override String get criar => 'Create';
  @override String get pinAtual => 'Current PIN';
  @override String get novoPin => 'New PIN (4 to 6 digits)';
  @override String get confirmar => 'Confirm';
  @override String get cancelar => 'Cancel';
  @override String get confirmePin => 'Confirm the PIN';
  @override String get confirmeNovoPin => 'Confirm the new PIN';
  @override String pinRegra(int a, int b) => 'Use $a to $b digits.';
  @override String get pinsNaoConferem => 'PINs do not match.';
  @override String get bloqueioAtivado => 'Lock enabled.';
  @override String get biometriaAtivada => 'Biometrics enabled.';
  @override String get pinAlterado => 'PIN changed.';
  @override String get bloqueioDesativadoOk => 'Lock disabled.';
  @override String naoSalvar(String e) => 'Could not save: $e';
  @override String get mangoBloqueado => 'Mango locked';
  @override String get digitePin => 'Enter the PIN to continue';
  @override String get pinIncorreto => 'Wrong PIN';
  @override String get esqueciPin => 'I forgot my PIN';
  @override String get esqueciPinMsg => 'Mango is local: a forgotten PIN cannot be recovered. Use biometrics or reinstall.';
  @override String get entendi => 'Got it';
  @override String get desbloquearMango => 'Unlock Mango';
  @override String get usarBiometriaAcao => 'Use biometrics';
  @override String get apagar => 'Delete';
  @override String muitasTentativas(String t) => 'Too many attempts. Try again in $t';
  @override String get diagnostico => 'Diagnostics';
  @override String get diagnosticoMsg => 'Failures logged on this device live here, if any.';
  @override
  String get diagnosticoDetalhe =>
      'Failures that happened on this device. Nothing is sent automatically: it '
      'only leaves here when you tap Share and pick a destination. The CSV backup '
      'does not include this log.';
  @override
  String get nenhumaFalhaDetalhe =>
      'When something breaks here, the detail shows on this screen — ready for '
      'you to share it if you want.';
  @override String get compartilhar => 'Share';
  @override String get copiar => 'Copy';
  @override String get registroCopiado => 'Log copied.';
  @override String get registroApagado => 'Failure log cleared.';
  @override String get apagarRegistro => 'Clear the log?';
  @override
  String get apagarRegistroMsg =>
      'Listed failures will be erased from this device. Share them first if you '
      'still need them for support.';

  @override
  String get esqueciPinDetalhe =>
      'Mango is local: there is no email or server to recover a forgotten PIN.\n\n'
      '• If biometrics is on, use your fingerprint/face to get in and change '
      'the PIN in Menu → Security.\n\n'
      '• Without biometrics, the only way out is uninstalling the app — which '
      'erases your entries. If you exported the CSV before (Menu → Export as '
      'CSV), you can import it back later.';
  @override String tempoEspera(String t) => 'Too many attempts. Try again in $t';
  @override String tempoSegundos(int s) => '$s s';
  @override String tempoMinutos(int m) => '$m min';
  @override String tempoMinutosSegundos(int m, int s) => '$m min $s s';
  @override
  String get erroSalvarConfig => 'Could not read the security settings:';
  @override
  String get naoSalvarConfig => 'Could not save: ';

  @override
  String get bloqueioDesativadoDetalhe =>
      'With a 4 to 6 digit PIN, Mango asks for it every time you open the app '
      'or come back from the background. Your data stays on this device — the '
      'PIN only stops whoever picks up your unlocked phone from seeing your '
      'entries.';
  @override
  String get biometriaReserva =>
      'Device fingerprint/face, with the PIN as a fallback';
  @override
  String get biometriaTituloMsg =>
      'Besides the PIN, Mango can ask for your fingerprint/face to unlock. '
      'The PIN still works as a fallback.';
  @override String get nenhumaFalha => 'No failures logged';
  @override String get nenhumaFalhaMsg => 'When something breaks, the detail shows here.';
  @override String get falhaLeitura => 'Could not read the failure log.';
  @override String naoCompartilhar(String e) => 'Could not share: $e';
  @override String naoCopiar(String e) => 'Could not copy: $e';
  @override String get fotoOuManual => 'Receipt photo or manual entry';
  @override String get receitaManual => 'Manual income entry';
  @override String get fotoCupomFiscal => 'Receipt photo';
  @override String get appLePreenche => 'The app reads and fills the data';
  @override String get lancamentoManual => 'Manual entry';
  @override String get digiteGasto => 'Type the expense by hand';
  @override String get lancamentosSub => 'Expense and income entries';
  @override String get totaisSub => 'Totals by period, category and payment';
  @override String get editarPerfilSub => 'Name, avatar and background color';
  @override String get segurancaSub => 'App lock with PIN and biometrics';
  @override String get exportar => 'Export to CSV';
  @override String get exportarSub => 'Save a backup of entries';
  @override String get importarBackup => 'Import backup';
  @override String get importarBackupSub => 'Merge entries from a CSV';
  @override String get sobre => 'About Mango';
  @override String get sobreTexto => 'Expense tracker with OCR, 100% offline.';
  @override String backupCom(int n, String? nome) => nome == null ? 'Backup with $n Mango entries.' : 'Backup with $n entries from $nome.';
  @override String get backupAviso => 'The .csv is not encrypted, keep it in a safe place';
  @override String get backupVazio => 'No entries to export.';
  @override String backupExportado(String n) => 'Backup saved as $n';
  @override String falhaExportar(String e) => 'Could not export: $e';
  @override String get nenhumLancamentoArquivo => 'No valid entries in file';
  @override String perfilTambemRestaurado(String n, String t) => ' Profile of $n ($t theme) will also be restored.';
  @override String importarBackupMsg(int n, String p) => 'The $n from CSV will be merged. Duplicates skipped.$p';
  @override String get importarBackupTitulo => 'Import backup?';
  @override String importacaoOk(int a, int b, String c) => 'Import: $a new, $b duplicates.$c';
  @override String ignoradasLines(int n) => ' $n line(s) skipped.';
  @override String cartoesImportados(int n) => ' $n card(s) also restored.';
  // ---------------- credit cards ----------------
  @override String get cartoes => 'Cards';
  @override String get cartoesSub => 'Monthly spending per card';
  @override String get novoCartao => 'New card';
  @override String get adicionarCartao => 'Add card';
  @override String get editarCartao => 'Edit card';
  @override String get nenhumCartao => 'No cards yet';
  @override String get nenhumCartaoMsg => 'Add your card (no number or expiry needed) to track its monthly statement.';
  @override String get banco => 'Bank';
  @override String get informeBanco => "Enter the card's bank";
  @override String get bandeira => 'Network';
  @override String get nomeCartao => 'Card name';
  @override String get nomeCartaoHint => 'What would you like to call this card';
  @override String get informeNomeCartao => 'Give the card a name';
  @override String get diaFechamento => 'Closing day';
  @override String get diaPagamento => 'Payment day';
  @override String get diaInvalido => 'Day must be between 1 and 31';
  @override String get salvarCartao => 'Save card';
  @override String get cartaoSalvo => 'Card saved';
  @override String get excluirCartao => 'Delete card?';
  @override String excluirCartaoMsg(String nome) => 'Delete "$nome"? Spending stays saved, just without a linked card.';
  @override String get cartaoExcluido => 'Card deleted';
  @override String get totalFatura => 'Statement total';
  @override String faturaDe(String mes) => '$mes statement';
  @override String fechamentoEm(String data) => 'Closes on $data';
  @override String pagamentoEm(String data) => 'Due on $data';
  @override String get semGastosCartao => 'No spending this month';
  @override String get campoCartao => 'Card';
  @override String get semCartao => 'No card';
  @override String get fechamentoFatura => 'Statement closes';
  @override String get pagamentoFatura => 'Payment due';
  @override String lembreteFechamento(String nome) => 'The statement for card $nome closes today.';
  @override String lembretePagamento(String nome) => 'Payment for card $nome is due today.';
  @override String get permissaoNotificacoes => 'Mango can notify you when the statement closes and when payment is due.';
  @override String bandeiraLabel(String name) {
    switch (name) {
      case 'visa': return 'Visa';
      case 'mastercard': return 'Mastercard';
      case 'elo': return 'Elo';
      case 'amex': return 'American Express';
      case 'hipercard': return 'Hipercard';
      case 'outras': return 'Other';
      default: return name;
    }
  }
  @override String categoriaLabel(String name) {
    switch (name) {
      case 'alimentacao': return 'Dining';
      case 'transporte': return 'Transport';
      case 'mercado': return 'Groceries';
      case 'saude': return 'Health';
      case 'lazer': return 'Leisure';
      case 'moradia': return 'Housing';
      case 'outros': return 'Other';
      case 'salario': return 'Salary';
      case 'investimentos': return 'Investments';
      case 'bonificacao': return 'Bonus';
      case 'freelance': return 'Freelance';
      case 'rendaExtra': return 'Extra income';
      case 'aluguel': return 'Rent';
      case 'pensao': return 'Pension';
      default: return name;
    }
  }
  @override String pagamentoLabel(String name) {
    switch (name) {
      case 'dinheiro': return 'Cash';
      case 'debito': return 'Debit';
      case 'credito': return 'Credit';
      case 'pix': return 'PIX';
      default: return 'Other';
    }
  }
  @override String tipoLabel(String name) => name == 'receita' ? 'Income' : 'Expense';
  @override String get temaClaro => 'light';
  @override String get temaEscuro => 'dark';
  @override String get currencySymbol => '\$';
  @override DatePatterns get patterns => const DatePatterns(dayMonth: 'MM/dd', dayMonthYear: 'MM/dd/yyyy', dayMonthYearTime: 'MM/dd/yyyy  HH:mm', monthYear: 'MMMM yyyy', monthName: 'MMMM', shortDay: 'dd', shortDayMonth: 'MM/dd', weekdayDayMonth: 'EEE, MM/dd');
}
