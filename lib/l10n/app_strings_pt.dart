part of 'app_strings.dart';
// pt-BR: textos atuais do app, centralizados.
class PtBrStrings extends AppStrings {
  const PtBrStrings();
  @override Locale get locale => const Locale('pt', 'BR');
  @override String get appName => 'Mango';
  @override String get ok => 'OK';
  @override String get cancel => 'Cancelar';
  @override String get voltar => 'Voltar';
  @override String get nao => 'Não';
  @override String get salvar => 'Salvar';
  @override String get excluir => 'Excluir';
  @override String get limpar => 'Limpar';
  @override String get menu => 'Menu';
  @override String get gastos => 'Gastos';
  @override String get relatorios => 'Relatórios';
  @override String get meusGastos => 'Meus gastos';
  @override String get continuarEditando => 'Continuar editando';
  @override String erroCarregar(String e) => 'Erro ao carregar: $e';

  @override String erroPerfil(String e) => 'Erro ao carregar o perfil: $e';
  @override
  String erroSegurancaApp(String e) =>
      'Erro ao carregar a segurança do app: $e';
  @override
  String imagemAvatarGrande(String a, String m) =>
      'A imagem é grande demais ($a MB, máximo $m MB). Escolha uma imagem menor.';
  @override String get desbloqueioMango => 'Desbloquear o Mango';
  @override
  String get parteNaoDesenhada =>
      'Esta parte da tela não pôde ser desenhada.\n'
      'Menu → Diagnóstico mostra o detalhe da falha.';
  @override String get ola => 'Olá!';
  @override String olaNome(String n) => 'Olá, $n!';
  @override String get bemVindoMango => 'Bem-vindo ao Mango!';
  @override String get temBackup => 'Você já tem um arquivo de backup?';
  @override String get restaurarBackup => 'Restaurar backup';
  @override String get criarPerfilNovo => 'Criar perfil novo';
  @override String get escolherBackup => 'Escolher arquivo de backup';
  @override String erroAbrirSeletor(String e) => 'Erro ao abrir o seletor: $e';
  @override String erroLerArquivo(String e) => 'Erro ao ler o arquivo: $e';
  @override String get nenhumDadoBackup => 'Nenhum dado válido encontrado no arquivo de backup';
  @override String get backupSemPerfil => 'Backup sem perfil';
  @override String backupSemPerfilMsg(int n) => 'O arquivo tem $n lançamento(s), mas sem os dados do perfil. Importar e continuar o cadastro?';
  @override String get importar => 'Importar';
  @override String get restaurarBackupTitulo => 'Restaurar backup?';
  @override String restaurarBackupMsg(String n, String t, int q) => 'Perfil de ${n.isEmpty ? "usuário" : n} (tema $t) com $q lançamento(s). Restaurar?';
  @override String get restaurar => 'Restaurar';
  @override String backupRestaurado(int n) => 'Backup restaurado: $n lançamento(s) novo(s). Confira seu perfil.';
  @override String lancamentosImportados(int n) => '$n lançamento(s) importado(s). Complete seu perfil.';
  @override String get usuario => 'usuário';
  @override String get selecionarAno => 'Selecionar ano';
  @override String selecionarMesDe(int y) => 'Selecionar mês de $y';
  @override String get excluirGasto => 'Excluir gasto?';
  @override String excluirGastoMsg(String v) => 'Deseja excluir este gasto de $v?';
  @override String get gastoExcluido => 'Gasto excluído';
  @override String get hoje => 'hoje';
  @override String gastosDoDia(String d) => 'Gastos do dia $d';
  @override String gastosDeSemana(String i, String f) => 'Gastos de $i a $f';
  @override String gastosDeMes(String m) => 'Gastos de $m';
  @override String get dia => 'Dia';
  @override String get semana => 'Semana';
  @override String get mes => 'Mês';
  @override String get mesAnterior => 'Mês anterior';
  @override String get proximoMes => 'Próximo mês';
  @override String get nenhumGastoMes => 'Nenhum gasto neste mês.\nUse o botão + para começar.';
  @override String get nenhumGastoPeriodo => 'Nenhum gasto neste período.\nToque no filtro para ver o mês.';
  @override String get semGastosPeriodo => 'Sem gastos no período.';
  @override String get excluirAcao => 'Excluir';
  @override String get novaDespesa => 'Nova despesa';
  @override String get novaReceita => 'Nova receita';
  @override String get editarGasto => 'Editar gasto';
  @override String get editarReceita => 'Editar receita';
  @override String get despesa => 'Despesa';
  @override String get receita => 'Receita';
  @override String get dadosCupom => 'Dados extraídos do cupom.\nConfira antes de salvar.';
  @override String valorLabel(String s) => 'Valor ($s)';
  @override String get valorHint => '0,00';
  @override String get informeValor => 'Informe o valor';
  @override String get estabelecimento => 'Estabelecimento';
  @override String get origem => 'Origem';
  @override String get descricaoOpcional => 'Descrição (opcional)';
  @override String get categoria => 'Categoria';
  @override String get formaPagamento => 'Forma de pagamento';
  @override String get dataHora => 'Data e hora';
  @override String get textoCupom => 'Texto lido do cupom';
  @override
  String get dadosExtraidos =>
      'Dados extraídos do cupom.\nConfira antes de salvar.';
  @override String get fotoCupom => 'Foto do cupom';
  @override String get toqueAmpliar => 'Toque para ampliar';
  @override String get fotoCupomErro => 'A foto do cupom não pôde ser exibida.';
  @override String get salvarAlteracoes => 'Salvar alterações';
  @override String get salvarGasto => 'Salvar gasto';
  @override String get salvarReceita => 'Salvar receita';
  @override String get cancelarLancamento => 'Cancelar lançamento?';
  @override String get cancelarLancamentoMsg => 'Você tem informações não salvas. Deseja cancelar e perder todas as alterações?';
  @override String get simCancelar => 'Sim, cancelar';
  @override String get lancamentoSalvoFotoNao => 'Lançamento salvo, mas a foto do cupom não pôde ser guardada.';
  @override String lancamentoSalvoParcelas(int n) => 'valor dividido em $n lançamentos mensais.';
  @override String parcelaAvisoSemValor(int r, String a, String t) =>
      'Serão criados $r lançamentos mensais ($a até $t), um por mês.';
  @override
  String parcelaAvisoComValor(int r, String v, String a, String t) =>
      'Serão criados $r lançamentos mensais de $v ($a até $t), um por mês.';
  @override
  String parcelaSalva(int a, int t, int n) =>
      'Parcela $a/$t salva: valor dividido em $n lançamentos mensais.';
  @override String get fotoCupomTitulo => 'Foto do cupom';
  @override String get lendoCupom => 'Lendo o cupom...';
  @override String get dicaFoto => 'Fotografe o cupom de cima, com boa luz e sem sombra.';
  @override String get tirarFoto => 'Tirar foto';
  @override String get escolherGaleria => 'Escolher da galeria';
  @override String imagemGrandeMsg(String a, String m) => 'A imagem é grande demais ($a MB, máximo $m MB). Tire uma foto do cupom ou escolha uma imagem menor.';
  @override String get cupomIlegivel => 'Não foi possível ler o cupom. Tente uma foto mais nítida.';
  @override String falhaLerCupom(String e) => 'Falha ao ler o cupom: $e';
  @override String get periodoMes => 'Mês';
  @override String get periodo30 => '30 dias';
  @override String get periodoAno => 'Ano';
  @override String get periodoCustom => 'Custom';
  @override String get semDados => 'Sem dados para visualização.';
  @override String get despesasXReceitas => 'Despesas x Receitas';
  @override String get totalPeriodo => 'Total do período';
  @override String get saldo => 'Saldo';
  @override String get despesas => 'Despesas';
  @override String get receitas => 'Receitas';
  @override String get gastosPorDia => 'Gastos por dia';
  @override String get porCategoria => 'Por categoria';
  @override String get porPagamento => 'Por forma de pagamento';
  @override String graficoAcessivel(String d, String r, String s) => 'Gráfico de barras: despesas $d, receitas $r, saldo $s';
  @override String get editarPerfil => 'Editar perfil';
  @override String get bemVindo => 'Bem-vindo!';
  @override String get ajustePerfil => 'Ajuste seu nome, avatar e cor de fundo.';
  @override String get vamosCriarPerfil => 'Vamos criar seu perfil para personalizar o app.';
  @override String get escolhaAvatar => 'Escolha seu avatar';
  @override String get avatar => 'Avatar';
  @override String get usarFoto => 'Usar foto';
  @override String get trocarFotoCurto => 'Trocar foto';
  @override String get semEmojisRecentes => 'Sem emojis recentes';
  @override String get buscarEmoji => 'Buscar emoji';
  @override String get toqueTrocarAvatar => 'Toque para trocar o avatar';
  @override String get nomeUsuario => 'Nome do usuário';
  @override String get informeNome => 'Informe seu nome';
  @override String get nomeCurto => 'Use ao menos 2 letras para o nome';
  @override String get outroEmoji => 'Outro emoji';
  @override String get digiteOutroEmoji => 'Digite outro emoji';
  @override String get emojiInvalido => 'Digite um único emoji válido';
  @override String get tema => 'Tema';
  @override String get claro => 'Claro';
  @override String get escuro => 'Escuro';
  @override String get corFundo => 'Cor de fundo';
  @override String get comecar => 'Começar';
  @override String get perfilAtualizado => 'Perfil atualizado';
  @override String get descartarAlteracoes => 'Descartar alterações?';
  @override String get descartarAlteracoesMsg => 'Você mudou o perfil e ainda não salvou. Sair agora descarta as alterações.';
  @override String get descartarSair => 'Descartar e sair';
  @override String get trocarFoto => 'Trocar foto do avatar';
  @override String get escolherEmoji => 'Escolher emoticon';
  @override String get escolhaEmoji => 'Escolha um emoji';
  @override String get fotoGaleria => 'Foto da galeria';
  @override String get gradeEmojis => 'Grade com todos os emojis';
  @override String get arrastarRecorte => 'Arrastar para posicionar, zoom abaixo';
  @override String get voltarEmoticon => 'Voltar a usar o emoticon';
  @override String get seuNome => 'Seu nome';
  @override String get ajustarFoto => 'Ajustar foto';
  @override
  String get ajustarFotoDica => 'Arraste a foto para posicionar o recorte.';
  @override String get removerFoto => 'Remover foto (usar emoticon)';
  @override String get imagemAte5MB => 'Imagem de até 5 MB';
  @override String get ajustarRecorte => 'Ajustar posição e recorte';
  @override String get aplicar => 'Aplicar';
  @override String imagemInvalida(String e) => 'Não foi possível usar a imagem: $e';
  @override String get seguranca => 'Segurança';
  @override String get bloqueioDesativado => 'O bloqueio do app está desativado';
  @override String get bloqueioDesativadoMsg => 'Com um PIN de 4 a 6 dígitos, o Mango pede a senha toda vez que abre ou volta do segundo plano.';
  @override String get criarPin => 'Criar PIN';
  @override String get pinAtivo => 'PIN ativo';
  @override String pinDigitos(int n) => '$n dígitos';
  @override String get desbloquearBiometria => 'Desbloquear com biometria';
  @override String get conferindoAparelho => 'Conferindo o aparelho...';
  @override String get semBiometria => 'Este aparelho não tem biometria cadastrada';
  @override String get comBiometria => 'Digital/rosto do aparelho, com o PIN como reserva';
  @override String get alterarPin => 'Alterar PIN';
  @override String get desativarBloqueio => 'Desativar bloqueio';
  @override String get usarBiometria => 'Usar biometria?';
  @override String get usarBiometriaMsg => 'Além do PIN, o Mango pode pedir a digital/rosto do aparelho para desbloquear.';
  @override String get agoraNao => 'Agora não';
  @override String get ativar => 'Ativar';
  @override String get alterar => 'Alterar';
  @override String get desativar => 'Desativar';
  @override String get criar => 'Criar';
  @override String get pinAtual => 'PIN atual';
  @override String get novoPin => 'Novo PIN (4 a 6 dígitos)';
  @override String get confirmar => 'Confirmar';
  @override String get cancelar => 'Cancelar';
  @override String get confirmePin => 'Confirme o PIN';
  @override String get confirmeNovoPin => 'Confirme o novo PIN';
  @override String pinRegra(int a, int b) => 'Use de $a a $b dígitos.';
  @override String get pinsNaoConferem => 'Os PINs não conferem.';
  @override String get bloqueioAtivado => 'Bloqueio ativado.';
  @override String get biometriaAtivada => 'Biometria ativada.';
  @override String get pinAlterado => 'PIN alterado.';
  @override String get bloqueioDesativadoOk => 'Bloqueio desativado.';
  @override String naoSalvar(String e) => 'Não foi possível salvar: $e';
  @override String get mangoBloqueado => 'Mango bloqueado';
  @override String get digitePin => 'Digite o PIN para continuar';
  @override String get pinIncorreto => 'PIN incorreto';
  @override String get esqueciPin => 'Esqueci meu PIN';
  @override String get esqueciPinMsg => 'O Mango é local: não há como recuperar um PIN esquecido. Use a biometria ou reinstale o app.';
  @override String get entendi => 'Entendi';
  @override String get desbloquearMango => 'Desbloquear o Mango';
  @override String get usarBiometriaAcao => 'Usar biometria';
  @override String muitasTentativas(String t) => 'Muitas tentativas. Tente de novo em $t';
  @override String get diagnostico => 'Diagnóstico';
  @override String get diagnosticoMsg => 'Aqui ficam as falhas registradas neste aparelho, se houver.';
  @override
  String get diagnosticoDetalhe =>
      'Falhas acontecidas neste aparelho. Nada é enviado automaticamente: só sai '
      'daqui se você tocar em Compartilhar e escolher o destino. O backup em CSV '
      'não inclui este registro.';
  @override
  String get nenhumaFalhaDetalhe =>
      'Quando algo quebrar por aqui, o detalhe aparece nesta tela — pronto para '
      'você compartilhar, se quiser.';
  @override String get apagar => 'Apagar';
  @override String get compartilhar => 'Compartilhar';
  @override String get copiar => 'Copiar';
  @override String get registroCopiado => 'Registro copiado.';
  @override String get registroApagado => 'Registro de falhas apagado.';
  @override String get apagarRegistro => 'Apagar o registro?';
  @override
  String get apagarRegistroMsg =>
      'As falhas listadas serão apagadas deste aparelho. Se você ainda precisar '
      'delas para um suporte, compartilhe antes.';

  @override
  String get esqueciPinDetalhe =>
      'O Mango é local: não existe e-mail nem servidor para recuperar um PIN '
      'esquecido.\n\n'
      '• Se a biometria estiver ativa, use a digital/rosto para entrar e trocar '
      'o PIN em Menu → Segurança.\n\n'
      '• Sem biometria, a saída é desinstalar o app — o que apaga os '
      'lançamentos. Se você exportou o CSV antes (Menu → Exportar em CSV), dá '
      'para importar de volta depois.';
  @override String tempoEspera(String t) => 'Muitas tentativas. Tente de novo em $t';
  @override String tempoSegundos(int s) => '$s s';
  @override String tempoMinutos(int m) => '$m min';
  @override String tempoMinutosSegundos(int m, int s) => '$m min $s s';
  @override
  String get erroSalvarConfig =>
      'Não foi possível ler a configuração de segurança:';
  @override
  String get naoSalvarConfig => 'Não foi possível salvar: ';

  @override
  String get bloqueioDesativadoDetalhe =>
      'Com um PIN de 4 a 6 dígitos, o Mango pede a senha toda vez que abre ou '
      'volta do segundo plano. Os dados continuam só neste aparelho — o PIN só '
      'evita que quem pegar o celular destravado veja seus lançamentos.';
  @override
  String get biometriaReserva =>
      'Digital/rosto do aparelho, com o PIN como reserva';
  @override
  String get biometriaTituloMsg =>
      'Além do PIN, o Mango pode pedir a digital/rosto do aparelho para '
      'desbloquear. O PIN continua valendo como reserva.';
  @override String get nenhumaFalha => 'Nenhuma falha registrada';
  @override String get nenhumaFalhaMsg => 'Quando algo quebrar, o detalhe aparece aqui.';
  @override String get falhaLeitura => 'Não foi possível ler o registro de falhas.';
  @override String naoCompartilhar(String e) => 'Não foi possível compartilhar: $e';
  @override String naoCopiar(String e) => 'Não foi possível copiar: $e';
  @override String get fotoOuManual => 'Foto do cupom ou lançamento manual';
  @override String get receitaManual => 'Lançamento manual de entrada';
  @override String get fotoCupomFiscal => 'Foto do cupom fiscal';
  @override String get appLePreenche => 'O app lê e preenche os dados';
  @override String get lancamentoManual => 'Lançamento manual';
  @override String get digiteGasto => 'Digite o gasto à mão';
  @override String get lancamentosSub => 'Lançamentos de despesas e receitas';
  @override String get totaisSub => 'Totais por período, categoria e pagamento';
  @override String get editarPerfilSub => 'Nome, avatar e cor de fundo';
  @override String get segurancaSub => 'Bloqueio do app com PIN e biometria';
  @override String get exportar => 'Exportar em CSV';
  @override String get exportarSub => 'Salvar backup dos lançamentos';
  @override String get importarBackup => 'Importar em CSV';
  @override String get importarBackupSub => 'Somar lançamentos de um CSV';
  @override String get sobre => 'Sobre o Mango';
  @override String get sobreTexto => 'Controle de gastos com OCR, 100% offline.';
  @override String backupCom(int n, String? nome) => nome == null ? 'Backup com $n lançamento(s) do Mango.' : 'Backup com $n lançamento(s) de $nome.';
  @override String get backupAviso => 'O .csv não é criptografado, guarde em local seguro.';
  @override String get backupVazio => 'Não há lançamentos para exportar.';
  @override String backupExportado(String n) => 'Backup salvo como $n';
  @override String falhaExportar(String e) => 'Não foi possível exportar: $e';
  @override String get nenhumLancamentoArquivo => 'Nenhum lançamento válido no arquivo';
  @override String perfilTambemRestaurado(String n, String t) => ' Perfil de $n (tema $t) também será restaurado.';
  @override String importarBackupMsg(int n, String p) => 'Os $n do CSV serão somados. Duplicatas ignoradas.$p';
  @override String get importarBackupTitulo => 'Importar backup?';
  @override String importacaoOk(int a, int b, String c) => 'Importação: $a novo(s), $b duplicado(s).$c';
  @override String ignoradasLines(int n) => ' $n linha(s) ignorada(s).';
  @override String cartoesImportados(int n) => ' $n cartão(ões) também restaurado(s).';
  // ---------------- cartões de crédito ----------------
  @override String get cartoes => 'Cartões';
  @override String get cartoesSub => 'Gastos do mês cartão a cartão';
  @override String get novoCartao => 'Novo cartão';
  @override String get adicionarCartao => 'Adicionar cartão';
  @override String get editarCartao => 'Editar cartão';
  @override String get nenhumCartao => 'Nenhum cartão cadastrado';
  @override String get nenhumCartaoMsg => 'Cadastre seu cartão (sem número nem validade) para acompanhar a fatura do mês.';
  @override String get banco => 'Banco';
  @override String get informeBanco => 'Informe o banco do cartão';
  @override String get bandeira => 'Bandeira';
  @override String get nomeCartao => 'Nome do cartão';
  @override String get nomeCartaoHint => 'Como você quer chamar este cartão';
  @override String get informeNomeCartao => 'Dê um nome ao cartão';
  @override String get diaFechamento => 'Dia do fechamento';
  @override String get diaPagamento => 'Dia do pagamento';
  @override String get diaInvalido => 'Dia deve ser entre 1 e 31';
  @override String get salvarCartao => 'Salvar cartão';
  @override String get cartaoSalvo => 'Cartão salvo';
  @override String get excluirCartao => 'Excluir cartão?';
  @override String excluirCartaoMsg(String nome) => 'Apagar o cartão "$nome"? Os gastos continuam salvos, apenas sem cartão vinculado.';
  @override String get cartaoExcluido => 'Cartão excluído';
  @override String get totalFatura => 'Total da fatura';
  @override String faturaDe(String mes) => 'Fatura de $mes';
  @override String fechamentoEm(String data) => 'Fecha em $data';
  @override String pagamentoEm(String data) => 'Pagamento em $data';
  @override String get semGastosCartao => 'Sem gastos neste mês';
  @override String get campoCartao => 'Cartão';
  @override String get semCartao => 'Sem cartão';
  @override String get fechamentoFatura => 'Fechamento da fatura';
  @override String get pagamentoFatura => 'Pagamento da fatura';
  @override String lembreteFechamento(String nome) => 'A fatura do cartão $nome fecha hoje.';
  @override String lembretePagamento(String nome) => 'Vence hoje a fatura do cartão $nome.';
  @override String get permissaoNotificacoes => 'O Mango pode avisar fechamento e pagamento da fatura por notificação.';
  @override String bandeiraLabel(String name) {
    switch (name) {
      case 'visa': return 'Visa';
      case 'mastercard': return 'Mastercard';
      case 'elo': return 'Elo';
      case 'amex': return 'American Express';
      case 'hipercard': return 'Hipercard';
      case 'outras': return 'Outra';
      default: return name;
    }
  }
  @override String categoriaLabel(String name) {
    switch (name) {
      case 'alimentacao': return 'Alimentação';
      case 'transporte': return 'Transporte';
      case 'mercado': return 'Mercado';
      case 'saude': return 'Saúde';
      case 'lazer': return 'Lazer';
      case 'moradia': return 'Moradia';
      case 'outros': return 'Outros';
      case 'salario': return 'Salário';
      case 'investimentos': return 'Investimentos';
      case 'bonificacao': return 'Bonificação';
      case 'freelance': return 'Freelance';
      case 'rendaExtra': return 'Renda extra';
      case 'aluguel': return 'Aluguel';
      case 'pensao': return 'Pensão';
      default: return name;
    }
  }
  @override String pagamentoLabel(String name) {
    switch (name) {
      case 'dinheiro': return 'Dinheiro';
      case 'debito': return 'Débito';
      case 'credito': return 'Crédito';
      case 'pix': return 'PIX';
      default: return 'Outros';
    }
  }
  @override String tipoLabel(String name) => name == 'receita' ? 'Receita' : 'Despesa';
  @override String get temaClaro => 'claro';
  @override String get temaEscuro => 'escuro';
  @override String get currencySymbol => 'R\$';
  @override DatePatterns get patterns => const DatePatterns(dayMonth: 'dd/MM', dayMonthYear: 'dd/MM/yyyy', dayMonthYearTime: 'dd/MM/yyyy  HH:mm', monthYear: 'MMMM yyyy', monthName: 'MMMM', shortDay: 'dd', shortDayMonth: 'dd/MM', weekdayDayMonth: 'EEE, dd/MM');
}
