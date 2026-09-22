import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Avatares (emoticons) oferecidos no cadastro do perfil.
const List<String> kProfileAvatars = [
  '🙂', '😀', '😎', '🤓', '🥳', '🤩',
  '🐱', '🐶', '🦊', '🐼', '🦁', '🐸',
  '🌟', '🍀', '🚀', '🎯',
];

/// Cores de fundo (claras, para o texto continuar legível) da tela inicial.
const List<Color> kProfileColors = [
  Color(0xFFE0F2F1), // verde-água
  Color(0xFFE3F2FD), // azul
  Color(0xFFF3E5F5), // lilás
  Color(0xFFFCE4EC), // rosa
  Color(0xFFFFF3E0), // pêssego
  Color(0xFFE8F5E9), // verde
  Color(0xFFFFFDE7), // amarelo claro
  Color(0xFFEEEEEE), // cinza
];

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
  late final TextEditingController _nome;
  late String _avatar;
  late Color _cor;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final perfil = widget.existing;
    _nome = TextEditingController(text: perfil?.nome ?? '');
    _avatar = perfil?.avatar ?? kProfileAvatars.first;
    _cor = Color(perfil?.corFundo ?? UserProfile.corFundoPadrao);
  }

  @override
  void dispose() {
    _nome.dispose();
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
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);

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

  @override
  Widget build(BuildContext context) {
    final onCor = onBackgroundColor(_cor);

    return Scaffold(
      backgroundColor: _cor,
      appBar: _isEdit
          ? AppBar(
              title: const Text('Editar perfil'),
              backgroundColor: Colors.transparent,
              foregroundColor: onCor,
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
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
        child: CircleAvatar(
          radius: 48,
          backgroundColor: onCor.withValues(alpha: 0.08),
          child: Text(_avatar, style: const TextStyle(fontSize: 48)),
        ),
      );

  Widget _campoNome(Color onCor) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: TextFormField(
          controller: _nome,
          textCapitalization: TextCapitalization.words,
          maxLength: 24,
          decoration: InputDecoration(
            labelText: 'Nome do usuário',
            prefixIcon: const Icon(Icons.person_outline),
            filled: true,
            fillColor: onCor.withValues(alpha: 0.05),
            counterText: '',
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
              for (var i = 0; i < kProfileColors.length; i++)
                _ColorChoice(
                  key: ValueKey('cor-$i'),
                  color: kProfileColors[i],
                  selected: kProfileColors[i] == _cor,
                  onCor: onCor,
                  onTap: () => setState(() => _cor = kProfileColors[i]),
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
class _ColorChoice extends StatelessWidget {
  final Color color;
  final bool selected;
  final Color onCor;
  final VoidCallback onTap;

  const _ColorChoice({
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

