plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.gilpereira.luckyscan50"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.gilpereira.luckyscan50"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName


    }

    buildTypes {
        // Flutter 3.35 sets broad filters on build types. Override there, rather
        // than in defaultConfig, and leave split-per-ABI builds untouched.
        if (providers.gradleProperty("target-platform").orNull == "android-arm64" &&
            providers.gradleProperty("split-per-abi").orNull != "true") {
            configureEach {
                ndk.abiFilters.clear()
                ndk.abiFilters.add("arm64-v8a")
            }
        }
        release {
            // INTERNAL TESTING ONLY: sign the optimized release with the debug key.
            // Replace with private signing credentials before any publication.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
