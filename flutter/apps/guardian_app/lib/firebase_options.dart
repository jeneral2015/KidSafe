import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('KidSafe Guardian يدعم Android والويب في هذه المرحلة.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC9HIooVFkEL1ISMZkSLqP1dMaWU0DLRHw',
    appId: '1:40877142171:web:1f92d7a185360edf2c163e',
    messagingSenderId: '40877142171',
    projectId: 'kidsafe-5739d',
    authDomain: 'kidsafe-5739d.firebaseapp.com',
    storageBucket: 'kidsafe-5739d.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA7nHDKLFD2Uf0uSW8eK68l3pto-wePGQ0',
    appId: '1:40877142171:android:c4e2d5075a44e1d32c163e',
    messagingSenderId: '40877142171',
    projectId: 'kidsafe-5739d',
    storageBucket: 'kidsafe-5739d.firebasestorage.app',
  );
}
