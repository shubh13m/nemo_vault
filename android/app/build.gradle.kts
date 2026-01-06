plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.nemo_vault"
    compileSdk = 36 

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        applicationId = "com.example.nemo_vault"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    buildTypes {
        getByName("release") {
            // Using debug keys for now as per Nemo Vault Phase 2 staging
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

subprojects {
    afterEvaluate {
        val project = this
        if (project.extensions.findByName("android") != null) {
            configure<com.android.build.gradle.BaseExtension> {
                compileSdkVersion(36)
                
                // Fix for the 'Daemon compilation failed' / AssertionError:
                // If a plugin hasn't defined a namespace, we use its project name
                if (namespace == null) {
                    namespace = "com.example.nemo_vault.${project.name.replace("-", "_")}"
                }

                compileOptions {
                    setSourceCompatibility(JavaVersion.VERSION_17)
                    setTargetCompatibility(JavaVersion.VERSION_17)
                }
            }
        }

        project.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                // Adds a safety buffer for incremental compilation
                freeCompilerArgs.add("-Xno-call-assertions")
            }
        }
    }
}