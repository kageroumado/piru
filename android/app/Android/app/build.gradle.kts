
plugins {
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.android.application)
    id("skip-build-plugin")
}

skip {
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(libs.versions.jvm.get().toString())
    }
}

android {
    namespace = group as String
    compileSdk = libs.versions.android.sdk.compile.get().toInt()
    compileOptions {
        sourceCompatibility = JavaVersion.toVersion(libs.versions.jvm.get())
        targetCompatibility = JavaVersion.toVersion(libs.versions.jvm.get())
    }
    packaging {
        jniLibs {
            keepDebugSymbols.add("**/*.so")
            pickFirsts.add("**/*.so")
            // this option would compress JNI .so files and reduce overall size for Skip Fuse apps, but cost more at install time
            //useLegacyPackaging = true
        }
    }

    // Stored uncompressed, the catalog copies out of the APK (Resources+Android.swift) as plain
    // reads, with no 5 MB → 18 MB inflate on the launch that copies it.
    androidResources {
        noCompress += "sqlite"
    }

    defaultConfig {
        minSdk = libs.versions.android.sdk.min.get().toInt()
        targetSdk = libs.versions.android.sdk.compile.get().toInt()
        // libPiru.so is built for arm64 alone; another ABI would install and fail to load it.
        ndk {
            abiFilters += "arm64-v8a"
        }
        // skip.tools.skip-build-plugin will automatically use Skip.env properties for:
        // applicationId = ANDROID_APPLICATION_ID ?? PRODUCT_BUNDLE_IDENTIFIER
        // versionCode = CURRENT_PROJECT_VERSION
        // versionName = MARKETING_VERSION
    }

    buildFeatures {
        buildConfig = true
    }

    lint {
        disable.add("Instantiatable")
        disable.add("MissingPermission")
    }

    dependenciesInfo {
        // Disables dependency metadata when building APKs.
        includeInApk = false
        // Disables dependency metadata when building Android App Bundles.
        includeInBundle = false
    }

    // A release built to be measured on a phone, never published (package-apk.sh refuses to
    // sign one): PIRU_PROFILE=profileable lets simpleperf attach from the shell, and
    // PIRU_PROFILE=debuggable also opens the app's data to `run-as`.
    val profileBuild = providers.environmentVariable("PIRU_PROFILE").orNull
    if (profileBuild != null) {
        require(profileBuild == "profileable" || profileBuild == "debuggable") {
            "PIRU_PROFILE is profileable or debuggable, not $profileBuild"
        }
        sourceSets.getByName("release").manifest.srcFile("src/profile/AndroidManifest.xml")
    }

    buildTypes {
        release {
            // Unsigned: package-apk.sh signs the release APK with the key from the macOS
            // keychain, and a release without that key fails rather than falling back.
            signingConfig = null
            isMinifyEnabled = true
            isShrinkResources = true
            isDebuggable = profileBuild == "debuggable"
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}
