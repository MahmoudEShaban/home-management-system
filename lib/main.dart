import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/providers.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferences prefs;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await initializeDateFormatting();
    prefs = await SharedPreferences.getInstance();
  } catch (e, st) {
    // Without this the app would sit on the splash screen forever.
    debugPrint('Startup failed: $e\n$st');
    runApp(_StartupErrorApp(error: e));
    return;
  }

  runApp(ProviderScope(
    // Riverpod retries failed providers automatically, which keeps screens
    // on a spinner while e.g. a Firestore permission error repeats. Show
    // errors straight away instead; screens offer "Try again".
    retry: (retryCount, error) => null,
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const RentManagerApp(),
  ));
}

/// Shown when the app can't start (e.g. a plugin fails to load).
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  const Text('The app could not start / تعذر تشغيل التطبيق',
                      textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('$error', textAlign: TextAlign.center),
                ]),
              ),
            ),
          ),
        ),
      );
}
