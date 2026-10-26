import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release builds are signed with the upload key from android/key.properties (kept outside git):
// the same key for the site APK, RuStore and the Play upload. Without it a release build fails.
// The old personal key (letopis-dev.jks, public password) is retired: deploy/sign-site.sh adds a
// rotation proof, so phones with the old build update without reinstalling. Debug builds use the
// standard Android debug key.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val releaseBuild = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
val rustoreAppId = (project.findProperty("letopisRustoreAppId") as String?)?.trim().orEmpty()
if (releaseBuild && keyProps.isEmpty) {
    throw GradleException("Release build needs android/key.properties with the upload key (see README, Signing)")
}

android {
    namespace = "com.bylinsky.letopis"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures { resValues = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.bylinsky.letopis"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Distribution channels (Dart reads the flavor as `appFlavor`, see lib/services/channel.dart).
    // Same applicationId and key: site and RuStore installs update each other.
    flavorDimensions += "channel"
    productFlavors {
        create("site") { dimension = "channel" }
        create("rustore") {
            dimension = "channel"
            // RuStore Pay: app id from the RuStore Console URL (apps/<id>/versions); empty until the
            // app exists there — then the support button says payments are not available yet.
            resValue("string", "CONSOLE_APPLICATION_ID", rustoreAppId)
            resValue("string", "SDK_PAY_SCHEME", "letopispay")
        }
        create("play") { dimension = "channel" }
    }

    signingConfigs {
        if (!keyProps.isEmpty) {
            create("upload") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (!keyProps.isEmpty) signingConfig = signingConfigs.getByName("upload")
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
