buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Bắt buộc: Đăng ký plugin Google Services để Gradle có thể dịch file google-services.json
        classpath("com.google.gms:google-services:4.4.1")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")

    val configureJvm = {
        // In log ra màn hình Console để theo dõi trực tiếp dòng chảy của Gradle
        println("=> [AI LOG] Ép đồng bộ JVM 17 cho plugin/module: ${project.name}")
        
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }

        tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
        }
    }

    // Chiến lược kiểm tra an toàn: Nếu chạy rồi thì thực thi ngay, nếu chưa thì mới treo hook
    if (project.state.executed) {
        configureJvm()
    } else {
        project.afterEvaluate { configureJvm() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Block xử lý ép compileSdk = 36 cho tất cả các plugins để tránh lỗi không tương thích AndroidX
subprojects {
    val configureAndroid = {
        if (plugins.hasPlugin("com.android.application") || plugins.hasPlugin("com.android.library")) {
            val androidExtension = extensions.findByName("android")
            if (androidExtension != null) {
                try {
                    // Sửa lỗi logic: Chỉ bắt chính xác hàm Setter (setCompileSdk), có đúng 1 tham số
                    val setMethod = androidExtension.javaClass.methods.firstOrNull { 
                        it.name == "setCompileSdk" && it.parameterCount == 1 
                    }
                    setMethod?.invoke(androidExtension, 36)
                    println("=> [AI LOG] Đã nâng cấp compileSdk=36 thành công cho: ${project.name}")
                } catch (ex: Exception) {
                    println("=> [AI LOG] Bỏ qua ép compileSdk cho ${project.name} (Không tìm thấy setter API)")
                }
            }
        }
    }

    if (project.state.executed) {
        configureAndroid()
    } else {
        project.afterEvaluate { configureAndroid() }
    }
}