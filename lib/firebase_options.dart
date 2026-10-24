// Firebase configuration for the "Home Management System" project
// (home-management-system-d7381). Android is registered; iOS is added
// once the iOS app is registered in Firebase (run `flutterfire configure`
// on a Mac, or ask Claude to add it).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  /// OAuth "Web client" ID. Google Sign-In needs it to return an ID token
  /// that Firebase Auth accepts.
  static const webClientId =
      '683347678237-77buab1sqi97d20kpev8ai5qkl1rv5ou.apps.googleusercontent.com';

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not configured for this app.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'iOS is not registered in Firebase yet. Register the iOS app, then '
          'add its options here.',
        );
      default:
        throw UnsupportedError('This platform is not supported.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDGhNxpxqa81lMlAHOAol1egcoaVOGRLoY',
    appId: '1:683347678237:android:2bec8aca6baf6b987662f4',
    messagingSenderId: '683347678237',
    projectId: 'home-management-system-d7381',
    storageBucket: 'home-management-system-d7381.firebasestorage.app',
  );
}
