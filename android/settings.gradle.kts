pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")

// Patch flutter_inappwebview_android for AGP 9.x compatibility.
// The plugin uses getDefaultProguardFile("proguard-android.txt") which was removed in AGP 9.
val pubCacheDir = System.getenv("PUB_CACHE")?.let { file(it) }
    ?: file("${System.getProperty("user.home")}/.pub-cache")
if (pubCacheDir.exists()) {
    fileTree(pubCacheDir) {
        include("**/flutter_inappwebview_android*/android/build.gradle")
    }.forEach { f ->
        val text = f.readText()
        if (text.contains("getDefaultProguardFile('proguard-android.txt')")) {
            f.writeText(text.replace(
                "getDefaultProguardFile('proguard-android.txt')",
                "getDefaultProguardFile('proguard-android-optimize.txt')"
            ))
            logger.lifecycle("Patched ${f.name} for AGP 9.x")
        }
    }
}
