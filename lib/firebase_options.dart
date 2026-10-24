// Firebase configuration for the "Home Management System" project
// (home-management-system-d7381). Android and iOS are registered.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  /// OAuth "Web client" ID. Google Sign-In needs it to return an ID token
  /// that Firebase Auth accepts.
  static const webClientId =
      '683347678237-77buab1sqi97d20kpev8ai5qkl1rv5ou.apps.googleusercontent.com';

  /// OAuth "iOS client" ID, used by Google Sign-In on iPhone. Its reversed
  /// form is registered as a URL scheme in ios/Runner/Info.plist.
  static const iosClientId =
      '683347678237-qqi76vdrvf4up2uoq7r3g542sd2ljj7o.apps.googleusercontent.com';

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not configured for this app.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
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

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBwAqYxcRiP17oRYLqtO_lU_HBN3u8tMgw',
    appId: '1:683347678237:ios:55dc3cc3ba47417e7662f4',
    messagingSenderId: '683347678237',
    projectId: 'home-management-system-d7381',
    storageBucket: 'home-management-system-d7381.firebasestorage.app',
    iosClientId: iosClientId,
    iosBundleId: 'com.mahmoudessam.homemanagement',
  );
}
