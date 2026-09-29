# Changelog

Mudanças relevantes do Mango, da mais recente para a mais antiga. Formato
inspirado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e
versionamento [SemVer](https://semver.org/lang/pt-BR/) — o `+N` do
`pubspec.yaml` é o *build number* do Android e **precisa** aumentar a cada
release publicada.

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
