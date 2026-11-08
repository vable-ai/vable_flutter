allprojects {
    repositories {
        // To try an unreleased Android SDK: publishToMavenLocal in vable-android, then
        // build with VABLE_ANDROID_LOCAL=1
        if (System.getenv("VABLE_ANDROID_LOCAL") == "1") mavenLocal()
        google()
        mavenCentral()
        maven {
            name = "GitHubPackages"
            url = uri("https://maven.pkg.github.com/vable-ai/mobile-sdk")
            credentials {
                username = "ci@vable.ai"
                password = System.getenv("GITHUB_TOKEN")
            }
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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
