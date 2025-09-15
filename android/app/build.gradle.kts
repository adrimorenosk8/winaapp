// android/app/build.gradle.kts

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin") // correcto aquí
}

android {
    namespace = "com.wina.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.wina.app"
        minSdk = flutter.minSdkVersion            // 👈 Kotlin DSL: minSdk =
        targetSdk = flutter.targetSdkVersion      // 👈 Kotlin DSL: targetSdk =
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Java 17 + desugaring para API < 26 (requerido por flutter_local_notifications)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true     // 👈 importante
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildTypes {
        release {
            // cambia a tu config de firma cuando la tengas
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ Desugaring libs
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // 🔥 Firebase BOM (controla las versiones)
    implementation(platform("com.google.firebase:firebase-bom:33.1.2"))

    // Firebase que ya usas
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")

    // ✅ FCM para push (lo añadimos si aún no estaba)
    implementation("com.google.firebase:firebase-messaging")
}
