plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.alnajashia.dominanter"
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
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
