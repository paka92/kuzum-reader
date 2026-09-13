allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Several Flutter plugins still declare compileSdk 34/35, while
// flutter_plugin_android_lifecycle now requires everything depending on it to
// compile against 36. Raise every Android library subproject to 36 so the AAR
// metadata check passes, instead of pinning older plugin versions.
//
// Registered before the evaluationDependsOn block below, which evaluates
// subprojects eagerly — afterEvaluate cannot be added once that has happened.
subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android") ?: return@afterEvaluate
        val target = 36
        val intTypes = setOf(Int::class.javaPrimitiveType, Integer::class.java)
        val setter =
            androidExtension.javaClass.methods.firstOrNull {
                it.name == "setCompileSdk" &&
                    it.parameterTypes.size == 1 &&
                    it.parameterTypes[0] in intTypes
            } ?: androidExtension.javaClass.methods.firstOrNull {
                it.name == "compileSdkVersion" &&
                    it.parameterTypes.size == 1 &&
                    it.parameterTypes[0] in intTypes
            }
        if (setter == null) {
            logger.warn("kuzum_reader: could not raise compileSdk of ${project.name}")
        } else {
            setter.invoke(androidExtension, target)
            logger.info("kuzum_reader: raised compileSdk of ${project.name} to $target")
        }
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
