plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val flutterAbiByPlatform = mapOf(
    "android-arm" to "armeabi-v7a",
    "android-arm64" to "arm64-v8a",
    "android-x64" to "x86_64",
)
val requestedAbis = (findProperty("target-platform") as? String
    ?: "android-arm,android-arm64,android-x64").split(",").map { platform ->
    flutterAbiByPlatform[platform] ?: error("Unsupported Flutter target-platform: $platform")
}
val splitPerAbi = (findProperty("split-per-abi") as? String).toBoolean()

android {
    namespace = "com.example.duoscene"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.duoscene"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 固定 Playra libmpv 引用 Vulkan 1.1 的导出符号，实际最低为 Android 9。
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        configureEach {
            // Flutter 在 buildType 预填 ABI，必须在此替换；仅改 defaultConfig 会被合并成更多架构。
            // 分 ABI 输出由 Flutter splits 管理，不能同时设置两套筛选。
            if (!splitPerAbi) {
                ndk.abiFilters.clear()
                ndk.abiFilters.addAll(requestedAbis)
            }
        }
        release {
            // 正式签名配置由发布切片提供，禁止把 debug 签名作为发行配置。
        }
    }
    packaging {
        jniLibs {
            // 新插件 AAR 可重新带入不完整的 32 位目录，安装器会误认为该 ABI 可运行。
            if (!splitPerAbi) {
                flutterAbiByPlatform.values.filterNot { it in requestedAbis }.forEach {
                    excludes.add("**/$it/**")
                }
            }
        }
    }
}

flutter {
    source = "../.."
}
