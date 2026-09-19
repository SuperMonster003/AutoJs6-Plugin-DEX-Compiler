import com.android.build.api.variant.FilterConfiguration
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID
import org.gradle.api.file.DuplicatesStrategy
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.file.RelativePath
import org.gradle.api.provider.Property
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.testing.Test
import org.gradle.process.CommandLineArgumentProvider

abstract class D8MatrixAndroidJarArgumentProvider : CommandLineArgumentProvider {
    @get:InputFile
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val androidJar: RegularFileProperty

    override fun asArguments(): Iterable<String> =
        listOf("-Dd8.matrix.androidJar=${androidJar.get().asFile.absolutePath}")
}

fun writeInvalidatedR4Gate(
    outputFile: File,
    schemaVersion: String,
    evidenceBoundary: String,
    reason: String,
) {
    require(outputFile.parentFile.mkdirs() || outputFile.parentFile.isDirectory) {
        "Could not create R4 gate output directory"
    }
    val temporaryFile = outputFile.parentFile.resolve(
        ".${outputFile.name}.${UUID.randomUUID()}.tmp",
    )
    val failureJson = """
        {
          "schemaVersion": "$schemaVersion",
          "passed": false,
          "evidenceBoundary": "$evidenceBoundary",
          "summary": "$reason"
        }
    """.trimIndent() + "\n"
    try {
        temporaryFile.writeText(failureJson, Charsets.UTF_8)
        try {
            Files.move(
                temporaryFile.toPath(),
                outputFile.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING,
            )
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(
                temporaryFile.toPath(),
                outputFile.toPath(),
                StandardCopyOption.REPLACE_EXISTING,
            )
        }
    } finally {
        Files.deleteIfExists(temporaryFile.toPath())
    }
}

plugins {
    id("io.github.supermonster003.autojs6-native-alignment")
    id("org.autojs.build.utils")
    id("org.autojs.build.versions")
    id("org.autojs.build.signs")
    id("org.autojs.build.jvm-convention")
    id("com.android.application")
}

val globalApplicationId = "io.github.supermonster003.autojs6.plugin.dexcompiler"
val buildTypeDebug = "debug"
val buildTypeRelease = "release"
val pinnedD8Version = libs.versions.r8.get()
val d8CandidateVersion = providers.gradleProperty("d8CandidateVersion")
val d8RollbackEvaluation = providers.gradleProperty("d8RollbackEvaluation")
    .map { it.toBooleanStrict() }
    .orElse(false)
require(!(d8CandidateVersion.isPresent && d8RollbackEvaluation.get())) {
    "d8CandidateVersion and d8RollbackEvaluation are mutually exclusive"
}
val selectedD8Version = d8CandidateVersion.orElse(pinnedD8Version)
val kotlinCompilerVersion = requireNotNull(
    org.jetbrains.kotlin.gradle.plugin.KotlinBasePluginWrapper::class.java.`package`.implementationVersion,
).substringBefore("-release")
val r4D8UpgradeMatrixTestTaskName = "r4D8UpgradeMatrixTest"
val r4D8UpgradeInvocationId = UUID.randomUUID().toString()
val r4D8UpgradeReportRootDirectory = layout.buildDirectory.dir(
    "reports/d8-upgrade-matrix/${selectedD8Version.get()}",
)
val r4D8UpgradeReportDirectory = r4D8UpgradeReportRootDirectory.map {
    it.dir("invocations/$r4D8UpgradeInvocationId/$r4D8UpgradeMatrixTestTaskName")
}
val r4D8UpgradeGateOutput = r4D8UpgradeReportRootDirectory.map {
    it.file("gate-$r4D8UpgradeMatrixTestTaskName.json")
}

android {
    namespace = globalApplicationId
    compileSdk = versions.sdkVersionCompile

    defaultConfig {
        applicationId = globalApplicationId
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        minSdk = versions.sdkVersionMin
        targetSdk = versions.sdkVersionTarget
        versionCode = versions.appVersionCode
        versionName = versions.appVersionName

        buildConfigField("String", "D8_COMPILER_VERSION", "\"${selectedD8Version.get()}\"")
        resValue("string", "plugin_author", "SuperMonster003")
        resValue("string", "plugin_version_date", utils.getDateString("MMM d, yyyy", "GMT+08:00"))
    }

    lint {
        abortOnError = true
    }

    signingConfigs {
        if (signs.isValid) {
            create(buildTypeRelease) {
                storeFile = signs.properties["storeFile"]?.let { file(it as String) }
                keyPassword = signs.properties["keyPassword"] as String
                keyAlias = signs.properties["keyAlias"] as String
                storePassword = signs.properties["storePassword"] as String
            }
        }
    }

    buildTypes {
        val proguardFiles = arrayOf<Any>(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro",
        )
        val niceSigningConfig = takeIf { signs.isValid }?.let {
            signingConfigs.getByName(buildTypeRelease)
        }
        debug {
            isMinifyEnabled = false
            proguardFiles(*proguardFiles)
            niceSigningConfig?.let { signingConfig = it }
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(*proguardFiles)
            niceSigningConfig?.let { signingConfig = it }
        }
    }

    buildFeatures {
        aidl = true
        buildConfig = true
        resValues = true
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }

    sourceSets.named("main") {
        kotlin.directories += "src/main/java"
    }

    packaging {
        resources.pickFirsts.addAll(
            listOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.*",
                "META-INF/NOTICE",
                "META-INF/NOTICE.*",
                "META-INF/*.kotlin_module",
            ),
        )
    }

    bundle {
        language.enableSplit = false
        density.enableSplit = false
        abi.enableSplit = false
    }
}

androidComponents {
    onVariants { variant ->
        variant.outputs.forEach { output ->
            val architecture = output.filters.find {
                it.filterType == FilterConfiguration.FilterType.ABI
            }?.identifier
            val outputFileNameProperty = output.javaClass.methods.firstOrNull {
                it.name == "getOutputFileName" && it.parameterTypes.isEmpty()
            }?.invoke(output) as? Property<*>

            @Suppress("UNCHECKED_CAST")
            (outputFileNameProperty as? Property<String>)?.set(
                output.versionName.map { versionName ->
                    val version = versionName.replace("\\s".toRegex(), "-")
                    val abiSuffix = architecture?.let { "-$it" }.orEmpty()
                    "${rootProject.name}-v$version$abiSuffix.${utils.FILE_EXTENSION_APK}".lowercase()
                },
            )
        }
    }
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib:2.2.21")
    //noinspection UseTomlInstead -- the coordinate is fixed here while R4 explicitly overrides only its version.
    implementation("com.android.tools:r8:${selectedD8Version.get()}")
    coreLibraryDesugaring(libs.desugar)

    implementation(files("$rootDir/libs/common-plugin-api.aar"))
    implementation(files("$rootDir/libs/protocol-wire-api.aar"))
    implementation(files("$rootDir/libs/dex-compiler-api.aar"))

    testImplementation(libs.junit)
    androidTestImplementation(libs.test.ext.junit)
    androidTestImplementation(libs.test.runner)
    testImplementation(libs.gson)
}

tasks {
    withType(JavaCompile::class.java) {
        options.encoding = "UTF-8"
    }

    providers.gradleProperty("r0TestMaxHeap").orNull?.let { constrainedHeap ->
        withType(Test::class.java).configureEach {
            maxHeapSize = constrainedHeap
            systemProperty("r0.test.maxHeap", constrainedHeap)
        }
    }

    // The platform jar AGP compiles against: resolved through the boot classpath instead of a hand-built
    // `platforms/android-<level>` path, because minor platform releases live in `android-37.0`-style folders.
    // Defer the getter too: AGP 9.1 checks targetCompatibility before returning its Provider.
    val platformAndroidJar = providers.provider {
        androidComponents.sdkComponents.bootClasspath
    }.flatMap { it }.map { entries ->
        entries.first { it.asFile.name == "android.jar" }
    }

    withType(Test::class.java).configureEach {
        val taskReportDirectory = if (name == r4D8UpgradeMatrixTestTaskName) {
            r4D8UpgradeReportDirectory
        } else {
            layout.buildDirectory.dir("reports/d8-upgrade-matrix/${selectedD8Version.get()}/$name")
        }
        systemProperty("d8.matrix.declaredVersion", selectedD8Version.get())
        systemProperty("d8.matrix.pinnedVersion", pinnedD8Version)
        systemProperty("d8.matrix.candidateEvaluation", d8CandidateVersion.isPresent.toString())
        systemProperty("d8.matrix.rollbackEvaluation", d8RollbackEvaluation.get().toString())
        systemProperty("d8.matrix.producerInvocationId", r4D8UpgradeInvocationId)
        systemProperty("d8.matrix.kotlinCompilerVersion", kotlinCompilerVersion)
        systemProperty(
            "d8.matrix.manifestPath",
            rootProject.file("scripts/r4-d8-upgrade/r4-d8-upgrade-matrix.json").absolutePath,
        )
        jvmArgumentProviders.add(objects.newInstance<D8MatrixAndroidJarArgumentProvider>().apply {
            androidJar.set(platformAndroidJar)
        })
        systemProperty(
            "d8.matrix.reportDirectory",
            taskReportDirectory.get().asFile.absolutePath,
        )
        inputs.file(rootProject.file("scripts/r4-d8-upgrade/r4-d8-upgrade-matrix.json"))
        inputs.property("d8MatrixDeclaredVersion", selectedD8Version.get())
        inputs.property("d8MatrixPinnedVersion", pinnedD8Version)
        inputs.property("d8MatrixCandidateEvaluation", d8CandidateVersion.isPresent)
        inputs.property("d8MatrixRollbackEvaluation", d8RollbackEvaluation.get())
        inputs.property("d8MatrixProducerInvocationId", r4D8UpgradeInvocationId)
        inputs.property("d8MatrixKotlinCompilerVersion", kotlinCompilerVersion)
        outputs.dir(taskReportDirectory)
        outputs.upToDateWhen { false }
        outputs.doNotCacheIf("R4 D8 matrix reports are fresh observations, not reusable build artifacts") { true }
    }

    val prepareR4D8UpgradeMatrix = register("prepareR4D8UpgradeMatrix") {
        group = "verification"
        description = "Invalidates prior R4.1 matrix evidence before a fresh producer invocation"
        outputs.upToDateWhen { false }
        doLast {
            writeInvalidatedR4Gate(
                outputFile = r4D8UpgradeGateOutput.get().asFile,
                schemaVersion = "autojs6.dex.r4.d8-upgrade-gate/v3",
                evidenceBoundary = "JVM_COMPILER_ONLY",
                reason = "INVALIDATED_BEFORE_PRODUCER_INVOCATION",
            )
            val invocationDirectory = r4D8UpgradeReportDirectory.get().asFile
            require(!invocationDirectory.exists()) {
                "Fresh R4 D8 matrix invocation directory already exists"
            }
            require(invocationDirectory.mkdirs()) {
                "Could not create fresh R4 D8 matrix report directory"
            }
        }
    }

    val r4D8UpgradeMatrixTest = register<Test>(r4D8UpgradeMatrixTestTaskName) {
        group = "verification"
        description = "Runs only the fresh R4.1 D8 upgrade matrix producer"
        dependsOn(prepareR4D8UpgradeMatrix)
        filter {
            includeTestsMatching(
                "io.github.supermonster003.autojs6.plugin.dexcompiler.D8UpgradeMatrixTest",
            )
            isFailOnNoMatchingTests = true
        }
    }

    val verifyR4D8UpgradeMatrix = register<Exec>("verifyR4D8UpgradeMatrix") {
        group = "verification"
        description = "Runs and verifies the local-only R4.1 D8 compiler upgrade matrix"
        dependsOn(r4D8UpgradeMatrixTest)
        inputs.files(fileTree(r4D8UpgradeReportDirectory) {
            include("*.json")
        })
        inputs.files(
            rootProject.fileTree("scripts/r4-d8-upgrade") {
                include("r4-d8-upgrade-matrix.json")
                include("r4-d8-upgrade-matrix.schema.json")
                include("r4-d8-upgrade-report.schema.json")
                include("R4D8UpgradeGate.psm1")
                include("verify-r4-d8-upgrade.ps1")
            },
        )
        inputs.property("d8MatrixExpectedProducerInvocationId", r4D8UpgradeInvocationId)
        outputs.file(r4D8UpgradeGateOutput)
        outputs.upToDateWhen { false }
        outputs.doNotCacheIf("R4 D8 matrix gates are fresh invocation-bound observations") { true }
        doFirst {
            val reportDirectory = r4D8UpgradeReportDirectory.get().asFile
            val reportCount = reportDirectory
                .listFiles { file -> file.isFile && file.name.endsWith(".json") && file.name != "gate.json" }
                ?.size
                ?: 0
            require(reportCount > 0) { "R4 D8 upgrade matrix produced no reports" }
            val gateArguments = mutableListOf(
                "pwsh", "-NoLogo", "-NoProfile", "-File",
                rootProject.file("scripts/r4-d8-upgrade/verify-r4-d8-upgrade.ps1").absolutePath,
                "-ExpectedCompilerVersion", selectedD8Version.get(),
                "-ExpectedProducerInvocationId", r4D8UpgradeInvocationId,
                "-OutputPath", r4D8UpgradeGateOutput.get().asFile.absolutePath,
                "-ReportDirectory", reportDirectory.absolutePath,
            )
            if (d8CandidateVersion.isPresent) {
                gateArguments += "-CandidateEvaluation"
            }
            if (d8RollbackEvaluation.get()) {
                gateArguments += "-RollbackEvaluation"
            }
            commandLine(gateArguments)
        }
    }

    val r4R8BoundaryGateOutput = layout.buildDirectory.file("reports/r8-boundary/gate.json")
    val prepareR4R8Boundary = register("prepareR4R8Boundary") {
        group = "verification"
        description = "Invalidates prior R4.2 boundary evidence before JVM verification"
        outputs.upToDateWhen { false }
        doLast {
            writeInvalidatedR4Gate(
                outputFile = r4R8BoundaryGateOutput.get().asFile,
                schemaVersion = "autojs6.dex.r4.r8-boundary-gate/v1",
                evidenceBoundary = "SOURCE_STATIC_ONLY",
                reason = "INVALIDATED_BEFORE_JVM_VERIFICATION",
            )
        }
    }
    val verifyR4R8Boundary = register<Exec>("verifyR4R8Boundary") {
        group = "verification"
        description = "Runs the local-only R4.2 D8 RELEASE/R8 separation gate"
        dependsOn(prepareR4R8Boundary, "testDebugUnitTest")
        inputs.files(
            rootProject.fileTree("scripts/r4-r8-boundary") {
                include("*.json")
                include("*.ps1")
                include("*.psm1")
                include("README.md")
            },
        )
        inputs.files(
            rootProject.file("app/src/main/AndroidManifest.xml"),
            rootProject.file(
                "app/src/main/java/io/github/supermonster003/autojs6/plugin/dexcompiler/D8DexCompilerEngine.kt",
            ),
            rootProject.file(
                "app/src/main/java/io/github/supermonster003/autojs6/plugin/dexcompiler/DexCompilerPluginInfoService.kt",
            ),
            rootProject.file(
                "app/src/main/java/io/github/supermonster003/autojs6/plugin/dexcompiler/DexCompilerRuntime.kt",
            ),
            rootProject.file(
                "app/src/main/java/io/github/supermonster003/autojs6/plugin/dexcompiler/service/RemoteDexCompileSession.kt",
            ),
            rootProject.file("app/build.gradle.kts"),
            rootProject.file("libs/dex-compiler-api.aar"),
            rootProject.file("README.md"),
        )
        outputs.file(r4R8BoundaryGateOutput)
        outputs.upToDateWhen { false }
        outputs.doNotCacheIf("R4.2 boundary reports are fresh source observations") { true }
        doFirst {
            commandLine(
                "pwsh", "-NoLogo", "-NoProfile", "-File",
                rootProject.file("scripts/r4-r8-boundary/verify-r4-r8-boundary.ps1").absolutePath,
                "-RepositoryRoot", rootProject.projectDir.absolutePath,
                "-OutputPath", r4R8BoundaryGateOutput.get().asFile.absolutePath,
            )
        }
    }

    val r4OtherCapabilitiesGateOutput = layout.buildDirectory.file("reports/other-capabilities/gate.json")
    val prepareR4OtherCapabilities = register("prepareR4OtherCapabilities") {
        group = "verification"
        description = "Invalidates prior R4.3 responsibility evidence before JVM verification"
        outputs.upToDateWhen { false }
        doLast {
            writeInvalidatedR4Gate(
                outputFile = r4OtherCapabilitiesGateOutput.get().asFile,
                schemaVersion = "autojs6.dex.r4.other-capabilities-gate/v1",
                evidenceBoundary = "STATIC_PRODUCTION_CAPABILITY_AND_BUILD_LAYER_SEPARATION",
                reason = "INVALIDATED_BEFORE_JVM_VERIFICATION",
            )
        }
    }
    val verifyR4OtherCapabilities = register<Exec>("verifyR4OtherCapabilities") {
        group = "verification"
        description = "Runs the R4.3 source/compiler and packaging responsibility boundary gate"
        dependsOn(prepareR4OtherCapabilities, "testDebugUnitTest")
        inputs.files(
            rootProject.fileTree("scripts/r4-other-capabilities") {
                include("*.json")
                include("*.ps1")
                include("*.psm1")
                include("README.md")
            },
            rootProject.fileTree("app/src/main/java") {
                include("**/*.kt")
                include("**/*.java")
            },
            rootProject.file("app/src/main/AndroidManifest.xml"),
            rootProject.file("app/build.gradle.kts"),
            rootProject.file("libs/dex-compiler-api.aar"),
        )
        outputs.file(r4OtherCapabilitiesGateOutput)
        outputs.upToDateWhen { false }
        outputs.doNotCacheIf("R4.3 responsibility reports are fresh source observations") { true }
        doFirst {
            commandLine(
                "pwsh", "-NoLogo", "-NoProfile", "-File",
                rootProject.file(
                    "scripts/r4-other-capabilities/verify-r4-other-capabilities.ps1",
                ).absolutePath,
                "-RepositoryRoot", rootProject.projectDir.absolutePath,
                "-OutputPath", r4OtherCapabilitiesGateOutput.get().asFile.absolutePath,
            )
        }
    }

    gradle.taskGraph.whenReady {
        if (hasTask(verifyR4D8UpgradeMatrix.get())) {
            writeInvalidatedR4Gate(
                outputFile = r4D8UpgradeGateOutput.get().asFile,
                schemaVersion = "autojs6.dex.r4.d8-upgrade-gate/v3",
                evidenceBoundary = "JVM_COMPILER_ONLY",
                reason = "INVALIDATED_BEFORE_TASK_GRAPH_EXECUTION",
            )
        }
        if (hasTask(verifyR4R8Boundary.get())) {
            writeInvalidatedR4Gate(
                outputFile = r4R8BoundaryGateOutput.get().asFile,
                schemaVersion = "autojs6.dex.r4.r8-boundary-gate/v1",
                evidenceBoundary = "SOURCE_STATIC_ONLY",
                reason = "INVALIDATED_BEFORE_TASK_GRAPH_EXECUTION",
            )
        }
        if (hasTask(verifyR4OtherCapabilities.get())) {
            writeInvalidatedR4Gate(
                outputFile = r4OtherCapabilitiesGateOutput.get().asFile,
                schemaVersion = "autojs6.dex.r4.other-capabilities-gate/v1",
                evidenceBoundary = "STATIC_PRODUCTION_CAPABILITY_AND_BUILD_LAYER_SEPARATION",
                reason = "INVALIDATED_BEFORE_TASK_GRAPH_EXECUTION",
            )
        }
    }


}

afterEvaluate {
    val debugUnitTest = tasks.named<Test>("testDebugUnitTest")
    tasks.named<Test>(r4D8UpgradeMatrixTestTaskName).configure {
        testClassesDirs = debugUnitTest.get().testClassesDirs
        classpath = debugUnitTest.get().classpath
    }
    debugUnitTest.configure {
        mustRunAfter("prepareR4R8Boundary", "prepareR4OtherCapabilities")
    }
}

extra {
    versions.handleIfNeeded(project, "", listOf(buildTypeDebug, buildTypeRelease))
}

// Reject accidental native dependencies on every ABI.
nativeAlignment { expectNoNativeLibraries.set(true) }

apply(from = rootProject.file("gradle/release-archive.gradle"))
