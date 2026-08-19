import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('تطبيق الطفل مخصص لـ Android.');
    }
    return android;
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA7nHDKLFD2Uf0uSW8eK68l3pto-wePGQ0',
    appId: '1:40877142171:android:a9193a46a56eedbc2c163e',
    messagingSenderId: '40877142171',
    projectId: 'kidsafe-5739d',
    storageBucket: 'kidsafe-5739d.firebasestorage.app',
  );
}
