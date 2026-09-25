import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Avatares (emoticons) oferecidos no cadastro do perfil.
const List<String> kProfileAvatars = [
  '🙂', '😀', '😎', '🤓', '🥳', '🤩',
  '🐱', '🐶', '🦊', '🐼', '🦁', '🐸',
  '🌟', '🍀', '🚀', '🎯',
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
  ConsumerState<ProfileSetupScreen> createState() =>
      _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  late final TextEditingController _nome;
  late String _avatar;
  late Color _cor;
  late bool _temaClaro;

  /// Valores ao abrir a tela: base para saber se houve alteração (só na
  /// edição vale pedir confirmação ao sair).
  late String _nomeInicial;
  late String _avatarInicial;
  late Color _corInicial;
  late bool _temaClaroInicial;

  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  bool get _temAlteracoes =>
      _nome.text.trim() != _nomeInicial ||
      _avatar != _avatarInicial ||
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
    _temaClaro = perfil?.temaClaro ?? true;
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
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    await ref.read(profileProvider.notifier).save(
          UserProfile(
            nome: _nome.text.trim(),
            avatar: _avatar,
            corFundo: _cor.toARGB32(),
            temaClaro: _temaClaro,
          ),
        );
    if (!mounted) return;
    setState(() {
      _saving = false;
      // O que está na tela agora é o perfil salvo: nada mais pendente.
      _nomeInicial = _nome.text.trim();
      _avatarInicial = _avatar;
      _corInicial = _cor;
      _temaClaroInicial = _temaClaro;
    });

    // No primeiro acesso esta tela é a raiz do app (nada a fechar). Na edição
    // ela foi empilhada pelo Menu: volta e avisa o usuário.
    if (_isEdit) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Perfil atualizado')),
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
        title: const Text('Descartar alterações?'),
        content: const Text(
          'Você mudou o perfil e ainda não salvou. Sair agora descarta '
          'as alterações.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continuar editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Descartar e sair'),
          ),
        ],
      ),
    );
    if ((descartar ?? false) && mounted) navigator.pop();
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
    setState(() => _avatar = escolhido.characters.first);
  }

  @override
  Widget build(BuildContext context) {
    // Prévia do fundo: cor escolhida no tema claro; cinza escuro fixo no
    // tema escuro (igual ao resto do app — ver [kFundoTemaEscuro]).
    final fundoPrevia = _temaClaro ? _cor : kFundoTemaEscuro;
    final onCor = onBackgroundColor(fundoPrevia);

    return PopScope<Object?>(
      // Na edição, sair com alterações não salvas pede confirmação; sem
      // alterações (ou no primeiro acesso) a saída é direta.
      canPop: !_bloqueiaSaida,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _confirmarSaida();
      },
      child: Scaffold(
        backgroundColor: fundoPrevia,
        appBar: _isEdit
            ? AppBar(
                title: const Text('Editar perfil'),
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
                      _previewAvatar(onCor),
                      _campoNome(onCor),
                      const SizedBox(height: 20),
                      _escolhaAvatar(onCor),
                      const SizedBox(height: 20),
                      _escolhaTema(onCor),
                      const SizedBox(height: 20),
                      _escolhaCor(onCor),
                      const SizedBox(height: 28),
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
    );
  }

  Widget _cabecalho(Color onCor) => Column(
        children: [
          Text(
            _isEdit ? 'Editar perfil' : 'Bem-vindo!',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.bold, color: onCor),
          ),
          const SizedBox(height: 8),
          Text(
            _isEdit
                ? 'Ajuste seu nome, avatar e cor de fundo.'
                : 'Vamos criar seu perfil para personalizar o app.',
            textAlign: TextAlign.center,
            style: TextStyle(color: onCor.withValues(alpha: 0.7)),
          ),
        ],
      );

  Widget _previewAvatar(Color onCor) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Tooltip(
          message: 'Toque para escolher outro emoji',
          child: InkWell(
            key: const ValueKey('avatar-preview'),
            onTap: _escolherEmojiDaGrade,
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 48,
              backgroundColor: onCor.withValues(alpha: 0.08),
              child: Text(_avatar, style: const TextStyle(fontSize: 48)),
            ),
          ),
        ),
      );

  Widget _campoNome(Color onCor) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: TextFormField(
          controller: _nome,
          textCapitalization: TextCapitalization.words,
          maxLength: 24,
          // Cor explícita a partir da prévia do fundo (não do Theme do app):
          // ao alternar o tema na edição, o Scaffold mostra a prévia mas o
          // Theme ainda é o do perfil salvo — sem isto o texto herdaria a cor
          // errada (ex.: branco sobre fundo claro, sem contraste).
          style: TextStyle(color: onCor),
          decoration: InputDecoration(
            labelText: 'Nome do usuário',
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
              borderSide:
                  BorderSide(color: onCor.withValues(alpha: 0.35)),
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
              (v ?? '').trim().isEmpty ? 'Informe seu nome' : null,
          onFieldSubmitted: (_) => _salvar(),
        ),
      );

  Widget _escolhaAvatar(Color onCor) => Column(
        children: [
          Text('Escolha seu avatar',
              style: TextStyle(fontWeight: FontWeight.bold, color: onCor)),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final avatar in kProfileAvatars)
                _AvatarChoice(
                  avatar: avatar,
                  selected: avatar == _avatar,
                  onCor: onCor,
                  onTap: () => setState(() => _avatar = avatar),
                ),
            ],
          ),
          // Os atalhos acima são só os mais usados: aqui abre a grade de emojis
          // do app (categorias + busca + recentes) para escolher qualquer um.
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton.icon(
              onPressed: _escolherEmojiDaGrade,
              icon: const Icon(Icons.emoji_emotions_outlined),
              label: const Text('Outro emoji'),
            ),
          ),
        ],
      );

  Widget _escolhaTema(Color onCor) => Column(
        children: [
          Text('Tema',
              style: TextStyle(fontWeight: FontWeight.bold, color: onCor)),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Tema claro'),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Tema escuro'),
              ),
            ],
            selected: {_temaClaro},
            onSelectionChanged: (selecao) {
              final tema = selecao.first;
              if (tema == _temaClaro) return;
              setState(() {
                _temaClaro = tema;
                final paleta = _temaClaro ? kCoresTemaClaro : kCoresTemaEscuro;
                final origem = _temaClaro ? kCoresTemaEscuro : kCoresTemaClaro;
                _cor = corNaPaleta(_cor, origem, paleta);
              });
            },
          ),
        ],
      );

  Widget _escolhaCor(Color onCor) => Column(
        children: [
          Text('Cor de fundo',
              style: TextStyle(fontWeight: FontWeight.bold, color: onCor)),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < _paletaCores.length; i++)
                ColorChoice(
                  key: ValueKey('cor-$i'),
                  color: _paletaCores[i],
                  selected: _paletaCores[i] == _cor,
                  onCor: onCor,
                  onTap: () => setState(() => _cor = _paletaCores[i]),
                ),
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
          label: Text(_isEdit ? 'Salvar' : 'Começar'),
        ),
      );
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
                  'Escolha um emoji',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) =>
                      Navigator.of(context).pop(emoji.emoji),
                  config: const Config(
                    checkPlatformCompatibility: true,
                    // App em pt-BR: busca em português ("unicórnio" em vez de
                    // "unicorn").
                    locale: Locale('pt'),
                    emojiViewConfig: EmojiViewConfig(
                      columns: 8,
                      emojiSizeMax: 28,
                      noRecents: Text(
                        'Sem emojis recentes',
                        style: TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    searchViewConfig: SearchViewConfig(
                      hintText: 'Buscar emoji',
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

