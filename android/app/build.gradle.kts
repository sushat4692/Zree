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

    sourceSets {
        getByName("main") {
            // uniffi-generated Kotlin bindings
            java.srcDir("../core-bindings")
            // libzree_core.so goes here, per ABI
            jniLibs.srcDir("src/main/jniLibs")
        }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.09.00")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    // uniffi's generated Kotlin uses JNA to reach the Rust library
    implementation("net.java.dev.jna:jna:5.17.0@aar")
}
