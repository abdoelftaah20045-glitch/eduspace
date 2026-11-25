
// Appended by CI: stable release signing when keystore secrets exist, debug signing otherwise.
android {
    signingConfigs {
        create("release") {
            storeFile = file("keystore.jks")
            storePassword = System.getenv("KEYSTORE_PASSWORD")
            keyAlias = System.getenv("KEY_ALIAS") ?: "eduspace"
            keyPassword = System.getenv("KEY_PASSWORD")
        }
    }
    buildTypes {
        release {
            signingConfig = if (System.getenv("KEYSTORE_PASSWORD").isNullOrEmpty()) signingConfigs.getByName("debug") else signingConfigs.getByName("release")
        }
    }
}
