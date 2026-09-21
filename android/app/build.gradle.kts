import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from android/key.properties (written by the release
// workflow from repository secrets, or placed manually for local testing).
// Without it, release builds fall back to debug signing so local
// `flutter run --release` keeps working without any setup.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "dev.shiori.reader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Development identity only; final release identity is deferred.
        applicationId = "dev.shiori.reader"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = if (providers.gradleProperty("shioriUpdateInstallSmoke").orNull == "true") {
            "dev.shiori.reader.UpdateInstallSmokeRunner"
        } else "android.test.InstrumentationTestRunner"
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

// Platform-provided JUnit3 instrumentation only; no downloaded test framework.
// Compile-only keeps these libraries out of both production and test APK dex.
dependencies {
    val optional = "${android.sdkDirectory}/platforms/android-${android.compileSdk}/optional"
    androidTestCompileOnly(files("$optional/android.test.base.jar", "$optional/android.test.runner.jar"))
}
