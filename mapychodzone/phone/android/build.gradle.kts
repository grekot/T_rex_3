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
// maplibre_gl 0.25+ ustawia Javę i Kotlina na 21, a na tym PC i we wspólnym workflow sklepu
// (setup-java 17) jest JDK 17. Kod wtyczki nie używa niczego z Javy 18+, więc kompilujemy go
// jako Javę 17. Do usunięcia, gdy przejdziemy na JDK 21 (lokalnie i w App_storage).
fun javaSiedemnascie(p: Project) {
    p.extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.compileOptions?.apply {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    p.tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
        compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
subprojects {
    if (name == "maplibre_gl") {
        if (state.executed) javaSiedemnascie(this) else afterEvaluate { javaSiedemnascie(this) }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
