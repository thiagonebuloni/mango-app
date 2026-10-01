---
title: Política de privacidade — Mango
permalink: /privacidade/
---
# Política de privacidade — Mango

**Última atualização:** 29 de setembro de 2026

O Mango é um aplicativo de controle de gastos pessoais que funciona **100%
offline**. Esta política descreve, de forma direta, quais dados o app usa e
para onde eles vão: **nenhum dado sai do seu aparelho**.

## 1. Dados que o app registra (e onde ficam)

| Dado | Onde fica |
| --- | --- |
| Lançamentos (valor, data/hora, categoria, forma de pagamento, descrição, estabelecimento) | Banco SQLite `mango.db`, na área privada do app no aparelho |
| Texto lido dos cupons (OCR) | Mesmo banco, coluna `raw`, na área privada do app |
| Fotos dos cupons | Área privada do app (documentos), apagadas quando o lançamento é excluído |
| Perfil (nome, emoticon, foto do avatar, cores e tema) | Mesmo banco |
| Registro de falhas do app (erro, pilha, hora) | Arquivo `falhas.jsonl` na área privada do app — listado em menu → *Diagnóstico* e fora do CSV |
| Bloqueio do app (hash do PIN, sal, iterações, preferência de biometria e a trava por tentativas: quantas falhas e até quando dura a espera) | Mesmo banco, tabela `seguranca` — fora do CSV; o PIN em claro **nunca** é gravado |

Não há servidor, conta de usuário, cadastro, login nem sincronização. O PIN
opcional (§3) é apenas uma tranca local do app, não uma conta: não existe
e-mail, senha de recuperação nem nada parecido. O app não declara a permissão
de **internet** no APK de release, ou seja, não tem como enviar dados para
lugar nenhum.

## 2. Dados que o app **não** coleta

- Não há coleta de dados pessoais, localização, contatos, identificadores de
  publicidade ou uso;
- Não há analytics, anúncios, SDKs de rastreamento nem envio automático de
  falhas para servidores (*crash reporting*): o registro de erros do app é
  **local** (ver §1) e só sai do aparelho se você compartilhar pelo menu
  *Diagnóstico*;
- Não há compartilhamento de dados com terceiros.

## 3. Permissões e acesso

- **Câmera e galeria:** usadas apenas quando você escolhe fotografar ou
  selecionar a imagem de um cupom, pela interface do próprio sistema
  (`image_picker`). A leitura do cupom (OCR) acontece **no aparelho**, com o
  modelo do Google ML Kit empacotado no APK — a imagem não é enviada para
  nenhum serviço.
- **Arquivos:** o app só lê o arquivo de backup CSV que você escolher e só
  escreve dentro da sua própria área privada.
- **Biometria:** usada apenas se você ligar o desbloqueio por biometria em
  menu → *Segurança* (as permissões `USE_BIOMETRIC`/`USE_FINGERPRINT` existem só
  para mostrar o diálogo do sistema). A digital/rosto **nunca** sai do sistema do aparelho: o
  app recebe apenas "deu certo" ou "não deu certo" — nenhum dado biométrico é
  lido, guardado ou compartilhado pelo Mango. O PIN do app, quando existe, é
  guardado no banco local como hash (PBKDF2 + sal aleatório), nunca em claro.

## 4. Backup

- **Backup do sistema (Android):** os dados do app são **excluídos** do backup
  automático na conta Google (regras em `android/app/src/main/res/xml/`). A
  transferência direta entre aparelhos (cabo / configuração inicial) continua
  funcionando.
- **Backup do app:** feito por você, quando quiser, em *menu → Exportar em
  CSV*. Esse arquivo é **texto puro, sem senha**, contém o perfil e os
  lançamentos, e vai para onde você escolher (arquivos, e-mail, mensageiro,
  nuvem). Guarde-o em local seguro: como ele está sob seu controle, a proteção
  dele é responsabilidade sua. A foto do avatar, a foto do cupom e o texto
  bruto do OCR **não** entram no CSV. O **bloqueio do app** (PIN/biometria)
  também não: restaurado em outro aparelho, o app volta sem tranca.

## 5. Exclusão dos dados

Desinstalar o app apaga tudo o que está na área privada dele. Você também pode
excluir lançamentos individualmente dentro do app (as fotos correspondentes são
removidas junto) e desligar o bloqueio a qualquer momento em menu → *Segurança*
(exige o PIN atual), o que apaga a linha da tabela `seguranca`. Não existe cópia
em servidor para pedir exclusão.

## 6. Crianças

O app não se destina a menores de 13 anos e não coleta dados de nenhum usuário.

## 7. Alterações nesta política

Mudanças relevantes serão registradas no `CHANGELOG.md` do repositório e nesta
página, com a data de atualização no topo.

## 8. Contato

Dúvidas sobre privacidade: abra uma *issue* em
<https://github.com/thiagonebuloni/mango-app> ou escreva para
<thiago.nebuloni@gmail.com>.

---

Este documento descreve o aplicativo publicado em
<https://github.com/thiagonebuloni/mango-app> (código aberto, sob licença MIT).
