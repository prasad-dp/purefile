# Flutter wrapper & core
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Play Store Core (Deferred Components referenced by Flutter engine)
-dontwarn com.google.android.play.core.**

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
-dontwarn com.crazecoder.openfile.**
-keep class dev.fluttercommunity.plus.share.** { *; }
-dontwarn dev.fluttercommunity.plus.share.**

# Apache Tika & XML streaming (referenced by open_filex / Tika mime detector)
-dontwarn org.apache.tika.**
-dontwarn javax.xml.stream.**
-dontwarn javax.xml.**
-dontwarn org.w3c.dom.**

# JNI, annotations and native methods
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
-keepclassmembers class * {
    native <methods>;
}
-dontwarn javax.annotation.**

# Google Mobile Ads (AdMob)
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**
-keep class io.flutter.plugins.googlemobileads.** { *; }

# Google Play In-App Purchase / Billing
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**
-keep class io.flutter.plugins.inapppurchase.** { *; }

