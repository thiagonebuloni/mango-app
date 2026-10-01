<p>
<img src="assets/icon/app_icon_master.png" width="128" height="128" align="center"/>
<p/>

# Mango

App mobile (Flutter) para registrar gastos, organizá-los em categorias e somar
total **diário, semanal e mensal**. Cada gasto pode ser digitado manualmente ou
preenchido automaticamente a partir da **foto de um cupom fiscal** (OCR on-device).


## Documentação

Este README cobre o essencial — instalar, rodar, testar e publicar. O detalhe
fica na **[wiki do projeto](https://github.com/thiagonebuloni/mango-app/wiki)**:

- [Instalação e atualização](https://github.com/thiagonebuloni/mango-app/wiki/Instalação-e-atualização)
  — APK, o caso do "Segundo espaço", assinatura e troca de chave;
- [Guia de uso](https://github.com/thiagonebuloni/mango-app/wiki/Guia-de-uso)
  — cupom, parcelas, categorias, relatórios e bloqueio;
- [Backup e privacidade](https://github.com/thiagonebuloni/mango-app/wiki/Backup-e-privacidade)
  — CSV, onde cada dado mora e o que sai (ou não) do aparelho.

As páginas de desenvolvedor (arquitetura, modelo de dados, parser de cupom,
internacionalização, testes e CI) estão **em construção** na wiki.


## Como funciona (custo R$ 0)

- **OCR:** Google ML Kit Text Recognition v2, rodando **no próprio aparelho**
  (gratuito, ilimitado, offline).
- **Parsing do cupom:** heurísticas locais (`lib/services/receipt_parser.dart`)
  extraem estabelecimento (CNPJ), data/hora, itens, **TOTAL** e forma de
  pagamento de cupons SAT/NFC-e brasileiros. A data do gasto é escolhida
  priorizando linhas de emissão/venda/cupom (ignorando validade/vencimento e
  aceitando a hora na linha de baixo) e **"À VISTA"** é interpretado como
  **Dinheiro**. Se o cupom for **parcelado** (`PARCELA 2/10`, `2 DE 10`,
  `EM 10X`), o estabelecimento sai como `LOJA XYZ 2/10` e a forma de
  pagamento é forçada para **Crédito**.
- **Parcelas:** ao salvar um lançamento com sufixo `x/y` no estabelecimento
  (ex.: `LOJA XYZ 1/10`, seja via cupom ou digitação manual), o valor total
  é **dividido** entre as parcelas restantes e uma cópia (`2/10`, `3/10`...)
  é criada para o mesmo dia dos meses seguintes (`lib/state/providers.dart` →
  `expandirParcelas`). A memória de categoria ignora o sufixo, então
  `LOJA 1/10` e `LOJA 2/10` contam como o mesmo estabelecimento.
- **Categorização:** regras por palavra-chave + **memória por estabelecimento**
  (o app aprende quando você corrige a categoria).
- **Confirmação humana:** o app nunca grava direto da foto — o formulário abre
  pré-preenchido para você conferir com 1 toque.
- **Dados 100% locais** (SQLite via sqflite). Sem servidor, sem backend, e o
  **backup automático do Android não leva esses dados para a conta Google** —
  veja [Backup, privacidade e onde ficam os dados](#backup-privacidade-e-onde-ficam-os-dados).
- **Bloqueio do app (opcional):** em menu → *Segurança* você cria um **PIN** de
  4 a 6 dígitos (guardado como hash PBKDF2-HMAC-SHA256 com sal aleatório, nunca
  em claro) e pode ligar o **desbloqueio por biometria** do aparelho. Com o
  bloqueio ativo, o app pede o PIN ao abrir e sempre que volta do segundo plano;
  depois de 5 tentativas erradas a tela espera 30 s, e cada erro novo **dobra a
  espera** (até 30 min) — a contagem fica no banco, então fechar ou reiniciar o
  app não foge da trava. O conteúdo do app fica desmontado atrás da tela de
  bloqueio — nada aparece na prévia de "app recentes"
  (`lib/screens/lock_screen.dart`, `lib/services/seguranca.dart`).
- **Perfil e tela inicial:** nome, avatar (emoticon ou foto com recorte) e
  cor de fundo escolhidos no primeiro acesso
  (`lib/screens/profile_setup_screen.dart`); a tela inicial
  (`lib/screens/landing_screen.dart`) mostra avatar + nome e os botões
- **Idioma do aparelho:** o app abre em **pt-BR** ou **en-US** conforme o
  idioma do sistema — inglês (qualquer `en_*`) abre em en-US, todo o resto
  cai em pt-BR. Não há troca manual dentro do app. Todas as frases estão em
  `lib/l10n/` (contrato + uma tradução por idioma) e as telas leem o texto de
  `context.strings`; moeda, datas, categorias e formas de pagamento também
  seguem o idioma (`lib/l10n/l10n_format.dart`). Como as duas traduções
  implementam a mesma classe abstrata, uma frase nova que fique só em
  português não compila.
- **Tela de entrada (splash):** ao abrir, o app mostra o gradiente laranja →
  amarelo da manga com 🥭 + nome (`lib/screens/splash_screen.dart`)
  enquanto o perfil e a segurança carregam — o splash nativo (Android
  `launch_background.xml` + iOS `LaunchScreen.storyboard`) usa as mesmas
  cores, então a abertura é contínua do ícone até o conteúdo.
- **Foto do cupom:** limite de 8 MB — imagens maiores (em geral vindas da
  galeria) são recusadas **antes** de decodificar/rodar o OCR, pois decodificar
  aloca muito mais memória e pode travar o app em aparelhos simples. A foto
  aprovada é **copiada para os documentos do app** quando o lançamento é salvo
  (a cópia do `image_picker` fica no cache, que o sistema pode limpar) e aparece
  na tela de edição — toque para ampliar
  (`lib/services/receipt_photo.dart`). Excluir o lançamento apaga a foto; as
  parcelas do mesmo cupom compartilham o arquivo, que só sai quando nenhum
  lançamento o usa.
- **Avatar:** tocar no avatar abre o menu — **emoticon** (atalhos mais usados
  **e** a grade de emojis do app, que já abre direto com todos: busca,
  categorias e recentes, sem depender do teclado do aparelho; guarda o
  primeiro emoticon, funcionando com compostos como 👨‍👩‍👧) ou **foto**
  (galeria/câmera, `lib/widgets/avatar.dart`). A foto tem limite de 5 MB
  (recusada antes de decodificar, como o cupom), é copiada para os documentos
  do app e tem edição simples: arrastar posiciona o recorte e o slider dá
  zoom (posição + zoom salvos no perfil, SQLite v5).
- **Fallback IA (opcional):** `lib/services/ai_fallback.dart` documenta o ponto
  de extensão para Gemini Flash (camada gratuita), enviando só o texto do OCR.

## Requisitos

- Flutter SDK (estável, ≥ 3.47 — testado com 3.47.5 / Dart 3.13)
- Android SDK/Studio (para Android) ou Xcode (para iOS)
- Um dispositivo/emulador Android ou iOS

## Rodando os testes

```bash
flutter pub get
flutter analyze   # deve terminar com "No issues found!"
flutter test      # 210 testes (parser do cupom + parcelas + categorizador + log de falhas + bloqueio/PIN + UI)
```

O CI (`.github/workflows/ci.yml`) roda exatamente esses dois comandos a cada
push/PR na `main`, com o Flutter fixado na versão testada (3.47.5).

## Rodando o app

```bash
flutter devices            # confira o aparelho/emulador conectado
flutter run                # debug no dispositivo padrão
flutter run -d <device_id> # escolher dispositivo específico
```

Dentro do app, botão **+** → "Foto do cupom fiscal" (câmera/galeria) ou
"Lançamento manual". Aba **Relatórios** mostra gráfico de barras despesas
x receitas do período, total do período, gráfico por categoria e por forma
de pagamento (mês / 30 dias / ano / intervalo custom).

## Backup, privacidade e onde ficam os dados

- **No aparelho:** tudo vive dentro do sandbox do app — o banco `mango.db`
  (SQLite via sqflite, em `databases/`) e a foto do avatar escolhida no perfil
  (uma cópia em `app_flutter/`, veja `lib/widgets/avatar.dart`). Nada é enviado
  para servidor nenhum.
- **Backup automático do Android:** os dados do app **não** entram no backup da
  conta Google. As regras em `android/app/src/main/res/xml/backup_rules.xml`
  (Android 11 e anteriores) e `android/app/src/main/res/xml/data_extraction_rules.xml`
  (Android 12+) excluem os dados privados do `cloud-backup` — o banco guarda o
  **texto bruto de cada cupom** (coluna `raw`), que pode conter CPF impresso na
  nota. A **transferência direta entre aparelhos** (cabo / configuração inicial)
  continua funcionando, porque não passa pela conta Google.
- **Backup oficial: o CSV.** Menu → *Exportar em CSV* grava
  `mango_backup_DDMMAAAAHHMMSS.csv` com o perfil (nome/avatar/cor/tema) e os
  lançamentos (`tipo;valor;data_hora;categoria;forma;descricao;estabelecimento;origem`)
  e abre a folha de compartilhamento do sistema. Para restaurar: menu →
  *Importar em CSV* (soma aos lançamentos, sem apagar nada) ou *Restaurar
  backup* no primeiro acesso.
- **O CSV não tem senha.** É texto puro, feito para abrir direto no
  Excel/LibreOffice, e o app avisa antes de exportar (o mesmo aviso fica
  gravado no topo do arquivo, em uma linha `# AVISO;`). Guarde-o em local
  seguro: ele contém todo o seu histórico. Não entram no CSV a foto do avatar,
  o caminho da foto do cupom nem o texto bruto do OCR (`raw`), que só existem
  no banco local.
- **Registro de falhas local.** Quando algo quebra, o detalhe (erro, pilha e
  hora) é gravado em `falhas.jsonl` na área privada do app. Nunca sai de lá
  sozinho: menu → *Diagnóstico* lista as falhas e só compartilha quando você
  toca em *Compartilhar* e escolhe o destino na folha do sistema. O registro
  **não** entra no CSV, é limitado a 200 KB (falhas antigas saem) e falhas
  repetidas em sequência viram uma linha só com `×N`.
- **Bloqueio do app (PIN/biometria).** A tabela `seguranca` guarda só o hash do
  PIN (PBKDF2 + sal aleatório) e a preferência de biometria, e **não entra no
  CSV nem no backup do sistema**: restaurado em outro aparelho, o app abre sem
  tranca. Quem protege os dados é a tela de bloqueio do próprio app — o banco
  `mango.db` em si continua sem criptografia, contando com o sandbox do Android.
- **Por que não criptografar o CSV?** O app não tem servidor nem recuperação de
  senha: uma senha esquecida significaria backup perdido para sempre, e um
  arquivo cifrado deixaria de abrir em planilha. A proteção em repouso fica para
  o lado do banco (criptografia/bloqueio do app), não do arquivo exportado.

## Gerando o APK de release

```bash
flutter build apk --release
# APK em build/app/outputs/flutter-apk/app-release.apk
# Instalar no aparelho (sempre no usuário principal — veja abaixo):
tool/install_release.sh
```

> **Importante (OCR no release):** o APK de release passa por minificação/R8.
> O ML Kit descobre seus componentes por reflexão, e o R8 full mode (padrão a
> partir do AGP 9, usado neste projeto) remove o construtor sem argumentos dos
> registradores. Isso faz `TextRecognition.getClient()` quebrar no release com
> `Attempt to invoke virtual method 'java.lang.Class java.lang.Object.getClass()'
> on a null object reference`. As regras de keep necessárias estão em
> **`android/app/proguard-rules.pro`** — não remova esse arquivo. Mais detalhes
> e como validar em [Solução de problemas](#solução-de-problemas).

### Instalando no aparelho (sem cair no "Segundo espaço")

`adb install` (e o `flutter run`, que usa o mesmo caminho) instala para o
usuário **ativo** no aparelho. Se na hora o Xiaomi estiver no *Segundo espaço*
(usuário 10 — um usuário Android separado, como o *espaço privado* do Android
15+, que é o usuário 11), o app vai **só** para lá: fica invisível no espaço
principal e, depois, um `adb install` normal falha com
`INSTALL_FAILED_UPDATE_INCOMPATIBLE` se a chave for outra. Para não depender do
estado da tela, fixe o usuário principal:

```bash
tool/install_release.sh            # instala em --user 0 e confere onde caiu
# ou na mão (o `pm install` é o caminho garantido; `adb install --user 0 <apk>`
# também funciona em platform-tools recentes, apesar de não constar no `adb help`):
adb push build/app/outputs/flutter-apk/app-release.apk /data/local/tmp/
adb shell pm install --user 0 -r /data/local/tmp/mango-release.apk
adb shell pm list packages --user 0  | grep mango   # deve aparecer
adb shell pm list packages --user 10 | grep mango   # não deve aparecer nada
```

`tool/install_release.sh` avisa se o aparelho estiver em outro usuário e mostra o
comando para limpar uma cópia que tenha ido para o Segundo espaço
(`adb shell pm uninstall --user 10 br.com.mango.mango`), sem tocar na do espaço
principal. Para instalar de propósito lá, troque o alvo:
`adb shell pm install --user 10 -r <apk>`.

### Assinatura do APK (chave própria)

O release **não** usa a chave de debug: ela é pública (vem no SDK do Android e
é a mesma em qualquer máquina), então um APK assinado com ela pode ser
"atualizado" por qualquer pessoa que saiba o nome do pacote
(`br.com.mango.mango`). A chave de verdade fica fora do Git, em
`android/key.properties` + keystore `.jks` (ambos no `android/.gitignore`).
Sem essa chave o build de release **para** com instruções, em vez de gerar um
APK mal assinado — debug e profile seguem funcionando normalmente.

Criar o keystore (uma vez; **guarde o `.jks` e as senhas**: sem eles não é
possível assinar atualizações do mesmo app):

```bash
keytool -genkeypair -v -keystore ~/mango-release.jks -alias mango \
  -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000
```

Criar `android/key.properties` apontando para ele (`storeFile` aceita caminho
absoluto ou relativo à pasta `android/`):

```properties
storeFile=/home/<usuario>/mango-release.jks
storePassword=<senha do keystore>
keyAlias=mango
keyPassword=<senha do keystore>
```

> **PKCS12 tem uma única senha** (é o formato padrão do `keytool` moderno,
> mesmo com a extensão `.jks`, que aqui é só o nome do arquivo): `keyPassword`
> **precisa** ser igual a `storePassword`. Um valor diferente faz o build
> falhar no fim do empacotamento com `Get Key failed: Given final block not
> properly padded` (veja [Solução de problemas](#solução-de-problemas)).
> Quer senhas realmente distintas? Gere o keystore com `-storetype JKS`.
> O `android/app/build.gradle.kts` aceita os dois formatos e, se o keystore for
> PKCS12 com `keyPassword` divergente, usa o `storePassword` para assinar
> (avisando no build) em vez de falhar.

Depois é só `flutter build apk --release` (ou `flutter build appbundle
--release`). Conferir com qual chave o APK saiu — deve mostrar o seu `CN=`,
nunca `CN=Android Debug` (o `apksigner` vem no `build-tools` do SDK do
Android; com `minSdk` ≥ 24 o AGP assina com o esquema v2/v3, que o
`keytool -printcert -jarfile` não lê):

```bash
$ANDROID_HOME/build-tools/36.0.0/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

### Publicando uma versão

1. Suba a versão no `pubspec.yaml` — `version: 1.0.1+2`: o número depois do `+`
   é o *build number* do Android e **precisa** aumentar a cada release (o
   Android recusa instalar um APK com o mesmo `versionCode`).
2. Registre a mudança no [`CHANGELOG.md`](CHANGELOG.md).
3. `flutter analyze` (deve terminar com "No issues found!"), `flutter test` e
   `flutter build apk --release`.
4. Marque e publique:

   ```bash
   git tag -a v1.0.1 -m "Mango 1.0.1"
   git push origin main
   git push origin v1.0.1
   ```

5. A tag dispara o workflow **Release** (`.github/workflows/release.yml`),
   que repete `analyze` + `testes`, confere se a tag bate com o
   `pubspec.yaml` e com a seção do `CHANGELOG`, monta o APK assinado com a
   chave própria (via **Secrets**, veja a próxima seção), valida o
   certificado e a ausência de permissão de rede e publica a Release `v…`
   com o anexo `mango-<versão>.apk` (notas = seção do CHANGELOG +
   instalação + SHA-256). Sem os Secrets o passo falha cedo, com
   instrução. Ensaio sem taggear: `gh workflow run release.yml` (builda e
   sobe o APK como artefato, sem criar Release).

6. **Alternativa manual** (sem CI), com o APK local:

   ```bash
   cp build/app/outputs/flutter-apk/app-release.apk /tmp/mango-1.0.1.apk
   sha256sum /tmp/mango-1.0.1.apk   # cole o hash no corpo das notas
   gh release create v1.0.1 /tmp/mango-1.0.1.apk \
     --title "Mango 1.0.1" --notes-file /tmp/notas.md --latest
   ```

   O corpo das notas é a seção correspondente do
   [`CHANGELOG.md`](CHANGELOG.md), com instruções de instalação e o SHA-256
   do arquivo (confira depois com `gh release view v<versão>`).

A janela *Sobre o Mango* mostra a versão lida do **próprio app instalado**
(`lib/services/app_info.dart`), então ela nunca fica defasada em relação ao
APK.

### Segredos do GitHub Actions (build + release automático)

O workflow **Release** precisa de 4 secrets — são os mesmos dados do
`android/key.properties` local; o keystore em si **nunca** entra no Git:

| Secret | Conteúdo |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | o keystore `.jks` codificado em base64 (uma linha só) |
| `ANDROID_KEYSTORE_PASSWORD` | a senha do keystore (num PKCS12, a única) |
| `ANDROID_KEY_ALIAS` | `mango` |
| `ANDROID_KEY_PASSWORD` | igual à senha do keystore (PKCS12 tem senha única) |

Com o `gh` autenticado (troque as senhas pelos valores reais):

```bash
# 1. codifica o keystore no seu terminal (ele sai daqui só em base64)
base64 -w0 ~/mango-release.jks > /tmp/keystore.b64             # Linux
base64 -i ~/mango-release.jks | tr -d '\n' > /tmp/keystore.b64  # macOS

# 2. cria os 4 secrets no repositório
gh secret set ANDROID_KEYSTORE_BASE64 < /tmp/keystore.b64
gh secret set ANDROID_KEYSTORE_PASSWORD --body '<senha-do-keystore>'
gh secret set ANDROID_KEY_ALIAS --body 'mango'
gh secret set ANDROID_KEY_PASSWORD --body '<mesma-senha-do-keystore>'

# 3. confere e limpa
gh secret list && rm /tmp/keystore.b64
```

Sem `gh`: no repositório GitHub, **Settings → Secrets and variables →
Actions → New repository secret**, um por linha da tabela.

Segurança: os secrets só ficam visíveis para workflows deste repositório —
nunca para pull requests de fork — e aparecem mascarados nos logs. Quem tem
permissão de *write* poderia lê-los alterando um workflow, então mantenha a
lista de colaboradores curta. **Guarde o `.jks` e as senhas fora do GitHub
também**: sem eles não há como assinar atualizações do app (e o Android
recusa um APK assinado com chave diferente da instalada).

## Licença e privacidade

- Código sob a licença **MIT** — veja [`LICENSE`](LICENSE).
- **Política de privacidade:** [`PRIVACIDADE.md`](PRIVACIDADE.md). O Play
  Console exige uma URL pública: a forma mais simples é publicar esse arquivo
  como página (GitHub Pages deste repositório) e colar a URL no cadastro do app.
- Não há coleta de dados, analytics ou anúncios — o APK de release não tem nem
  permissão de rede, o que responde "nenhum dado coletado" no formulário de
  *Segurança dos dados* do Play.

## Solução de problemas

### "Falha ao ler o cupom ... getClass() ... on a null object reference"

Acontece **só no APK de release** (em debug o OCR funciona). É R8 removendo o
construtor dos registradores do ML Kit, que são instanciados via reflexão.

Correção (já aplicada em `android/app/proguard-rules.pro`):

```proguard
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google.mlkit.** { *; }
```

Como conferir que o release saiu correto — nenhuma linha de saída e o DEX deve
conter o construtor do registrador:

```bash
grep -E '^(TextRegistrar|CommonComponentRegistrar|VisionCommonRegistrar):' \
  build/app/outputs/mapping/release/usage.txt
# (nenhuma saída = construtores preservados)
```

Se você gerou APKs por ABI (`--split-per-abi`) antes da correção, apague-os:
`flutter build apk --release` reescreve apenas `app-release.apk` e os splits
antigos (quebrados) continuam no disco.

Para iOS: `flutter build ios --release` (requer Mac + Xcode; ML Kit pede
target iOS ≥ 15.5 e excluir arquitetura armv7 em Runner > Build Settings).

### "Get Key failed: Given final block not properly padded" ao assinar o release

`Execution failed for task ':app:packageRelease'` terminando com
`KeytoolException: Failed to read key mango from store ".../mango-release.jks":
Get Key failed: Given final block not properly padded` significa que a chave
existe, mas não abre com a senha informada. A causa quase sempre é o
`keyPassword` de `android/key.properties` diferente do `storePassword`: o
keystore é **PKCS12** (padrão do `keytool` desde o Java 9, mesmo com extensão
`.jks`) e PKCS12 guarda **uma única senha**.

Correção (as senhas não aparecem na saída do comando):

```bash
cd android
SP=$(grep '^storePassword=' key.properties | cut -d= -f2-)
sed -i "s/^keyPassword=.*/keyPassword=$SP/" key.properties   # PKCS12: senha única
keytool -list -keystore /home/<usuario>/mango-release.jks -storepass "$SP"
# deve listar a entrada 'mango' e "Tipo de área de armazenamento de chaves: PKCS12"
```

Como o build já trata esse caso (usando o `storePassword` como senha da chave
quando o keystore é PKCS12), o sintoma agora aparece como **aviso** no build,
não como falha: se o aviso persistir, iguale o `keyPassword` para o build sair
limpo. Se o próprio `keytool -list` falhar, o problema é o `storePassword` (e
não há como recuperá-lo): gere um keystore novo e lembre que um APK com outra
assinatura **não** atualiza o app instalado — precisa desinstalar antes.

### "INSTALL_FAILED_UPDATE_INCOMPATIBLE: ... signatures do not match" ao instalar

```
adb: failed to install .../app-release.apk: Failure
[INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package br.com.mango.mango
signatures do not match newer version; ignoring!]
```

O app já instalado foi assinado com **outra chave** — em geral o release antigo,
assinado com a chave de **debug** pública (`CN=Android Debug`), de antes da
assinatura própria. O Android **não** permite trocar a chave de um app
instalado, e nenhuma flag do `adb install` contorna isso (`-r`, `-d`,
`--bypass-low-target-sdk-block` não ajudam). Confira a chave do que está no
aparelho:

```bash
adb shell pm path br.com.mango.mango                       # caminho do base.apk
adb pull /data/app/.../base.apk /tmp/instalado.apk
$ANDROID_HOME/build-tools/36.0.0/apksigner verify --print-certs /tmp/instalado.apk
# CN=Android Debug -> era o release antigo, sem chave própria
```

Migrar (uma única vez; **exporte antes** se já tiver lançamentos — menu →
*Exportar em CSV* — e restaure no primeiro acesso com *Restaurar backup*):

```bash
adb uninstall br.com.mango.mango   # remove de todos os usuários/espaços
# `adb uninstall -k br.com.mango.mango` tenta manter os dados; não é garantido
tool/install_release.sh            # instala só no usuário principal
```

Depois disso, **toda** build de release precisa do mesmo keystore
(`~/mango-release.jks`): outra chave exige desinstalar de novo. Vale também para
o `flutter run`, que usa a chave de debug — com o release instalado no mesmo
espaço, use `flutter run --release` ou desinstale antes. Para o app não acabar
no *Segundo espaço* do aparelho, veja
[Instalando no aparelho](#instalando-no-aparelho-sem-cair-no-segundo-espaço).

### "Esqueci o PIN do app"

O Mango é local: não existe conta, e-mail nem servidor — não há como recuperar
um PIN esquecido. Errar tem custo: depois de 5 tentativas a tela de bloqueio
espera 30 s, e cada erro novo dobra a espera (até 30 min); durante a espera o
teclado e a biometria ficam fora de alcance, e a contagem não se perde ao fechar
o app. Caminhos possíveis:

- **Com biometria ligada:** entre pela digital/rosto (o botão aparece na tela de
  bloqueio) e troque o PIN em *menu → Segurança → Alterar PIN*.
- **Sem biometria:** a saída é desinstalar o app, o que apaga o banco (incluindo
  as fotos dos cupons). Se você tem um **CSV exportado**, instale de novo, crie o
  perfil e use *menu → Importar em CSV* — ou *Restaurar backup* no primeiro
  acesso — para trazer os lançamentos de volta.
- O `mango.db` fica na área privada do app: sem um aparelho destravado (e root)
  não há como editar a tabela `seguranca` por fora — que é exatamente a ideia.

Por isso o CSV continua sendo o backup oficial: ele não é afetado pelo bloqueio.

## Estrutura

```
lib/
├── main.dart                  # app + LockGate (bloqueio) + ProfileGate (abertura)
├── models/models.dart         # Expense, Category, PaymentMethod, ReceiptDraft, UserProfile, SegurancaConfig
├── db/db.dart                 # SQLite (sqflite) + perfil + bloqueio + agregações/períodos
├── state/providers.dart       # Riverpod: gastos, perfil, sumários, segurança e bloqueio
├── theme/app_theme.dart       # tema do app a partir da cor de fundo do perfil
├── l10n/
│   ├── app_strings.dart        # contrato de frases (uma por idioma do app)
│   ├── app_strings_pt.dart    # pt-BR
│   ├── app_strings_en.dart    # en-US
│   ├── app_locale.dart        # idioma do sistema → locale do app; `context.strings`
│   └── l10n_format.dart       # moeda e datas pelo locale (BRL/USD)
├── services/
│   ├── ocr_service.dart       # ML Kit Text Recognition (on-device)
│   ├── receipt_parser.dart    # parser heurístico de cupom fiscal BR
│   ├── receipt_photo.dart     # cópia durável da foto do cupom + limpeza
│   ├── categorizer.dart       # regras por palavra-chave + memória
│   ├── seguranca.dart         # PIN (PBKDF2-HMAC-SHA256) + biometria + trava por tentativas
│   ├── crash_log.dart         # log local de falhas (falhas.jsonl) + fila
│   └── ai_fallback.dart       # extensão opcional p/ IA (desligada por padrão)
├── screens/
│   ├── root_nav.dart          # abas Gastos / Relatórios (deslize)
│   ├── splash_screen.dart     # tela de entrada: gradiente manga + nome
│   ├── landing_screen.dart    # tela inicial: avatar + nome + Meus gastos/Menu
│   ├── lock_screen.dart       # bloqueio: teclado do PIN + botão de biometria
│   ├── seguranca_screen.dart  # menu → Segurança: criar/alterar/desativar o bloqueio
│   ├── profile_setup_screen.dart  # cadastro/edição: nome, avatar e cor de fundo
│   ├── home_screen.dart       # lista de gastos + resumo
│   ├── capture_screen.dart    # foto do cupom + OCR
│   ├── expense_form_screen.dart   # confirmação/edição do gasto
│   ├── reports_screen.dart    # relatórios por período
│   └── diagnostico_screen.dart # falhas locais: listar / compartilhar / limpar
└── widgets/common.dart        # formatação BRL, ícones/cores, FAB, tiles

test/                          # parser, parcelas, backup CSV, UI e auditorias (audit_probe*)
tool/                          # generate_icon.py + install_release.sh (instala no usuário 0)
.github/workflows/ci.yml       # analyze + testes a cada push/PR (Flutter 3.47.5)
.github/workflows/release.yml  # tag v*: build assinado + Release com o APK
```

## Permissões

- **Android:** nenhuma permissão própria — câmera e galeria são usadas pelo
  seletor do próprio sistema. As permissões `USE_BIOMETRIC` e `USE_FINGERPRINT`
  (esta última para Android 8 e anteriores) vêm do plugin `local_auth`, apenas
  para o diálogo de biometria do sistema quando o bloqueio do app está ligado.
  As permissões `INTERNET` e `ACCESS_NETWORK_STATE`
  que bibliotecas arrastam (telemetria do ML Kit) são **removidas** no
  manifesto mesclado (`android/app/src/main/AndroidManifest.xml`), então o APK
  de **release não tem permissão de rede**. No build de **debug** a `INTERNET`
  continua declarada em `android/app/src/debug/AndroidManifest.xml`, exigida
  pelo Flutter para hot reload/depuração.
- **iOS:** `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` e
  `NSFaceIDUsageDescription` (exigido pelo `local_auth` para o Face ID do
  bloqueio por biometria) já configurados em `ios/Runner/Info.plist`. O
  bloqueio por biometria no iOS ainda **não** foi testado (veja as *issues* do
  repositório).
