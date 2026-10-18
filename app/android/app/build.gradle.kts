import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val privateSigning = Properties()
val privateSigningFile = rootProject.file("key.properties")
if (privateSigningFile.isFile) {
    privateSigningFile.inputStream().use { privateSigning.load(it) }
}
val hasPrivateSigning = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !privateSigning.getProperty(it).isNullOrBlank() }

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

    signingConfigs {
        if (hasPrivateSigning) {
            create("privateRelease") {
                storeFile = rootProject.file(privateSigning.getProperty("storeFile"))
                storePassword = privateSigning.getProperty("storePassword")
                keyAlias = privateSigning.getProperty("keyAlias")
                keyPassword = privateSigning.getProperty("keyPassword")
            }
        }
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
            // A release must never silently fall back to the Android debug key.
            signingConfig = if (hasPrivateSigning) signingConfigs.getByName("privateRelease") else null
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.exifinterface:exifinterface:1.3.7")
}

val requirePrivateReleaseSigning = tasks.register("requirePrivateReleaseSigning") {
    doLast {
        check(hasPrivateSigning) {
            "Private release signing is required. Configure all four Android signing secrets; no debug fallback is allowed."
        }
    }
}
tasks.configureEach {
    if (name == "assembleRelease" || name == "packageRelease" || name == "validateSigningRelease") {
        dependsOn(requirePrivateReleaseSigning)
    }
}
