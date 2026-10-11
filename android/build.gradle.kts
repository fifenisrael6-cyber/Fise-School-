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


// The Android library plugin (notably receive_sharing_intent) configures its
// Java compile tasks to target 11 while Kotlin targets 17. Apply this after all
// project build scripts have configured their variants so the Java target is
// not overwritten by the Android plugin. This avoids afterEvaluate, which
// fails when a subproject has already been evaluated.
gradle.projectsEvaluated {
    rootProject.allprojects.forEach { configuredProject ->
        configuredProject.tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()

            // The printing plugin's Java task currently lacks Android framework
            // classes. Add the installed API jar after plugin task configuration.
            if (configuredProject.name == "printing") {
                val sdkRoot = System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT")
                if (sdkRoot != null) {
                    val androidJar = configuredProject.file("$sdkRoot/platforms/android-36/android.jar")
                    if (androidJar.exists()) {
                        classpath = files(classpath, androidJar)
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
