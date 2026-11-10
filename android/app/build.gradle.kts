import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Toolchain versions are pinned by the Flutter 3.35.1 template in
// android/settings.gradle.kts (AGP 8.9.1, Kotlin 2.1.0). The original
// DeChainer uses AGP 8.13.2 / Kotlin 2.4.10 (its gradle/libs.versions.toml).
// That delta (parity audit D-37) is DELIBERATELY HELD: upgrading AGP/Kotlin
// independently of the Flutter template risks breaking the fragile sandbox
// build (see build_apk.sh) for no behavioural gain, and the versions will
// move when the Flutter template itself moves. Recorded here so the parity
// documentation stays honest — do not "fix" this silently.

val dominanterKeystoreProps = Properties()
val dominanterKeystorePropsFile = rootProject.file(
    System.getenv("DOMINANTER_KEYSTORE_PROPERTIES")
        ?: "../../keys/keystore.properties"
)
if (dominanterKeystorePropsFile.exists()) {
    dominanterKeystorePropsFile.inputStream().use {
        dominanterKeystoreProps.load(it)
    }
}

android {
    namespace = "io.github.alnajashia.dominanter"

    signingConfigs {
        create("dominanterRelease") {
            if (dominanterKeystorePropsFile.exists()) {
                storeFile = file(dominanterKeystoreProps.getProperty("storeFile"))
                storePassword = dominanterKeystoreProps.getProperty("storePassword")
                keyAlias = dominanterKeystoreProps.getProperty("keyAlias")
                keyPassword = dominanterKeystoreProps.getProperty("keyPassword")
            }
        }
    }
    // Envelope matches the original DeChainer (minSdk 30, target/compile 36) — see
    // docs/ARCHITECTURE.md §2. Values are pinned explicitly instead of flutter.* defaults.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    // Java/Kotlin 21 matches the original project (JavaVersion.VERSION_21) and the
    // JDK 21 used to run Gradle here. (17 is the lowest safe fallback — AGP 8.9 and
    // Kotlin 2.1 accept both; do not go below 17, which Gradle itself requires.)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_21.toString()
    }

    defaultConfig {
        applicationId = "io.github.alnajashia.dominanter"
        minSdk = 30
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (dominanterKeystorePropsFile.exists()) {
                signingConfigs.getByName("dominanterRelease")
            } else {
                signingConfigs.getByName("debug")
            }

            // Release hardening, mirroring the original's posture
            // (DeChainer app/build.gradle.kts, release block: minify and
            // resource shrinking on, proguard-android-optimize.txt plus
            // proguard-rules.pro). Parity audit D-37: an earlier build of
            // ours shipped release with both off.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Shizuku API + provider, pinned exactly as the original (13.1.5) — ARCHITECTURE.md §2.
    // Imported ONLY by the shizuku/ provisioning package (setup-time), never by runtime code.
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
    // Hidden-API access for the binder-wrapped DevicePolicyManager provisioning path.
    implementation("org.lsposed.hiddenapibypass:hiddenapibypass:4.3")
    // Biometric (F32) is a Dart-side local_auth UI gate per ARCHITECTURE.md §2, so no
    // native biometric dependency is needed here.
}
