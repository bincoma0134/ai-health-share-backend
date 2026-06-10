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
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Block xử lý ép compileSdk = 36 cho tất cả các plugins để tránh lỗi không tương thích
subprojects {
    val configureAndroid = {
        if (plugins.hasPlugin("com.android.application") || plugins.hasPlugin("com.android.library")) {
            val androidExtension = extensions.findByName("android")
            if (androidExtension != null) {
                try {
                    (androidExtension as? com.android.build.gradle.BaseExtension)?.compileSdkVersion(36)
                } catch (e: Exception) {
                    try {
                        val method = androidExtension::class.java.methods.firstOrNull { it.name == "setCompileSdk" || it.name == "compileSdk" }
                        method?.invoke(androidExtension, 36)
                    } catch (ex: Exception) {
                        // Bỏ qua nếu không can thiệp được cấu hình động
                    }
                }
            }
        }
    }

    // Nếu dự án đã được đánh giá (due to evaluationDependsOn), thực thi cấu hình ngay lập tức
    if (project.state.executed) {
        configureAndroid()
    } else {
        // Nếu chưa, đợi vòng đời sau khi đánh giá kết thúc một cách an toàn
        project.afterEvaluate { configureAndroid() }
    }
}