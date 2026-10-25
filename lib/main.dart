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
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting();
  final prefs = await SharedPreferences.getInstance();

  runApp(ProviderScope(
    // Riverpod retries failed providers automatically, which keeps screens
    // on a spinner while e.g. a Firestore permission error repeats. Show
    // errors straight away instead; screens offer "Try again".
    retry: (retryCount, error) => null,
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const RentManagerApp(),
  ));
}
