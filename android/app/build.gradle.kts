plugins {
    id("com.android.application")
}

fun git(vararg args: String): String? = try {
    val p = ProcessBuilder(listOf("git") + args).directory(rootProject.projectDir).redirectErrorStream(true).start()
    val out = p.inputStream.bufferedReader().readText().trim()
    if (p.waitFor() == 0 && out.isNotEmpty()) out else null
} catch (_: Exception) { null }

val buildNumber = git("rev-list", "--count", "HEAD")?.toIntOrNull() ?: 1
val buildSha = git("rev-parse", "--short", "HEAD") ?: "dev"

android {
    namespace = "com.cloudphone.launcher"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.cloudphone.launcher"
        minSdk = 24
        targetSdk = 34
        versionCode = buildNumber
        versionName = "1.$buildNumber.$buildSha"
        buildConfigField("int", "CP_VERSION_CODE", "$buildNumber")
        buildConfigField("String", "CP_VERSION", "\"1.$buildNumber.$buildSha\"")
    }
    buildFeatures { buildConfig = true }
    // Same sideload key as the zen-panel CI APKs (see app/keystore/README.txt):
    // one key for every CI APK so "install over previous" works.
val uploadStore = rootProject.file("app/keystore/upload.jks")
val storePass = System.getenv("ANDROID_KEYSTORE_PASSWORD").orEmpty().ifBlank { "zenpanel-upload" }
    val keyAlias = System.getenv("ANDROID_KEY_ALIAS").orEmpty().ifBlank { "zen-panel" }
    val keyPass = System.getenv("ANDROID_KEY_PASSWORD").orEmpty().ifBlank { storePass }
    if (uploadStore.exists()) {
        signingConfigs.create("release") {
            storeFile = uploadStore
            storePassword = storePass
            this.keyAlias = keyAlias
            keyPassword = keyPass
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.webkit:webkit:1.12.1")
    implementation("androidx.preference:preference:1.2.1")
}