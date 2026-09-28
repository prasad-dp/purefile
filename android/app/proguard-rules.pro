# Flutter wrapper & core
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google ML Kit Text Recognition
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# Camera & CameraX
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# Local Auth & Biometrics
-keep class androidx.biometric.** { *; }
-keep class io.flutter.plugins.localauth.** { *; }

# Secure Storage & Cryptography
-keep class androidx.security.crypto.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Receive Sharing Intent
-keep class com.kasem.receive_sharing_intent.** { *; }

# File Picker & OpenFileX & SharePlus
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class com.crazecoder.openfile.** { *; }
-keep class dev.fluttercommunity.plus.share.** { *; }

# JNI, annotations and native methods
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
-keepclassmembers class * {
    native <methods>;
}
-dontwarn javax.annotation.**
