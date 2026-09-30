import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../db/db.dart';
import '../l10n/app_locale.dart';
import '../models/models.dart';
import '../services/categorizer.dart';
import '../services/crash_log.dart';
import '../services/ocr_service.dart';
import '../services/receipt_parser.dart';
import '../l10n/app_strings.dart';
import 'expense_form_screen.dart';

/// Tamanho máximo aceito para a foto do cupom (em bytes). Imagens maiores — em
/// especial vindas da galeria, que podem ter dezenas de MB em aparelhos novos —
/// são recusadas antes do OCR, que alocaria muito mais memória ao decodificar
/// (risco de travar/fechar o app em aparelhos simples).
///
/// A câmera usa `maxWidth` para redimensionar na origem, então este limite só
/// costuma pegar arquivos da galeria — cupons comprimidos ficam bem abaixo.
const int kMaxReceiptImageBytes = 8 * 1024 * 1024;

/// Foto grande demais para processar com segurança (decodificar + OCR
/// alocaria muito mais memória e poderia travar o app). Retorna a mensagem
/// de erro amigável, ou `null` se o tamanho for aceitável.
String? validarTamanhoImagem(int tamanhoBytes, [AppStrings? strings]) {
  if (tamanhoBytes <= kMaxReceiptImageBytes) return null;
  final s = strings ?? AppStrings.of(null);
  return s.imagemGrandeMsg(
      (tamanhoBytes / (1024 * 1024)).toStringAsFixed(1),
      (kMaxReceiptImageBytes / (1024 * 1024)).toStringAsFixed(0));
}

/// Captura a foto do cupom, roda o OCR on-device, interpreta os dados e
/// abre o formulário já preenchido para confirmação do usuário.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final OcrService _ocr = OcrService();
  bool _processing = false;

  @override
  void dispose() {
    _ocr.dispose();
    super.dispose();
  }

  Future<void> _capture(ImageSource source) async {
    // Captura as frases antes do primeiro `await`: o contexto pode sair da
    // arvore enquanto a imagem e o OCR sao processados.
    final s = context.strings;
    setState(() => _processing = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked == null) {
        setState(() => _processing = false);
        return;
      }

      // Recusa a imagem antes de decodificá-la: arquivos enormes (galeria)
      // explodem a memória no decode/OCR e podem travar o app.
      final tamanho = await File(picked.path).length();
      final erroTamanho = validarTamanhoImagem(tamanho, s);
      if (erroTamanho != null) throw Exception(erroTamanho);

      final text = await _ocr.extractText(picked.path);
      if (text.trim().isEmpty) {
        throw Exception(s.cupomIlegivel);
      }

      final draft = ReceiptParser.parse(text);
      final categoria = await _categorize(draft);

      if (!mounted) return;
      setState(() => _processing = false);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ExpenseFormScreen.fromReceipt(
            draft: draft,
            categoria: categoria,
            fotoPath: picked.path,
          ),
        ),
      );
    } catch (erro, pilha) {
      // Falha no fluxo do cupom (OCR, picker ou decode): registra no log
      // local, que em release é o único rastro que sobra — o logcat não.
      registrarFalha(erro, pilha, contexto: 'ocr');
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.falhaLerCupom('$erro'))),
      );
      // Fallback: formulário manual em branco.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ExpenseFormScreen()),
      );
    }
  }

  Future<Category> _categorize(ReceiptDraft draft) async {
    final categorizer = Categorizer(
      memoryLoader: DBHelper.instance.merchantCategories,
    );
    return categorizer.categorize(
      estabelecimento: draft.estabelecimento,
      text: draft.textoOcr,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(s.fotoCupomTitulo)),
      body: Center(
        child: _processing
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(s.lendoCupom),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long,
                        size: 72, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(s.dicaFoto, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      icon: const Icon(Icons.photo_camera),
                      label: Text(s.tirarFoto),
                      onPressed: () => _capture(ImageSource.camera),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.photo_library),
                      label: Text(s.escolherGaleria),
                      onPressed: () => _capture(ImageSource.gallery),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
