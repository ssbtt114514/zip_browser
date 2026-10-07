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

    // >>> zip_browser compileSdk pin >>>
    // 强制插件子模块使用 compileSdk 36：部分插件硬编码了较低版本，
    // 但其依赖要求 36，否则 checkReleaseAarMetadata 失败。
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        when (androidExt) {
            is com.android.build.gradle.LibraryExtension ->
                androidExt.compileSdkVersion(36)
            is com.android.build.gradle.AppExtension ->
                androidExt.compileSdkVersion(36)
        }
    }
    // <<< zip_browser compileSdk pin <<<

    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
