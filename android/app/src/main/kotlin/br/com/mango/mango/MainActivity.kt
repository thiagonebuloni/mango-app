package br.com.mango.mango

import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "mango/ocr"

    // Extensões aceitas para o OCR (as mesmas que o `image_picker` gera).
    private val extensoesAceitas =
        setOf("jpg", "jpeg", "png", "webp", "bmp", "gif", "heic")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractText" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Caminho da imagem ausente.", null)
                            return@setMethodCallHandler
                        }
                        val arquivo = File(path)
                        val erroCaminho = validarCaminhoImagem(arquivo)
                        if (erroCaminho != null) {
                            result.error("INVALID_PATH", erroCaminho, null)
                            return@setMethodCallHandler
                        }
                        try {
                            val image = InputImage.fromFilePath(this, Uri.fromFile(arquivo))
                            val recognizer =
                                TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                            recognizer.process(image)
                                .addOnSuccessListener { visionText -> result.success(visionText.text) }
                                .addOnFailureListener { e ->
                                    result.error("OCR_FAILED", e.localizedMessage, null)
                                }
                                .addOnCompleteListener { recognizer.close() }
                        } catch (e: Exception) {
                            result.error("OCR_FAILED", e.localizedMessage, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Defesa em profundidade do canal `mango/ocr` (A1): o MethodChannel é
     * interno ao app, mas mesmo assim o caminho precisa
     *
     * 1. ter extensão de imagem conhecida e
     * 2. resolver (canonicamente, blindando `..` e symlinks) para dentro de
     *    um diretório privado do app — nunca leitura arbitrária de arquivos
     *    fora do sandbox.
     *
     * Retorna `null` quando o caminho é válido ou uma mensagem amigável
     * para `result.error` caso contrário.
     */
    private fun validarCaminhoImagem(arquivo: File): String? {
        val ext = arquivo.extension.lowercase()
        if (ext.isEmpty() || ext !in extensoesAceitas) {
            return "Extensão de imagem não suportada: .$ext"
        }
        val raizes = listOfNotNull(
            cacheDir,
            filesDir,
            noBackupFilesDir,
            externalCacheDir,
            getExternalFilesDir(null),
        ).mapNotNull { dir -> runCatching { dir.canonicalFile }.getOrNull() }
        val alvo = runCatching { arquivo.canonicalFile }.getOrNull()
            ?: return "Caminho da imagem inválido."
        val dentro = raizes.any { raiz ->
            alvo.path == raiz.path || alvo.path.startsWith(raiz.path + File.separator)
        }
        if (!dentro) return "Caminho fora dos diretórios privados do app."
        if (!alvo.isFile) return "Arquivo de imagem não encontrado."
        return null
    }
}
