# Azm release ProGuard/R8 rules.
#
# The release build type mirrors the original DeChainer posture
# (isMinifyEnabled + isShrinkResources in app/build.gradle.kts, with
# proguard-android-optimize.txt plus this file). R8 already keeps every
# component named in the AndroidManifest; the rules below make the keep-set
# explicit and auditable, and protect classes reached only reflectively
# (Shizuku binder wrappers, HiddenApiBypass provisioning), which manifest
# parsing cannot see.

# ---------------------------------------------------------------------------
# Flutter engine — the standard documented Flutter keep rules. (The Flutter
# Gradle plugin also injects its own rules; these are the baseline from
# Flutter's own proguard example and are kept here so the set is complete
# in one place.)
# ---------------------------------------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ---------------------------------------------------------------------------
# This app's manifest-declared components. MainActivity is the Flutter
# entry point (instantiated by the framework by name); the accessibility
# service and both receivers are instantiated by the system by name.
# ---------------------------------------------------------------------------
-keep class com.alnajashia.azm.MainActivity { *; }
-keep class com.alnajashia.azm.AzmApplication { *; }
-keep class com.alnajashia.azm.accessibility.AzmAccessibilityService { *; }
-keep class com.alnajashia.azm.accessibility.BlockActivity { *; }
-keep class com.alnajashia.azm.accessibility.AccessibilityRequestActivity { *; }
-keep class com.alnajashia.azm.deviceowner.AzmDeviceAdminReceiver { *; }
-keep class com.alnajashia.azm.deviceowner.AzmPolicyUpdateReceiver { *; }

# ---------------------------------------------------------------------------
# Shizuku — API, provider (rikka.shizuku.ShizukuProvider is the manifest
# <provider>), and the binder/Parcelable wrappers the provisioning path
# reaches reflectively through ShizukuBinderWrapper.
# ---------------------------------------------------------------------------
-keep class rikka.shizuku.** { *; }
-keep class moe.shizuku.** { *; }

# ---------------------------------------------------------------------------
# HiddenApiBypass — also the original's only project-specific rule
# (app/proguard-rules.pro in DeChainer). The provisioning path calls it
# and, through it, hidden DevicePolicyManager APIs reflectively.
# ---------------------------------------------------------------------------
-keep class org.lsposed.hiddenapibypass.** { *; }

# ---------------------------------------------------------------------------
# Parcelable contract. This codebase currently has NO @Parcelize or
# Parcelable models of its own (verified 2026-11-09 — TimeModels are
# plain data classes serialised by hand), so there is nothing app-specific
# to keep; this standard member rule protects any Parcelable CREATOR
# (ours or a dependency's) from being stripped or renamed.
# ---------------------------------------------------------------------------
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# NOTE: PrivilegedChannelHandler is constructed directly from MainActivity
# (no reflection), and its channel method names are string keys dispatched
# through a when-block, not reflective lookups — R8 reachability keeps it
# correctly without a rule. Do NOT add a blanket keep for the whole
# com.alnajashia.azm package: it would defeat minification
# of our own code, which the original did not do either.

# Flutter deferred-components references Play Core split-install classes that
# are not bundled (deferred components are unused); R8 must not fail on them.
# (Standard Flutter R8 companion rules; the original native app never needed
# them because it has no Flutter embedding.)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.Task
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
