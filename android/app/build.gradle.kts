import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Two keys:
// - personal builds (`flutter build apk`) use the dev key in the repo, so updates install over each other;
// - store builds (`flutter build appbundle`, or any build with LETOPIS_STORE=1) use the upload key from
//   android/key.properties, which lives outside git. A store build without it fails instead of falling back.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val storeBuild = System.getenv("LETOPIS_STORE") == "1" ||
    gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) }
if (storeBuild && keyProps.isEmpty) {
    throw GradleException("Store build needs android/key.properties with the upload key (see README, Signing)")
}

android {
    namespace = "com.bylinsky.letopis"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

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

    signingConfigs {
        create("dev") {
            storeFile = file("letopis-dev.jks")
            storePassword = "android"
            keyAlias = "letopis"
            keyPassword = "android"
        }
        if (storeBuild) {
            create("store") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("dev")
        }
        release {
            signingConfig = signingConfigs.getByName(if (storeBuild) "store" else "dev")
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
