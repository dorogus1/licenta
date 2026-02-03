// File generated manually based on available info.
// TODO: Replace the placeholder values below with your actual Firebase configuration.
// You can find these values in your Firebase Console under Project Settings -> General -> Your Apps.
// Since you are using a Web Extension, you likely have a Web App configuration.
// For Android/iOS/Windows native support, you should ideally add those apps in Firebase Console
// and use the specific configuration values for them.
//
// If you only have the Web config, it MIGHT work for Windows if you use the Web keys,
// but for Android/iOS it is recommended to use the google-services.json / GoogleService-Info.plist approach
// or fill in the specific Android/iOS parameters here.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDiUH04OAUwJk8vdDbqFrQuH-F7ybWBUiY',
    appId: '1:1024855875521:web:ce64c01b96bb3833d01940',
    messagingSenderId: '1024855875521',
    projectId: 'focus-shild',
    authDomain: 'focus-shild.firebaseapp.com',
    storageBucket: 'focus-shild.firebasestorage.app',
    measurementId: 'G-7RWW18FV0X',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCOII03qcqyZy-_X_q6LK0rBJjU-nPPgyA',
    appId: '1:1024855875521:android:56298c78bf52954dd01940',
    messagingSenderId: '1024855875521',
    projectId: 'focus-shild',
    storageBucket: 'focus-shild.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCQ1XnXiWk8FockoTjeqCTsuFrfRgzJhGI',
    appId: '1:1024855875521:ios:e63ede64bcf870fdd01940',
    messagingSenderId: '1024855875521',
    projectId: 'focus-shild',
    storageBucket: 'focus-shild.firebasestorage.app',
    iosBundleId: 'com.example.focusApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCQ1XnXiWk8FockoTjeqCTsuFrfRgzJhGI',
    appId: '1:1024855875521:ios:e63ede64bcf870fdd01940',
    messagingSenderId: '1024855875521',
    projectId: 'focus-shild',
    storageBucket: 'focus-shild.firebasestorage.app',
    iosBundleId: 'com.example.focusApp',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDiUH04OAUwJk8vdDbqFrQuH-F7ybWBUiY',
    appId: '1:1024855875521:web:df6e19b6a29389fad01940',
    messagingSenderId: '1024855875521',
    projectId: 'focus-shild',
    authDomain: 'focus-shild.firebaseapp.com',
    storageBucket: 'focus-shild.firebasestorage.app',
    measurementId: 'G-8TTWFBZLPJ',
  );

}