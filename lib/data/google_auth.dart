import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';

/// Wrapper around the google_sign_in 7 singleton, used for Firebase login and
/// for Google Drive backups.
class GoogleAuth {
  GoogleAuth._();

  static Future<void>? _init;
  static GoogleSignInAccount? _account;

  static Future<GoogleSignIn> _ready() async {
    _init ??= GoogleSignIn.instance.initialize(
      // Needed on Android so Firebase Auth receives an ID token.
      serverClientId: DefaultFirebaseOptions.webClientId,
    );
    await _init;
    return GoogleSignIn.instance;
  }

  /// Shows the Google account picker. Returns null if the user cancels.
  static Future<GoogleSignInAccount?> signIn() async {
    final gsi = await _ready();
    try {
      _account = await gsi.authenticate();
      return _account;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  /// Returns the signed-in account without showing UI, if possible.
  static Future<GoogleSignInAccount?> silent() async {
    if (_account != null) return _account;
    final gsi = await _ready();
    _account = await gsi.attemptLightweightAuthentication();
    return _account;
  }

  /// ID token for signing in to Firebase with [account].
  static String? idToken(GoogleSignInAccount account) =>
      account.authentication.idToken;

  static Future<void> signOut() async {
    final gsi = await _ready();
    _account = null;
    await gsi.signOut();
  }
}
