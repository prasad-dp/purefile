package com.purefile.purefile

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity): local_auth's Android
// BiometricPrompt requires a FragmentActivity host (feature 14 vault).
class MainActivity : FlutterFragmentActivity()
