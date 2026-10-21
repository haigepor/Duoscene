import java.net.URI
import java.util.Base64

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

val dartDefines = (findProperty("dart-defines") as? String).orEmpty()
    .split(",").filter { it.isNotBlank() }.mapNotNull { encoded ->
        val entry = String(Base64.getDecoder().decode(encoded), Charsets.UTF_8).split("=", limit = 2)
        if (entry.size == 2) entry[0] to entry[1] else null
    }.toMap()
val lanOrigin = if (dartDefines["ALLOW_LAN_HTTP"] == "true") {
    runCatching { URI(dartDefines["API_BASE_URL"].orEmpty()) }.getOrNull()
} else null
val lanOctets = lanOrigin?.host?.split(".")?.map { it.toIntOrNull() }.orEmpty()
val privateLanHost = lanOctets.size == 4 && lanOctets.all { it != null && it in 0..255 } &&
    (lanOctets[0] == 10 || lanOctets[0] == 192 && lanOctets[1] == 168 ||
        lanOctets[0] == 172 && lanOctets[1]!! in 16..31)
val lanResources = if (lanOrigin?.scheme == "http" && privateLanHost) {
    val generated = layout.buildDirectory.dir("generated/duosceneLanDebugResources")
    val generateLanResources = tasks.register("generateDuosceneLanDebugResources") {
        inputs.dir("src/debug/res")
        inputs.property("apiHost", lanOrigin.host)
        outputs.dir(generated)
        doLast {
            copy { from("src/debug/res"); into(generated) }
            val xml = generated.get().file("xml/provider_network_security.xml").asFile
            // 仅生成 Debug/Profile 覆盖资源，精确放行本次构建的局域网地址；Release 不变。
            xml.writeText(xml.readText(Charsets.UTF_8).replace("</domain-config>", "    <domain includeSubdomains=\"false\">${lanOrigin.host}</domain>\n    </domain-config>"), Charsets.UTF_8)
        }
    }
    tasks.matching { it.name == "preDebugBuild" || it.name == "preProfileBuild" }.configureEach { dependsOn(generateLanResources) }
    generated
} else null

android {
    namespace = "com.example.duoscene"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    if (lanResources != null) {
        sourceSets.getByName("debug").res.setSrcDirs(listOf(lanResources))
        sourceSets.maybeCreate("profile").res.setSrcDirs(listOf(lanResources))
    }

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
