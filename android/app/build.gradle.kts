import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Faz P.2.1 — Google Maps SDK for Android client key. Read from
// android/local.properties (gitignored, per-machine — same mechanism
// settings.gradle.kts already uses for flutter.sdk), never a literal in
// source control. Empty when unset — the manifest placeholder below then
// resolves to an empty API_KEY value, which the Maps SDK treats as an
// initialization failure the Flutter-side map screen already handles as
// an expected fallback, not a build error.
//
// Faz P.2.1 fix: the package-qualified `java.util.Properties()` form
// failed to resolve here ("Unresolved reference 'util'") — at the top
// level of this Kotlin DSL script, the Android/Kotlin Gradle plugins'
// auto-generated accessors shadow the bare `java` identifier, breaking
// inline `java.util.*` qualification. A proper top-level `import
// java.util.Properties` (above) resolves via Kotlin's import mechanism
// instead, which isn't subject to that receiver-shadowing problem.
val mapsApiKeyAndroid: String =
    run {
        val properties = Properties()
        val localPropertiesFile = rootProject.file("local.properties")
        if (localPropertiesFile.exists()) {
            localPropertiesFile.inputStream().use { properties.load(it) }
        }
        properties.getProperty("mapsApiKeyAndroid", "")
    }

android {
    namespace = "com.abakus.one"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent production Application ID (matches the iOS/macOS bundle
        // ID com.abakus.one) — replaces the temporary com.example.* value.
        applicationId = "com.abakus.one"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Faz P.2.1 — resolves AndroidManifest.xml's ${mapsApiKeyAndroid} placeholder.
        manifestPlaceholders["mapsApiKeyAndroid"] = mapsApiKeyAndroid
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Environment flavors (Phase 2, P2-002) — orthogonal to buildTypes above:
    // a build is always both a flavor (which Firebase project/environment)
    // and a build type (debug/release), never one in place of the other.
    // Each flavor shares the same applicationId (matches the package name
    // registered for all three Firebase Android apps) and picks up its
    // Firebase config from android/app/src/<flavor>/google-services.json.
    flavorDimensions += "environment"
    productFlavors {
        create("development") {
            dimension = "environment"
        }
        create("staging") {
            dimension = "environment"
        }
        create("production") {
            dimension = "environment"
        }
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
