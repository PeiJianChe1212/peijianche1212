import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun env(name: String): String? = System.getenv(name)

val releaseStorePath = env("PEILINK_KEYSTORE_FILE") ?: keystoreProperties.getProperty("storeFile")
val releaseStorePassword = env("PEILINK_KEYSTORE_PASSWORD") ?: keystoreProperties.getProperty("storePassword")
val releaseKeyAlias = env("PEILINK_KEY_ALIAS") ?: keystoreProperties.getProperty("keyAlias")
val releaseKeyPassword = env("PEILINK_KEY_PASSWORD") ?: keystoreProperties.getProperty("keyPassword")

val hasReleaseSigning =
    !releaseStorePath.isNullOrBlank() &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

val requestedRelease = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}

if (!hasReleaseSigning && requestedRelease) {
    throw GradleException(
        "正式 release 需要签名配置：请在 android/key.properties 填写 storeFile/storePassword/keyAlias/keyPassword，" +
            "或设置 PEILINK_KEYSTORE_FILE / PEILINK_KEYSTORE_PASSWORD / PEILINK_KEY_ALIAS / PEILINK_KEY_PASSWORD。" +
            "禁止回退到 debug 签名。"
    )
}

android {
    namespace = "com.peilink.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.peilink.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "PeiLink"
    }

    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationId = "com.peilink.dev"
            manifestPlaceholders["appLabel"] = "PeiLink Dev"
        }
        create("user") {
            dimension = "environment"
            applicationId = "com.peilink.app"
            manifestPlaceholders["appLabel"] = "PeiLink"
        }
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = rootProject.file(releaseStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
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