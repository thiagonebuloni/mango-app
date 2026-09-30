# Changelog

Mudanças relevantes do Mango, da mais recente para a mais antiga. Formato
inspirado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e
versionamento [SemVer](https://semver.org/lang/pt-BR/) — o `+N` do
`pubspec.yaml` é o *build number* do Android e **precisa** aumentar a cada
release publicada.

## [1.2.0] - 2026-09-29

### Adicionado

- **Bloqueio do app com PIN** (menu → *Segurança*): PIN de 4 a 6 dígitos,
  digitado em um teclado do próprio app e guardado no banco apenas como hash
  **PBKDF2-HMAC-SHA256** com sal aleatório (100.000 iterações) — o PIN em claro
  nunca é gravado, e a comparação do hash é feita em tempo constante. Com o
  bloqueio ativo, o app pede o desbloqueio ao abrir e **sempre que volta do
  segundo plano**; o conteúdo do app fica desmontado atrás da tela de bloqueio,
  então nada aparece na prévia de "app recentes" do Android.
- **Desbloqueio por biometria** (opcional, quando o aparelho tem digital/rosto
  cadastrado): quem valida é o sistema do aparelho — nenhum dado biométrico
  passa pelo app — e o PIN continua valendo como reserva. A oferta aparece logo
  depois de criar o PIN e a preferência pode ser mudada a qualquer momento na
  tela *Segurança*.
- **Trava por tentativas erradas:** as primeiras 5 tentativas são livres; da
  quinta errada em diante a tela de bloqueio espera 30 s e a espera **dobra a
  cada erro novo** (1 min, 2 min… até 30 min). Durante a espera ficam sem toque
  o teclado e o botão de biometria, e a contagem mora no banco: fechar ou
  reiniciar o app não zera a espera — só um desbloqueio bem-sucedido.
- Tela **Segurança**: criar, alterar ou desativar o bloqueio (a troca e a
  desativação sempre exigem o PIN atual) e ligar/desligar a biometria.
- Botão *Esqueci meu PIN* na tela de bloqueio, explicando que o app é local:
  sem biometria, a saída é desinstalar e reimportar o CSV exportado.

### Alterado

- Banco de dados na **v7** (tabela `seguranca`, o bloqueio) e na **v8**
  (`tentativas_falhas` e `bloqueado_ate`, a trava por tentativas), criadas na
  migração — bancos existentes mantêm todos os lançamentos e o perfil.
- Telas do Android passam a usar o tema `Theme.AppCompat.DayNight`, exigido
  pelo diálogo de biometria do `local_auth`.

### Segurança

- O hash do PIN e a preferência de biometria **não** entram no CSV nem no
  backup automático do sistema: restaurado em outro aparelho, o app abre sem
  tranca. A configuração existe só no banco local.

## [1.1.0] - 2026-09-29

### Adicionado

- **Registro local de falhas**: erros do app (build/layout, exceções não
  tratadas e falhas do OCR) são gravados em `falhas.jsonl` na área privada do
  aparelho, com rotação de 200 KB (saem as falhas mais antigas) e falhas
  repetidas em sequência somadas numa linha só (`×N`). Nada é enviado
  automaticamente — o APK de release continua sem permissão de internet.
- Tela **Diagnóstico** (menu → *Diagnóstico*): lista as falhas com hora,
  contexto e pilha de chamadas, e permite **compartilhar** (folha de
  compartilhamento do sistema), **copiar** ou **limpar** o registro; os
  botões ficam desativados enquanto não há falhas.
- Mensagem amigável no lugar do quadro cinza das telas quebradas em release,
  apontando para o *Diagnóstico* — em debug mantém a tela vermelha de
  desenvolvimento.

## [1.0.0] - 2026-09-28

Primeira versão publicada.

### Adicionado

- Lançamentos de **despesa e receita** com valor, data/hora, categoria, forma
  de pagamento, descrição e estabelecimento.
- **Leitura de cupom fiscal por foto**: OCR do Google ML Kit rodando no próprio
  aparelho, com parser de cupons brasileiros (SAT / NFC-e) e confirmação humana
  antes de salvar.
- **Categorização** por palavra-chave + memória por estabelecimento (o app
  aprende quando você corrige a categoria).
- **Parcelamento**: sufixo `x/y` no estabelecimento divide o valor e cria um
  lançamento por mês.
- **Resumos e relatórios** por dia, semana, mês, ano e intervalo custom, por
  categoria e por forma de pagamento, com gráfico de despesas × receitas.
- **Perfil** com nome, avatar (emoticon ou foto com recorte) e cor de fundo,
  com tema claro e escuro.
- **Backup em CSV**: exportar, importar somando aos lançamentos existentes e
  restaurar no primeiro acesso.
- **Foto do cupom** guardada nos documentos do app e exibida na edição do
  lançamento.
- **CI** no GitHub Actions rodando `flutter analyze` e `flutter test`.

### Segurança e privacidade

- Dados do app **fora do backup automático** do Android (nuvem), mantendo a
  transferência direta entre aparelhos.
- **Sem permissão de internet** no APK de release: as permissões `INTERNET` e
  `ACCESS_NETWORK_STATE` vinham de uma dependência de telemetria do ML Kit e
  são removidas no manifesto mesclado.
- Sem criptografia no CSV exportado, por decisão consciente: o arquivo é texto
  puro (abre direto em planilha) e o app avisa antes de exportar, porque uma
  senha esquecida significaria backup perdido para sempre — não há servidor
  para recuperá-la.
- Release assinado com chave própria (nunca com a chave de debug, que é
  pública).

### Limites conhecidos

- **iOS**: o OCR ainda não está implementado — o canal nativo `mango/ocr` só
  existe no Android, então no iPhone a foto do cupom cai no formulário manual.
- O CSV de backup não transporta fotos nem o texto bruto do OCR.
