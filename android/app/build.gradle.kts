plugins {
    id("com.android.application")
    // Flutter 3.32 的 Gradle 插件不会自动应用 Kotlin 插件，
    // 必须显式声明；版本由 android/settings.gradle.kts 统一管理。
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.zipbrowser.zip_browser"
    // flutter_plugin_android_lifecycle 等插件要求 compileSdk >= 36
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.zipbrowser.zip_browser"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Zip Browser：固定 21（Android 5.0）。配套构建链固定 Flutter 3.32.8
        // ——最后一个官方支持 API 21 的稳定版；Android 4.x 的结论见
        // docs/ANDROID_COMPAT.md。
        minSdk = 21
        // Flutter 3.32 的 flutter.targetSdkVersion 是 35，这里显式抬到 36，
        // 保持新设备上的行为与上架要求一致（Android 5 上该值不生效）。
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // ML Kit 插件引用全部脚本识别器，本项目只打包中文库，
            // 由 proguard-rules.pro 忽略其余脚本的缺失类告警。
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // FileProvider：WebView 文件选择器（input[type=file] 相机）需要
    implementation("androidx.core:core-ktx:1.13.1")
    // 文字识别（OCR）中文脚本原生库；lib/services/ocr_service.dart 使用
    // TextRecognitionScript.chinese，缺了它运行时会报脚本识别器缺失。
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
}

flutter {
    source = "../.."
}
