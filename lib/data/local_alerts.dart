// Phone notifications without a server (free Firebase plan).
//
// • While the app is open or in the background, new inbox items arrive
//   through the live Firestore listener and are shown immediately.
// • On Android, a background check (WorkManager) runs about every 15 minutes
//   even when the app is closed, and shows anything new.
// • iOS does not allow regular background checks, so there notifications
//   appear when the app is opened or running.

import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../firebase_options.dart';
import 'notifications.dart';
import 'providers.dart';

final _plugin = FlutterLocalNotificationsPlugin();
bool _initialized = false;

/// Newest inbox item time already shown on this phone, shared by the app and
/// the background check so nothing is shown twice.
const _kLastShown = 'alerts.lastShown';
const _taskName = 'inboxCheck';

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'building_updates',
    'Building updates',
    channelDescription: 'New expenses, approvals and messages from your building',
    importance: Importance.high,
    priority: Priority.high,
  ),
  iOS: DarwinNotificationDetails(),
);

Future<void> initLocalAlerts() async {
  if (_initialized) return;
  await _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );
  _initialized = true;
}

Future<void> requestAlertPermission() async {
  try {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  } catch (e) {
    debugPrint('Notification permission request failed: $e');
  }
}

/// Shows notifications for unread items newer than the last one shown, and
/// remembers the newest. The first time on a phone it only sets the marker,
/// so old items don't flood the notification shade.
Future<void> _showNew(SharedPreferences prefs, String uid, List<InboxItem> items) async {
  await prefs.reload();
  final last = prefs.getInt(_kLastShown);
  final newest = items.fold<int>(last ?? 0, (m, i) {
    final t = i.createdAt.millisecondsSinceEpoch;
    return t > m ? t : m;
  });
  if (last == null) {
    await prefs.setInt(_kLastShown, newest == 0 ? DateTime.now().millisecondsSinceEpoch : newest);
    return;
  }
  final fresh = items
      .where((i) => !i.read && i.senderUid != uid && i.createdAt.millisecondsSinceEpoch > last)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  if (fresh.isEmpty) return;
  await initLocalAlerts();
  for (final i in fresh.take(10)) {
    await _plugin.show(
      id: i.id.hashCode & 0x7fffffff,
      title: i.title,
      body: i.body,
      notificationDetails: _details,
    );
  }
  await prefs.setInt(_kLastShown, newest);
}

// ─────────────────────────── App (main isolate) ───────────────────────────

/// Watched while signed in: asks for permission once, starts the Android
/// background check, and shows new inbox items as phone notifications.
final localAlertsProvider = Provider<void>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return;
  final prefs = ref.watch(prefsProvider);

  () async {
    await initLocalAlerts();
    await requestAlertPermission();
    await startBackgroundChecks();
  }()
      .catchError((Object e) => debugPrint('Local alerts setup failed: $e'));

  ref.listen<AsyncValue<List<InboxItem>>>(inboxProvider, (_, next) {
    final items = next.value;
    if (items == null) return;
    _showNew(prefs, uid, items).catchError((Object e) => debugPrint('Alert failed: $e'));
  }, fireImmediately: true);
});

Future<void> startBackgroundChecks() async {
  if (kIsWeb || !Platform.isAndroid) return;
  await Workmanager().initialize(inboxCheckDispatcher);
  await Workmanager().registerPeriodicTask(
    'inbox-check',
    _taskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

/// Call on sign-out so the background check stops for this phone.
Future<void> stopBackgroundChecks() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    await Workmanager().cancelAll();
  } catch (e) {
    debugPrint('Stopping background checks failed: $e');
  }
}

// ─────────────────────────── Background (Android) ───────────────────────────

@pragma('vm:entry-point')
void inboxCheckDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser ??
          await auth.authStateChanges().first.timeout(const Duration(seconds: 10), onTimeout: () => null);
      if (user == null) return true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final last = prefs.getInt(_kLastShown) ?? DateTime.now().millisecondsSinceEpoch;
      final snap = await FirebaseFirestore.instance
          .collection('inbox')
          .doc(user.uid)
          .collection('items')
          .where('createdAt', isGreaterThan: last)
          .orderBy('createdAt')
          .limit(20)
          .get();
      final items = snap.docs.map((d) => InboxItem.fromMap(d.id, d.data())).toList();
      await _showNew(prefs, user.uid, items);
    } catch (e) {
      debugPrint('Background inbox check failed: $e');
    }
    return true;
  });
}
