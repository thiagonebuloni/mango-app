import java.security.KeyStore
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Assinatura de release (A3). A chave `debug` é pública: vem no SDK do
// Android e é igual em qualquer máquina, então um APK de release assinado
// com ela pode ser "atualizado" por qualquer pessoa que saiba o nome do
// pacote (`br.com.mango.mango`). A chave de verdade fica em
// `android/key.properties` + keystore `.jks`, ambos fora do Git
// (android/.gitignore).
val chaveProperties = Properties()
val chaveArquivo = rootProject.file("key.properties")
val temChavePropria = chaveArquivo.exists()
if (temChavePropria) {
    chaveArquivo.inputStream().use { chaveProperties.load(it) }
}

val camposObrigatorios = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val camposFaltando = camposObrigatorios.filter {
    chaveProperties.getProperty(it).isNullOrBlank()
}
if (temChavePropria && camposFaltando.isNotEmpty()) {
    throw GradleException(
        "android/key.properties incompleto: falta ${camposFaltando.joinToString(", ")}. " +
            "Veja a seção 'Gerando o APK de release' no README.",
    )
}

// Caminhos relativos são resolvidos a partir de `android/`, onde o
// key.properties mora (ex.: `storeFile=mango-release.jks`).
val arquivoKeystore = chaveProperties.getProperty("storeFile")?.let { rootProject.file(it) }
if (temChavePropria && arquivoKeystore != null && !arquivoKeystore.exists()) {
    throw GradleException(
        "Keystore não encontrado em ${arquivoKeystore.path} (storeFile do " +
            "android/key.properties). Veja a seção 'Gerando o APK de release' no README.",
    )
}

// PKCS12 — formato que o keytool moderno usa por padrão, mesmo com extensão
// `.jks` — guarda **uma única senha**: a da chave é a do keystore. Com um
// keyPassword diferente, o AGP falha só no fim do empacotamento com
// "Get Key failed: Given final block not properly padded", erro que não cita
// senha nenhuma. Aqui o storePassword é reaproveitado (com aviso) e o README
// explica a regra; keystores JKS seguem aceitando senhas distintas.
val senhaKeystore = chaveProperties.getProperty("storePassword").orEmpty()
val aliasChave = chaveProperties.getProperty("keyAlias").orEmpty()
var senhaChave = chaveProperties.getProperty("keyPassword").orEmpty()
if (temChavePropria) {
    val keystore = requireNotNull(arquivoKeystore) { "storeFile sem caminho em android/key.properties" }
    val tipoKeystore = try {
        KeyStore.getInstance(keystore, senhaKeystore.toCharArray()).type
    } catch (e: Exception) {
        throw GradleException(
            "Não foi possível abrir o keystore ${keystore.path} com o storePassword de " +
                "android/key.properties (${e.message}). Veja a seção 'Assinatura do APK " +
                "(chave própria)' no README.",
        )
    }
    if (tipoKeystore.equals("PKCS12", ignoreCase = true) && senhaChave != senhaKeystore) {
        logger.warn(
            "android/key.properties: ${keystore.name} é PKCS12 (senha única) — usando o " +
                "storePassword como keyPassword; o keyPassword do arquivo é ignorado. " +
                "Veja a seção 'Assinatura do APK (chave própria)' no README.",
        )
        senhaChave = senhaKeystore
    }
}

android {
    namespace = "br.com.mango.mango"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "br.com.mango.mango"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (temChavePropria) {
            create("release") {
                keyAlias = aliasChave
                keyPassword = senhaChave
                storeFile = arquivoKeystore
                storePassword = chaveProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Sem chave própria o release sai **sem** assinatura (nunca com a
            // de debug) — e o build já para antes disso, veja abaixo.
            signingConfig = if (temChavePropria) signingConfigs.getByName("release") else null
        }
    }
}

// Release sem chave própria: erro claro em vez de APK assinado com a chave
// de debug; com chave própria, confere se ela realmente abre (alias + senhas)
// — melhor falhar aqui, com a causa, do que no meio do empacotamento.
// Debug/profile continuam funcionando normalmente.
gradle.taskGraph.whenReady {
    val pediuRelease = allTasks.any { tarefa ->
        (tarefa.name.startsWith("assemble") || tarefa.name.startsWith("bundle")) &&
            tarefa.name.contains("Release")
    }
    if (pediuRelease && temChavePropria) {
        val keystore = requireNotNull(arquivoKeystore)
        // Alias inexistente não lança: `getKey` devolve null, daí o teste das duas
        // condições (chave ilegível × chave ausente) antes de empacotar.
        val chave = try {
            KeyStore
                .getInstance(keystore, senhaKeystore.toCharArray())
                .getKey(aliasChave, senhaChave.toCharArray())
        } catch (e: Exception) {
            throw GradleException(
                "Assinatura de release inválida: não foi possível ler a chave '$aliasChave' " +
                    "de ${keystore.path} (${e.message}). Confira as senhas em " +
                    "android/key.properties. Veja a seção 'Assinatura do APK (chave própria)' " +
                    "no README.",
            )
        }
        if (chave == null) {
            throw GradleException(
                "Assinatura de release inválida: o keystore ${keystore.path} não tem a " +
                    "chave '$aliasChave' (keyAlias do android/key.properties). Rode " +
                    "'keytool -list -keystore ${keystore.path}' para ver o alias correto. " +
                    "Veja a seção 'Assinatura do APK (chave própria)' no README.",
            )
        }
    }
    if (pediuRelease && !temChavePropria) {
        throw GradleException(
            "Build de release sem assinatura própria: crie android/key.properties " +
                "com storeFile, storePassword, keyAlias e keyPassword (e o keystore " +
                "correspondente). Veja a seção 'Gerando o APK de release' no README.",
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// ML Kit: somente o reconhecedor latino (leve). O canal nativo
// (mango/ocr em MainActivity.kt) faz o OCR direto, sem plugin.
dependencies {
    implementation("com.google.mlkit:text-recognition:16.0.1")
}
