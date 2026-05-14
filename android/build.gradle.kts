// Android AAR module for VodozemacFFI.
//
// Builds `vodozemac-release.aar` containing:
//   - The UniFFI-generated Kotlin bindings (src/main/kotlin/...)
//   - Pre-compiled native libs for arm64-v8a, armeabi-v7a, x86_64
//     (src/main/jniLibs/<abi>/libvodozemac_ffi.so)
//   - The required runtime dependency on JNA (net.java.dev.jna:jna)
//
// `build_aar.sh` orchestrates the .so build + bindings generation BEFORE
// this Gradle build runs — Gradle here is just packaging.

plugins {
    id("com.android.library") version "8.7.3"
    id("org.jetbrains.kotlin.android") version "2.0.21"
}

android {
    namespace = "com.dtelecom.vodozemac"
    compileSdk = 35

    defaultConfig {
        // 24 = Android 7.0 Nougat. Matches React Native 0.84's default
        // minSdk, which is the floor our consumers care about.
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")

        // Tell Android Gradle Plugin which ABIs we ship native libs for.
        // Anything outside this list will be silently dropped at .apk
        // packaging by the consumer's build.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    // Two consumer-facing artifacts: debug + release. We only need
    // release; suppress debug to avoid noise + halve build time.
    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    // Skip producing test fixtures / androidTest variants — the consumer
    // doesn't ship them and this project's own tests live outside Gradle
    // (host-arch validation via kotlinc + JNA, see Tests/).
    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    // UniFFI Kotlin bindings load native code via JNA at runtime.
    // Pinned to ^5.14 (matches what UniFFI 0.31 generates against).
    implementation("net.java.dev.jna:jna:5.14.0@aar")

    // Kotlin standard library — explicit pin to match the kotlin plugin
    // version above; otherwise AGP picks an older transitive.
    implementation(kotlin("stdlib", "2.0.21"))
}
