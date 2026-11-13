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

val azmKeystoreProps = Properties()
val azmKeystorePropsFile = rootProject.file(
    System.getenv("AZM_KEYSTORE_PROPERTIES")
        ?: "../../keys/keystore.properties"
)
if (azmKeystorePropsFile.exists()) {
    azmKeystorePropsFile.inputStream().use {
        azmKeystoreProps.load(it)
    }
}

android {
    namespace = "com.alnajashia.azm"

    signingConfigs {
        create("azmRelease") {
            if (azmKeystorePropsFile.exists()) {
                storeFile = file(azmKeystoreProps.getProperty("storeFile"))
                storePassword = azmKeystoreProps.getProperty("storePassword")
                keyAlias = azmKeystoreProps.getProperty("keyAlias")
                keyPassword = azmKeystoreProps.getProperty("keyPassword")
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
        // LiteRT 2.2.0's Kotlin-API module was published with a newer
        // Kotlin metadata version than this project's compiler; the
        // feature uses only its stable Java-facing surface (the same
        // org.tensorflow.lite API the original compiles against), so
        // the metadata version check is skipped for this module.
        freeCompilerArgs += "-Xskip-metadata-version-check"
    }

    androidResources {
        // The NSFW model asset must stay uncompressed: the detector
        // memory-maps it straight from the APK (openFd), as in the
        // original.
        noCompress.add("tflite")
    }

    packaging {
        jniLibs {
            // The visual-blocking detector only uses the classic
            // Interpreter API on the CPU, which loads just
            // libLiteRt.so. The GPU accelerator (dlopen'd on demand,
            // optional) and the JNI bridge for the CompiledModel API
            // are never used — excluded as in the original.
            excludes += listOf("**/libLiteRtClGlAccelerator.so", "**/liblitert_jni.so")
        }
    }

    defaultConfig {
        applicationId = "com.alnajashia.azm"
        minSdk = 30
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (azmKeystorePropsFile.exists()) {
                signingConfigs.getByName("azmRelease")
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
    // LiteRT (TensorFlow Lite) runtime for the on-device NSFW
    // classifier (visual blocking, F16/F17) — same artifact and
    // version as the original (com.google.ai.edge.litert:litert
    // 2.2.0). CPU Interpreter API only; inference is fully on-device.
    implementation("com.google.ai.edge.litert:litert:2.2.0")
    // Biometric (F32) is a Dart-side local_auth UI gate per ARCHITECTURE.md §2, so no
    // native biometric dependency is needed here.
}
