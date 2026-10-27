import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

import 'google_auth.dart';
import 'providers.dart';

enum BackupFrequency { off, daily, weekly }

class DriveBackupInfo {
  final String id;
  final String name;
  final DateTime? createdTime;
  final int sizeBytes;
  const DriveBackupInfo(this.id, this.name, this.createdTime, this.sizeBytes);
}

/// State shown on the Backups screen and dashboard.
class BackupState {
  final String? driveAccount; // email of the connected Google account
  final BackupFrequency frequency;
  final DateTime? lastBackup;
  final String? lastError;
  final bool busy;

  const BackupState({
    this.driveAccount,
    this.frequency = BackupFrequency.weekly,
    this.lastBackup,
    this.lastError,
    this.busy = false,
  });

  bool get connected => driveAccount != null;

  BackupState copyWith({
    String? driveAccount,
    bool clearAccount = false,
    BackupFrequency? frequency,
    DateTime? lastBackup,
    String? lastError,
    bool clearError = false,
    bool? busy,
  }) =>
      BackupState(
        driveAccount: clearAccount ? null : (driveAccount ?? this.driveAccount),
        frequency: frequency ?? this.frequency,
        lastBackup: lastBackup ?? this.lastBackup,
        lastError: clearError ? null : (lastError ?? this.lastError),
        busy: busy ?? this.busy,
      );
}

/// Uploads JSON snapshots of all data to a "Home Management Backups" folder in
/// the user's Google Drive. Uses the narrow `drive.file` scope, so the app can
/// only see files it created.
class BackupController extends StateNotifier<BackupState> {
  BackupController(this._ref, this._prefs) : super(_load(_prefs));

  final Ref _ref;
  final SharedPreferences _prefs;

  static const folderName = 'Home Management Backups';
  static const keep = 30;
  static const _kAccount = 'backup.account';
  static const _kFrequency = 'backup.frequency';
  static const _kLast = 'backup.last';
  static const _kError = 'backup.error';

  static BackupState _load(SharedPreferences p) => BackupState(
        driveAccount: p.getString(_kAccount),
        frequency: BackupFrequency.values
                .asNameMap()[p.getString(_kFrequency) ?? 'weekly'] ??
            BackupFrequency.weekly,
        lastBackup: p.getInt(_kLast) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(p.getInt(_kLast)!),
        lastError: p.getString(_kError),
      );

  static const _scopes = [drive.DriveApi.driveFileScope];

  // ─────────────────────────── Connection ───────────────────────────

  /// Interactive: asks the user to pick an account and grant Drive access.
  Future<void> connect() async {
    final account = await GoogleAuth.silent() ?? await GoogleAuth.signIn();
    if (account == null) return; // user cancelled
    await account.authorizationClient.authorizeScopes(_scopes);
    await _prefs.setString(_kAccount, account.email);
    state = state.copyWith(driveAccount: account.email, clearError: true);
  }

  Future<void> disconnect() async {
    await _prefs.remove(_kAccount);
    state = state.copyWith(clearAccount: true);
  }

  void setFrequency(BackupFrequency f) {
    _prefs.setString(_kFrequency, f.name);
    state = state.copyWith(frequency: f);
  }

  /// Drive client. Silent runs only use an existing grant and never show UI.
  Future<drive.DriveApi> _api({required bool interactive}) async {
    var account = await GoogleAuth.silent();
    if (account == null && interactive) account = await GoogleAuth.signIn();
    if (account == null) throw Exception('Google account not signed in');
    var authorization =
        await account.authorizationClient.authorizationForScopes(_scopes);
    if (authorization == null && interactive) {
      authorization = await account.authorizationClient.authorizeScopes(_scopes);
    }
    if (authorization == null) {
      throw Exception('Google Drive permission needed: open Backups and tap Back up now');
    }
    return drive.DriveApi(authorization.authClient(scopes: _scopes));
  }

  Future<String> _folderId(drive.DriveApi api) async {
    final found = await api.files.list(
      q: "mimeType='application/vnd.google-apps.folder' "
          "and name='$folderName' and trashed=false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final existing = found.files;
    if (existing != null && existing.isNotEmpty) return existing.first.id!;
    final folder = await api.files.create(drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder');
    return folder.id!;
  }

  // ─────────────────────────── Backup ───────────────────────────

  /// Uploads a snapshot now. Throws on failure when [interactive].
  Future<void> backupNow({bool interactive = true}) async {
    if (state.busy) return;
    state = state.copyWith(busy: true);
    try {
      final api = await _api(interactive: interactive);
      final folderId = await _folderId(api);
      final snapshot = await _ref.read(userDocRepo).exportAll();
      final bytes = Uint8List.fromList(
          utf8.encode(const JsonEncoder.withIndent(' ').convert(snapshot)));
      final stamp = DateTime.now()
          .toIso8601String()
          .substring(0, 19)
          .replaceAll(':', '-')
          .replaceAll('T', '_');
      await api.files.create(
        drive.File()
          ..name = 'home-management-backup_$stamp.json'
          ..parents = [folderId]
          ..mimeType = 'application/json',
        uploadMedia: drive.Media(Stream.value(bytes), bytes.length,
            contentType: 'application/json'),
      );
      await _prune(api, folderId);

      final now = DateTime.now();
      await _prefs.setInt(_kLast, now.millisecondsSinceEpoch);
      await _prefs.remove(_kError);
      state = state.copyWith(lastBackup: now, clearError: true, busy: false);
    } catch (e) {
      debugPrint('Backup failed: $e');
      await _prefs.setString(_kError, '$e');
      state = state.copyWith(lastError: '$e', busy: false);
      if (interactive) rethrow;
    }
  }

  /// Runs a silent backup if one is due. Called on app start and resume.
  Future<void> runIfDue() async {
    if (!state.connected || state.busy) return;
    final interval = switch (state.frequency) {
      BackupFrequency.off => null,
      BackupFrequency.daily => const Duration(days: 1),
      BackupFrequency.weekly => const Duration(days: 7),
    };
    if (interval == null) return;
    final last = state.lastBackup;
    if (last != null && DateTime.now().difference(last) < interval) return;
    await backupNow(interactive: false);
  }

  Future<void> _prune(drive.DriveApi api, String folderId) async {
    final files = await _list(api, folderId);
    for (final f in files.skip(keep)) {
      await api.files.delete(f.id);
    }
  }

  // ─────────────────────────── Restore ───────────────────────────

  Future<List<DriveBackupInfo>> listBackups() async {
    final api = await _api(interactive: true);
    return _list(api, await _folderId(api));
  }

  Future<List<DriveBackupInfo>> _list(drive.DriveApi api, String folderId) async {
    final res = await api.files.list(
      q: "'$folderId' in parents and trashed=false",
      orderBy: 'createdTime desc',
      pageSize: 100,
      spaces: 'drive',
      $fields: 'files(id,name,createdTime,size)',
    );
    return (res.files ?? const <drive.File>[])
        .where((f) => f.id != null)
        .map((f) => DriveBackupInfo(
              f.id!,
              f.name ?? '',
              f.createdTime?.toLocal(),
              int.tryParse(f.size ?? '') ?? 0,
            ))
        .toList();
  }

  Future<void> restore(String fileId) async {
    state = state.copyWith(busy: true);
    try {
      final api = await _api(interactive: true);
      final media = await api.files.get(fileId,
          downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      final chunks = <int>[];
      await for (final chunk in media.stream) {
        chunks.addAll(chunk);
      }
      final json = jsonDecode(utf8.decode(chunks)) as Map<String, dynamic>;
      await _ref.read(userDocRepo).importAll(json);
    } finally {
      state = state.copyWith(busy: false);
    }
  }
}

final backupProvider = StateNotifierProvider<BackupController, BackupState>(
    (ref) => BackupController(ref, ref.watch(prefsProvider)));

