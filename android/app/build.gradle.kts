import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
   
}
 val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
 if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val kotlinVersion = "2.2.20"

// Flutter SDK yo‘lini o‘qish
val flutterSdk = rootProject.file("local.properties").let { file ->
    Properties().apply {
        load(FileInputStream(file))
    }.getProperty("flutter.sdk")
}

android {
    namespace = "uz.mrlg.riyaplay"
    compileSdk = 36
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("libs")
        }
    }
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    defaultConfig {
        applicationId = "uz.mrlg.riyaplay"
        minSdk = 26
        targetSdk = 34
        // pubspec.yaml dagi `version:` dan olinadi (1.0.0+1 -> name 1.0.0, code 1).
        // Qattiq yozilsa, versiyani oshirishda ikki joyni almashtirish kerak bo'ladi.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    buildTypes {
    // Debug build alohida paket sifatida o'rnatiladi, shunda qurilmadagi
    // release ilova va undagi sessiya tegilmay qoladi.
    getByName("debug") {
        applicationIdSuffix = ".debug"
        versionNameSuffix = "-debug"
    }
    getByName("release") {
        isMinifyEnabled = true
        isShrinkResources = true
        signingConfig = signingConfigs.getByName("release")
        proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
    }
}
    
    
    compileOptions {
        // ota_update talab qiladi: u minSdk'dan yuqori java.time API'laridan
        // foydalanadi, desugaring ularni eski Android'larga moslaydi.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    
    lint {
        abortOnError = false // Lint xatoliklari buildni to‘xtatmaydi
        checkReleaseBuilds = false // Release buildlarda lint o‘chiriladi
    }
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib:$kotlinVersion")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Dublikat sinflarni oldini olish uchun
configurations.all {
    resolutionStrategy {
        force("org.jetbrains.kotlin:kotlin-stdlib:$kotlinVersion")
        force("org.jetbrains.kotlin:kotlin-stdlib-jdk7:$kotlinVersion")
        force("org.jetbrains.kotlin:kotlin-stdlib-jdk8:$kotlinVersion")
    }
}