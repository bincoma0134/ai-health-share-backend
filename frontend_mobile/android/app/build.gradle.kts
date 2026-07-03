plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // Đã mở khóa để Gradle đọc file JSON của Firebase
}

// Cấu hình theo chuẩn AGP mới để loại bỏ cảnh báo Deprecated
configure<com.android.build.api.dsl.ApplicationExtension> {
    namespace = "com.gsx.health.frontend_mobile"
    
    // Đồng bộ compileSdk lên 36 (Android 16) theo yêu cầu bắt buộc của các thư viện androidx mới
    compileSdk = 36 
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true // 🚀 Bổ sung để hỗ trợ Java 8+ API cho flutter_local_notifications
    }  

    defaultConfig {
        applicationId = "com.gsx.health.frontend_mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = 35 // Giữ targetSdk 35 để bảo toàn hành vi runtime ổn định của ứng dụng
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
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

// 🚀 Nạp gói Desugaring theo yêu cầu của thư viện Local Notification
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}