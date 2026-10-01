import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_locale.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';

/// Avatares (emoticons) oferecidos no cadastro do perfil.
const List<String> kProfileAvatars = [
  '🙂',
  '😀',
  '😎',
  '🤓',
  '🥳',
  '🤩',
  '🐱',
  '🐶',
  '🦊',
  '🐼',
  '🦁',
  '🐸',
  '🌟',
  '🍀',
];

/// Cores de fundo da tela inicial.
///
/// Mantido para compatibilidade com os testes existentes: a paleta ativa do
/// perfil agora vem de [kCoresTemaClaro]/[kCoresTemaEscuro] (ver
/// `lib/theme/app_theme.dart`).
const List<Color> kProfileColors = kCoresTemaClaro;

/// Cores escuras de fundo, com os mesmos matizes da paleta clara, oferecidas
/// quando o usuário escolhe o tema escuro.
const List<Color> kProfileColorsEscuro = kCoresTemaEscuro;

/// Cadastro do usuário no primeiro acesso (nome, avatar e cor de fundo) e
/// edição do perfil depois (`existing` != null).
///
/// Ao salvar, o [profileProvider] passa a ter um perfil e a tela inicial do
/// app (avatar + nome + botões) é exibida.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  /// Perfil já existente (edição). `null` = primeiro acesso.
  final UserProfile? existing;

  const ProfileSetupScreen({super.key, this.existing});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  late final TextEditingController _nome;
  late String _avatar;
  late Color _cor;
  late bool _temaClaro;
  /// Caminho da foto do avatar (cópia nos documentos do app). `null` = emoticon.
  String? _fotoPath;
  /// Posição do recorte (-1..1) e zoom (1..3) da foto.
  late double _fotoAlignX;
  late double _fotoAlignY;
  late double _fotoZoom;
  /// Foto nova escolhida nesta sessão mas ainda não salva: se o usuário sair
  /// sem salvar, o arquivo órfão é apagado.
  String? _fotoPendente;

  /// Valores ao abrir a tela: base para saber se houve alteração (só na
  /// edição vale pedir confirmação ao sair).
  late String _nomeInicial;
  late String _avatarInicial;
  late Color _corInicial;
  late bool _temaClaroInicial;
  String? _fotoPathInicial;
  late double _fotoAlignXInicial;
  late double _fotoAlignYInicial;
  late double _fotoZoomInicial;

  bool _saving = false;
  bool _escolhendoFoto = false;

  bool get _isEdit => widget.existing != null;

  bool get _temAlteracoes =>
      _nome.text.trim() != _nomeInicial ||
      _avatar != _avatarInicial ||
      _fotoPath != _fotoPathInicial ||
      _fotoAlignX != _fotoAlignXInicial ||
      _fotoAlignY != _fotoAlignYInicial ||
      _fotoZoom != _fotoZoomInicial ||
      _cor != _corInicial ||
      _temaClaro != _temaClaroInicial;

  /// Na edição, sair com alterações não salvas pede confirmação.
  bool get _bloqueiaSaida => _isEdit && _temAlteracoes;

  /// Paleta de cores oferecida: alterna com o tema escolhido.
  List<Color> get _paletaCores =>
      _temaClaro ? kCoresTemaClaro : kCoresTemaEscuro;

  @override
  void initState() {
    super.initState();
    final perfil = widget.existing;
    _nome = TextEditingController(text: perfil?.nome ?? '');
    _avatar = perfil?.avatar ?? kProfileAvatars.first;
    _fotoPath = perfil?.avatarImagePath;
    _fotoAlignX = (perfil?.avatarAlignX ?? 0).clamp(-1.0, 1.0);
    _fotoAlignY = (perfil?.avatarAlignY ?? 0).clamp(-1.0, 1.0);
    _fotoZoom = (perfil?.avatarZoom ?? 1).clamp(1.0, 3.0);
    _temaClaro = perfil?.temaClaro ?? false;
    _cor = Color(
      perfil?.corFundo ??
          (_temaClaro
              ? UserProfile.corFundoPadrao
              : UserProfile.corFundoEscuroPadrao),
    );
    // Garante que a cor inicial pertence à paleta do tema atual.
    final paleta = _temaClaro ? kCoresTemaClaro : kCoresTemaEscuro;
    if (!paleta.any((c) => c.toARGB32() == _cor.toARGB32())) {
      final origem = _temaClaro ? kCoresTemaEscuro : kCoresTemaClaro;
      _cor = corNaPaleta(_cor, origem, paleta);
    }
    _nomeInicial = _nome.text.trim();
    _avatarInicial = _avatar;
    _corInicial = _cor;
    _temaClaroInicial = _temaClaro;
    _fotoPathInicial = _fotoPath;
    _fotoAlignXInicial = _fotoAlignX;
    _fotoAlignYInicial = _fotoAlignY;
    _fotoZoomInicial = _fotoZoom;
    // Digitar muda o perfil: mantém o PopScope (canPop) em sincronia.
    if (_isEdit) _nome.addListener(_onNomeChanged);
  }

  void _onNomeChanged() {
    if (mounted) setState(() {}); // atualiza o PopScope (canPop) ao digitar
  }

  @override
  void dispose() {
    _nome.removeListener(_onNomeChanged);
    _nome.dispose();
    _scrollController.dispose();
    // Saiu sem salvar: apaga a cópia nova para não deixar foto órfã.
    if (_fotoPendente != null && _fotoPendente != _fotoPathInicial) {
      apagarArquivoAvatar(_fotoPendente);
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Frases capturadas antes dos awaits: o contexto pode sair da arvore
    // enquanto a imagem do avatar e gravada.
    final perfilAtualizado = context.strings.perfilAtualizado;
    setState(() => _saving = true);
    await ref
        .read(profileProvider.notifier)
        .save(
          UserProfile(
            nome: _nome.text.trim(),
            avatar: _avatar,
            corFundo: _cor.toARGB32(),
            temaClaro: _temaClaro,
            avatarImagePath: _fotoPath,
            avatarAlignX: _fotoAlignX,
            avatarAlignY: _fotoAlignY,
            avatarZoom: _fotoZoom,
          ),
        );
    if (!mounted) return;
    // A foto pendente virou definitiva: não apagar no dispose.
    final fotoAntiga = _fotoPathInicial;
    setState(() {
      _saving = false;
      _fotoPendente = null;
      // O que está na tela agora é o perfil salvo: nada mais pendente.
      _nomeInicial = _nome.text.trim();
      _avatarInicial = _avatar;
      _corInicial = _cor;
      _temaClaroInicial = _temaClaro;
      _fotoPathInicial = _fotoPath;
      _fotoAlignXInicial = _fotoAlignX;
      _fotoAlignYInicial = _fotoAlignY;
      _fotoZoomInicial = _fotoZoom;
    });
    // Trocou/removeu a foto: apaga o arquivo antigo (best-effort).
    if (fotoAntiga != null && fotoAntiga != _fotoPath) {
      await apagarArquivoAvatar(fotoAntiga);
    }

    // No primeiro acesso esta tela é a raiz do app (nada a fechar). Na edição
    // ela foi empilhada pelo Menu: volta e avisa o usuário.
    // (messenger/navigator capturados antes dos awaits acima.)
    if (_isEdit) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(perfilAtualizado)),
      );
    }
  }

  /// Sair da edição com alterações pendentes: só fecha se o usuário confirmar
  /// que quer descartá-las.
  Future<void> _confirmarSaida() async {
    final navigator = Navigator.of(context);
    final descartar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.strings.descartarAlteracoes),
        content: Text(context.strings.descartarAlteracoesMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.strings.continuarEditando),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.strings.descartarSair),
          ),
        ],
      ),
    );
    if ((descartar ?? false) && mounted) navigator.pop();
  }

  /// Toque no avatar: abre o menu (emoticon da grade interna ou foto).
  Future<void> _menuAvatar() async {
    final opcao = await showModalBottomSheet<_OpcaoAvatar>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.emoji_emotions_outlined),
              title: Text(context.strings.escolherEmoji),
              subtitle: Text(context.strings.gradeEmojis),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_OpcaoAvatar.emoji),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(context.strings.fotoGaleria),
              subtitle: Text(context.strings.imagemAte5MB),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_OpcaoAvatar.galeria),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(context.strings.tirarFoto),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_OpcaoAvatar.camera),
            ),
            if (_fotoPath != null) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.crop_outlined),
                title: Text(context.strings.ajustarRecorte),
                subtitle: Text(context.strings.arrastarRecorte),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_OpcaoAvatar.ajustar),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Colors.redAccent),
                title: Text(context.strings.removerFoto),
                subtitle: Text(context.strings.voltarEmoticon),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_OpcaoAvatar.remover),
              ),
            ],
          ],
        ),
      ),
    );
    if (opcao == null || !mounted) return;
    switch (opcao) {
      case _OpcaoAvatar.emoji:
        await _escolherEmojiDaGrade();
      case _OpcaoAvatar.galeria:
        await _escolherFoto(ImageSource.gallery);
      case _OpcaoAvatar.camera:
        await _escolherFoto(ImageSource.camera);
      case _OpcaoAvatar.ajustar:
        await _ajustarFoto();
      case _OpcaoAvatar.remover:
        _removerFoto();
    }
  }

  /// Abre o seletor de emoticons (teclado de emojis do app, que já abre direto
  /// na grade de emojis com busca, categorias e recentes — acesso a todos os
  /// emojis, sem depender do teclado do aparelho).
  Future<void> _escolherEmojiDaGrade() async {
    final escolhido = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _EmojiSheet(),
    );
    if (escolhido == null || escolhido.isEmpty || !mounted) return;
    // Guarda só o primeiro emoticon (alguns têm vários code points, como
    // 👨‍👩‍👧, 🇧🇷 ou 🧑🏽).
    _selecionarAvatar(escolhido.characters.first);
  }

  /// Escolhe a foto (galeria/câmera), valida o tamanho e abre o ajuste
  /// (posicionamento + recorte).
  Future<void> _escolherFoto(ImageSource origem) async {
    if (_escolhendoFoto) return;
    setState(() => _escolhendoFoto = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: origem,
        // Reduz na origem: avatar circular pequeno não precisa de 12 MP.
        maxWidth: kAvatarMaxWidth,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      // Recusa antes de decodificar (mesma proteção do cupom fiscal).
      final tamanho = await File(picked.path).length();
      final erro = validarTamanhoAvatar(tamanho, context.strings);
      if (!mounted) return;
      if (erro != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(erro)));
        return;
      }
      final copia = await salvarCopiaAvatar(picked);
      if (!mounted) return;
      final anterior = _fotoPath;
      setState(() {
        _fotoPath = copia;
        _fotoPendente = copia;
        _fotoAlignX = 0;
        _fotoAlignY = 0;
        _fotoZoom = 1;
      });
      // Foto antiga desta sessão vira órfã: apaga (best-effort).
      if (anterior != null &&
          anterior != _fotoPathInicial &&
          anterior != copia) {
        await apagarArquivoAvatar(anterior);
      }
      await _ajustarFoto();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.imagemInvalida('$e'))),
      );
    } finally {
      if (mounted) setState(() => _escolhendoFoto = false);
    }
  }

  /// Editor simples da foto: arrastar posiciona, o slider dá zoom — a prévia
  /// circular mostra exatamente o recorte que será salvo.
  Future<void> _ajustarFoto() async {
    final foto = _fotoPath;
    if (foto == null || !mounted) return;
    final resultado = await showModalBottomSheet<_AjusteFoto>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AjusteFotoSheet(
        imagePath: foto,
        alignX: _fotoAlignX,
        alignY: _fotoAlignY,
        zoom: _fotoZoom,
        avatarFallback: _avatar,
      ),
    );
    if (resultado == null || !mounted) return;
    setState(() {
      _fotoAlignX = resultado.alignX;
      _fotoAlignY = resultado.alignY;
      _fotoZoom = resultado.zoom;
    });
  }

  void _removerFoto() {
    final atual = _fotoPath;
    setState(() => _fotoPath = null);
    // Apaga já a cópia nova desta sessão; a salva só sai do disco ao Salvar.
    if (atual != null &&
        atual != _fotoPathInicial &&
        atual == _fotoPendente) {
      _fotoPendente = null;
      apagarArquivoAvatar(atual);
    }
  }

  /// Escolha de emoticon (atalhos ou grade): além de trocar o avatar, remove
  /// a foto anterior da prévia para o emoticon voltar a aparecer.
  ///
  /// A cópia nova desta sessão vira órfã e é apagada na hora; a foto já salva
  /// só sai do disco ao Salvar (ver [_salvar]).
  void _selecionarAvatar(String avatar) {
    final atual = _fotoPath;
    setState(() {
      _avatar = avatar;
      _fotoPath = null;
    });
    if (atual != null &&
        atual != _fotoPathInicial &&
        atual == _fotoPendente) {
      _fotoPendente = null;
      apagarArquivoAvatar(atual);
    }
  }

  /// Perfil da prévia (fundo + avatar), incluindo foto e recorte atuais.
  UserProfile _perfilPrevia() => UserProfile(
        nome: _nome.text.trim(),
        avatar: _avatar,
        corFundo: _cor.toARGB32(),
        temaClaro: _temaClaro,
        avatarImagePath: _fotoPath,
        avatarAlignX: _fotoAlignX,
        avatarAlignY: _fotoAlignY,
        avatarZoom: _fotoZoom,
      );

  @override
  Widget build(BuildContext context) {
    // Prévia do fundo: cor escolhida no tema claro; cinza escuro fixo no
    // tema escuro (igual ao resto do app — ver [kFundoTemaEscuro]).
    final fundoPrevia = _temaClaro ? _cor : kFundoTemaEscuro;
    final onCor = onBackgroundColor(fundoPrevia);
    // Prévia em tempo real: deriva um Theme da seleção atual (cor + modo) e
    // envolve a tela, para que os highlights (seletor de tema,
    // seleção de avatar/cor, botões e barra de rolagem) usem a cor do tema
    // escolhido antes de salvar — igual ao restante do app via buildAppTheme.
    final previaPerfil = _perfilPrevia();
    final previaTheme = buildAppTheme(
      corFundoDoPerfil(previaPerfil),
      temaClaro: temaClaroDoPerfil(previaPerfil),
      corAcento: corAcentoDoPerfil(previaPerfil),
    );

    return PopScope<Object?>(
      // Na edição, sair com alterações não salvas pede confirmação; sem
      // alterações (ou no primeiro acesso) a saída é direta.
      canPop: !_bloqueiaSaida,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _confirmarSaida();
      },
      child: Theme(
        data: previaTheme,
        child: Scaffold(
          backgroundColor: fundoPrevia,
          appBar: _isEdit
              ? AppBar(
                  title: Text(context.strings.editarPerfil),
                  backgroundColor: Colors.transparent,
                  foregroundColor: onCor,
                )
              : null,
          body: SafeArea(
            child: Center(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _cabecalho(onCor),
                          _previewAvatar(),
                          _campoNome(onCor),
                          const SizedBox(height: 16),
                          _escolhaAvatar(onCor),
                          const SizedBox(height: 16),
                          _escolhaTema(onCor),
                          const SizedBox(height: 16),
                          _escolhaCor(onCor),
                          const SizedBox(height: 20),
                          _botaoSalvar(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cabecalho(Color onCor) => Column(
    children: [
      Text(
        _isEdit ? context.strings.editarPerfil : context.strings.bemVindo,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: onCor,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _isEdit ? context.strings.ajustePerfil : context.strings.vamosCriarPerfil,
        textAlign: TextAlign.center,
        style: TextStyle(color: onCor.withValues(alpha: 0.7)),
      ),
    ],
  );

  /// Prévia "como os outros vão te ver": caixa com cantos arredondados na cor
  /// do tema escolhido (com gradiente), contendo avatar + nome digitado.
  /// Muda automaticamente ao trocar a cor/tema — igual à imagem de referência.
  Widget _previewAvatar() => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Container(
      key: const ValueKey('avatar-preview-card'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(_cor, Colors.white, 0.06) ?? _cor,
            _cor,
            Color.lerp(_cor, Colors.black, 0.22) ?? _cor,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: context.strings.toqueTrocarAvatar,
            child: InkWell(
              key: const ValueKey('avatar-preview'),
              onTap: _menuAvatar,
              customBorder: const CircleBorder(),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF1C1C1E),
                    ),
                    child: ProfileAvatar(
                      perfil: _perfilPrevia(),
                      radius: 44,
                      fontSize: 48,
                      backgroundColor: const Color(0xFF1C1C1E),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.primary,
                      border: Border.all(
                        color: const Color(0xFF1C1C1E),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      _escolhendoFoto
                          ? Icons.hourglass_top
                          : Icons.photo_camera_outlined,
                      size: 14,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.strings.escolhaAvatar,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: onBackgroundColor(_cor).withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            // \u200B (zero-width) ao final: evita que `find.text(nome)`
            // dos testes conte a prévia junto com o campo de texto —
            // visualmente idêntico ao nome digitado.
            '${_nome.text.trim().isEmpty ? context.strings.seuNome : _nome.text.trim()}\u200B',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: onBackgroundColor(_cor),
            ),
          ),
          // const SizedBox(height: 2),
          // Text(
          //   'é assim que os outros vão te ver',
          //   textAlign: TextAlign.center,
          //   style: TextStyle(
          //     fontSize: 13,
          //     color: onBackgroundColor(_cor).withValues(alpha: 0.7),
          //   ),
          // ),
        ],
      ),
    ),
  );

  Widget _campoNome(Color onCor) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: TextFormField(
      controller: _nome,
      textCapitalization: TextCapitalization.words,
      maxLength: UserProfile.nomeMaxLength,
      // Cor explícita a partir da prévia do fundo (não do Theme do app):
      // ao alternar o tema na edição, o Scaffold mostra a prévia mas o
      // Theme ainda é o do perfil salvo — sem isto o texto herdaria a cor
      // errada (ex.: branco sobre fundo claro, sem contraste).
      style: TextStyle(color: onCor),
      decoration: InputDecoration(
        labelText: context.strings.nomeUsuario,
        labelStyle: TextStyle(color: onCor.withValues(alpha: 0.7)),
        floatingLabelStyle: TextStyle(color: onCor),
        prefixIcon: const Icon(Icons.person_outline),
        prefixIconColor: onCor.withValues(alpha: 0.7),
        suffixIconColor: onCor.withValues(alpha: 0.7),
        counterStyle: TextStyle(color: onCor.withValues(alpha: 0.7)),
        errorStyle: const TextStyle(color: Colors.redAccent),
        filled: true,
        fillColor: onCor.withValues(alpha: 0.05),
        counterText: '',
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: onCor.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: onCor, width: 1.6),
        ),
        errorBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.redAccent, width: 1.6),
        ),
        border: const OutlineInputBorder(),
      ),
      validator: (v) =>
          (v ?? '').trim().isEmpty ? context.strings.informeNome : null,
      onFieldSubmitted: (_) => _salvar(),
    ),
  );

  Widget _escolhaAvatar(Color onCor) => Column(
    children: [
      Text(
        context.strings.avatar,
        style: TextStyle(fontWeight: FontWeight.bold, color: onCor),
      ),
      const SizedBox(height: 12),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final avatar in kProfileAvatars)
            _AvatarChoice(
              avatar: avatar,
              selected: _fotoPath == null && avatar == _avatar,
              onCor: onCor,
              onTap: () => _selecionarAvatar(avatar),
            ),
        ],
      ),
      // Emoticon de fundo: mesmo com foto, ele aparece se a imagem falhar.
      // Os atalhos acima são só os mais usados: aqui abre a grade de emojis
      // do app (categorias + busca + recentes) para escolher qualquer um.
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _escolherEmojiDaGrade,
              icon: const Icon(Icons.emoji_emotions_outlined),
              label: Text(context.strings.outroEmoji),
            ),
            TextButton.icon(
              onPressed: _menuAvatar,
              icon: const Icon(Icons.image_outlined),
              label: Text(
                _fotoPath == null
                    ? context.strings.usarFoto
                    : context.strings.trocarFotoCurto,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  void _trocarTema(bool temaClaro) {
    if (temaClaro == _temaClaro) return;
    setState(() {
      _temaClaro = temaClaro;
      final paleta = _temaClaro ? kCoresTemaClaro : kCoresTemaEscuro;
      final origem = _temaClaro ? kCoresTemaEscuro : kCoresTemaClaro;
      _cor = corNaPaleta(_cor, origem, paleta);
    });
  }

  Widget _escolhaTema(Color _) {
    // Card "Tema": o fundo reage à cor escolhida (tingido com [_cor]),
    // mas o modo (claro/escuro) só muda tocando em Claro/Escuro — escolher
    // uma cor apenas converte o tom dentro do tema atual.
    final isClaro = _temaClaro;
    final cardColor = isClaro
        ? (Color.lerp(_cor, Colors.white, 0.35) ?? _cor)
        : (Color.lerp(_cor, const Color(0xFF101318), 0.30) ?? _cor);
    final cardText = onBackgroundColor(cardColor);
    final cardBorder = isClaro
        ? Colors.black.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.12);
    final trackColor = isClaro
        ? Colors.white.withValues(alpha: 0.65)
        : Colors.black.withValues(alpha: 0.40);
    final trackBorder = isClaro
        ? Colors.black.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.10);

    return Container(
      key: const ValueKey('tema-card'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isClaro ? 0.10 : 0.45),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.strings.tema,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: cardText,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: trackBorder, width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TemaOption(
                    key: const ValueKey('tema-claro'),
                    icon: Icons.wb_sunny_outlined,
                    label: context.strings.claro,
                    selected: isClaro,
                    temaClaro: isClaro,
                    cor: _cor,
                    onTap: () => _trocarTema(true),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _TemaOption(
                    key: const ValueKey('tema-escuro'),
                    icon: Icons.dark_mode_outlined,
                    label: context.strings.escuro,
                    selected: !isClaro,
                    temaClaro: isClaro,
                    cor: _cor,
                    onTap: () => _trocarTema(false),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _escolhaCor(Color onCor) => Column(
    children: [
      Text(
        context.strings.corFundo,
        style: TextStyle(fontWeight: FontWeight.bold, color: onCor),
      ),
      const SizedBox(height: 8),
      // Duas fileiras centralizadas (4 + 4): mantém o mesmo espaçamento do
      // Wrap anterior, mas garante o alinhamento pedido no layout.
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 4 && i < _paletaCores.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            ColorChoice(
              key: ValueKey('cor-$i'),
              color: _paletaCores[i],
              selected: _paletaCores[i] == _cor,
              onCor: onCor,
              onTap: () => setState(() => _cor = _paletaCores[i]),
            ),
          ],
        ],
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 4; i < _paletaCores.length; i++) ...[
            if (i > 4) const SizedBox(width: 12),
            ColorChoice(
              key: ValueKey('cor-$i'),
              color: _paletaCores[i],
              selected: _paletaCores[i] == _cor,
              onCor: onCor,
              onTap: () => setState(() => _cor = _paletaCores[i]),
            ),
          ],
        ],
      ),
    ],
  );

  Widget _botaoSalvar() => SizedBox(
    width: 240,
    child: FilledButton.icon(
      onPressed: _saving ? null : _salvar,
      icon: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(_isEdit ? Icons.check : Icons.arrow_forward),
      label: Text(_isEdit ? context.strings.salvar : context.strings.comecar),
    ),
  );
}

/// Botão Claro/Escuro do seletor de tema (ver imagem de referência).
///
/// O botão selecionado acompanha a cor escolhida ([cor]): claro = tom mais
/// vivo da cor, escuro = a própria cor escura. Cantos arredondados (10),
/// sombreado e borda clara. Não selecionado: transparente, texto apagado.
class _TemaOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;

  /// `true` quando o card está no modo claro (inverte as cores do botão).
  final bool temaClaro;

  /// Cor de fundo escolhida pelo usuário: tinge o botão selecionado.
  final Color cor;
  final VoidCallback onTap;

  const _TemaOption({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.temaClaro,
    required this.cor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Botão selecionado reage à cor: no claro usa um tom mais vivo da cor
    // (mistura com a cor de acento do tema); no escuro usa a própria cor.
    final theme = Theme.of(context);
    final selectedBg = temaClaro
        ? Color.lerp(cor, theme.colorScheme.primary, 0.35) ?? cor
        : cor;
    final selectedText = onBackgroundColor(selectedBg);
    // Borda clara acompanhando a cor do botão selecionado.
    final selectedBorder = temaClaro
        ? Colors.black.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.14);
    final unselectedText = temaClaro
        ? Colors.black.withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.45);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? selectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? selectedBorder : Colors.transparent,
              width: 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: temaClaro ? 0.12 : 0.45,
                      ),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? selectedText : unselectedText,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 15,
                  color: selected ? selectedText : unselectedText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Opções do menu aberto ao tocar no avatar.
enum _OpcaoAvatar { emoji, galeria, camera, ajustar, remover }

/// Posição + zoom escolhidos no editor de foto.
class _AjusteFoto {
  final double alignX;
  final double alignY;
  final double zoom;

  const _AjusteFoto(this.alignX, this.alignY, this.zoom);
}

/// Editor simples da foto do avatar: arrastar posiciona o recorte, o slider
/// controla o zoom. A prévia circular mostra exatamente como ficará salvo
/// (mesmo enquadramento do [ProfileAvatar]).
class _AjusteFotoSheet extends StatefulWidget {
  final String imagePath;
  final double alignX;
  final double alignY;
  final double zoom;
  final String avatarFallback;

  const _AjusteFotoSheet({
    required this.imagePath,
    required this.alignX,
    required this.alignY,
    required this.zoom,
    required this.avatarFallback,
  });

  @override
  State<_AjusteFotoSheet> createState() => _AjusteFotoSheetState();
}

class _AjusteFotoSheetState extends State<_AjusteFotoSheet> {
  late double _ax = widget.alignX.clamp(-1.0, 1.0);
  late double _ay = widget.alignY.clamp(-1.0, 1.0);
  late double _zoom = widget.zoom.clamp(1.0, 3.0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Text(
                context.strings.ajustarFoto,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                context.strings.ajustarFotoDica,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              // Arrastar move a foto junto com o dedo (1:1 de direção).
              // O `Alignment` da imagem é invertido em relação ao gesto:
              // aumentar `Alignment` desloca a imagem para o lado oposto
              // (ex.: `ay +1` mostra a base = imagem "sobe"), então o delta
              // do arrasto entra com sinal negativo nos dois eixos.
              onPanUpdate: (d) => setState(() {
                _ax = (_ax - d.delta.dx / 80).clamp(-1.0, 1.0);
                _ay = (_ay - d.delta.dy / 80).clamp(-1.0, 1.0);
              }),
              child: CircleAvatar(
                radius: 110,
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.08),
                child: ClipOval(
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: Transform.scale(
                      scale: _zoom,
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.cover,
                        alignment: Alignment(_ax, _ay),
                        errorBuilder: (_, _, _) => Text(
                          widget.avatarFallback,
                          style: const TextStyle(fontSize: 72),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  const Icon(Icons.zoom_out_outlined),
                  Expanded(
                    child: Slider(
                      value: _zoom,
                      min: 1,
                      max: 3,
                      divisions: 20,
                      label: '${(_zoom * 100).round()}%',
                      onChanged: (v) => setState(() => _zoom = v),
                    ),
                  ),
                  const Icon(Icons.zoom_in_outlined),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.strings.cancelar),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(
                        _AjusteFoto(_ax, _ay, _zoom),
                      ),
                      child: Text(context.strings.aplicar),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bolinha com um emoticon, marcada quando é o avatar escolhido.
class _AvatarChoice extends StatelessWidget {
  final String avatar;
  final bool selected;
  final Color onCor;
  final VoidCallback onTap;

  const _AvatarChoice({
    required this.avatar,
    required this.selected,
    required this.onCor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? primary.withValues(alpha: 0.25)
              : onCor.withValues(alpha: 0.05),
          border: Border.all(
            color: selected ? primary : onCor.withValues(alpha: 0.15),
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(avatar, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

/// Bolinha de cor de fundo, marcada quando é a cor escolhida.
///
/// Pública para os testes verificarem a paleta ativa por tema.
class ColorChoice extends StatelessWidget {
  final Color color;
  final bool selected;
  final Color onCor;
  final VoidCallback onTap;

  const ColorChoice({
    super.key,
    required this.color,
    required this.selected,
    required this.onCor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? primary : onCor.withValues(alpha: 0.15),
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 20, color: onBackgroundColor(color))
            : null,
      ),
    );
  }
}

/// Planilha de emojis do app: já abre direto na grade com todos os emojis
/// (categorias, busca e recentes). Tocar num emoji fecha devolvendo-o; o
/// chamador guarda apenas o primeiro emoticon.
class _EmojiSheet extends StatelessWidget {
  const _EmojiSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Text(
                  context.strings.escolhaEmoji,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) =>
                      Navigator.of(context).pop(emoji.emoji),
                  // Busca e rótulos no idioma do app: "unicórnio" em pt-BR,
                  // "unicorn" em en-US.
                  config: Config(
                    checkPlatformCompatibility: true,
                    locale: Locale(
                      Localizations.localeOf(context).languageCode,
                    ),
                    emojiViewConfig: EmojiViewConfig(
                      columns: 8,
                      emojiSizeMax: 28,
                      noRecents: Text(
                        context.strings.semEmojisRecentes,
                        style: const TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    searchViewConfig: SearchViewConfig(
                      hintText: context.strings.buscarEmoji,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
