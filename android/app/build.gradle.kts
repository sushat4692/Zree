plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "im.sush.zree"
    compileSdk = 35

    defaultConfig {
        applicationId = "im.sush.zree"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        // arm64 only for now; add x86_64 if we ever run an emulator
        ndk { abiFilters += listOf("arm64-v8a") }
    }

    buildFeatures { compose = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    testOptions {
        unitTests.all {
            // JVM tests run on the host, so point JNA at the macOS build of the core
            val coreLib = rootProject.projectDir.parentFile.resolve("target/release").absolutePath
            it.systemProperty("jna.library.path", coreLib)
            it.systemProperty("java.library.path", coreLib)
        }
    }

    sourceSets {
        getByName("main") {
            // uniffi-generated Kotlin bindings
            java.srcDir("../core-bindings")
            // libzree_core.so goes here, per ABI
            jniLibs.srcDir("src/main/jniLibs")
        }
    }
}

// An out-of-date libzree_core.so fails at runtime with a confusing
// "NoClassDefFoundError: uniffi.zree_core.UniffiLib" (uniffi's checksum guard).
// Fail the build instead, with the command to run.
val coreSrc = rootProject.projectDir.parentFile.resolve("core/src")
val coreSo = file("src/main/jniLibs/arm64-v8a/libzree_core.so")

tasks.register("checkCoreFreshness") {
    doLast {
        if (!coreSo.exists()) {
            throw GradleException("libzree_core.so missing — run android/scripts/build-core.sh")
        }
        val newestSource = coreSrc.walkTopDown()
            .filter { it.isFile && it.extension == "rs" }
            .maxOfOrNull { it.lastModified() } ?: 0L
        if (newestSource > coreSo.lastModified()) {
            throw GradleException(
                "libzree_core.so is older than core/src — run android/scripts/build-core.sh " +
                    "(and regenerate the Kotlin bindings if the FFI changed)"
            )
        }
    }
}

tasks.named("preBuild") { dependsOn("checkCoreFreshness") }

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.09.00")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.6")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("androidx.documentfile:documentfile:1.0.1")
    testImplementation("junit:junit:4.13.2")
    // the desktop jar carries libjnidispatch for the host JVM
    testImplementation("net.java.dev.jna:jna:5.17.0")
    implementation("androidx.core:core-splashscreen:1.0.1")
    // uniffi's generated Kotlin uses JNA to reach the Rust library
    implementation("net.java.dev.jna:jna:5.17.0@aar")
}
