import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

/// Collection names under users/{uid}/. Order matters for restore.
const kCollections = [
  'properties',
  'units',
  'tenants',
  'payments',
  'expenses',
  'invoices',
  'duesPayments',
];

/// Thin wrapper over one Firestore collection that belongs to the signed-in user.
///
/// Writes are not awaited: Firestore applies them to the local cache
/// immediately and syncs when the device is online, so the UI never blocks
/// while offline.
class Repo<T extends Entity> {
  Repo(this.db, this.uid, this.collection, this.fromMap);

  final FirebaseFirestore db;
  final String uid;
  final String collection;
  final T Function(String id, Map<String, dynamic> data) fromMap;

  CollectionReference<Map<String, dynamic>> get col =>
      db.collection('users').doc(uid).collection(collection);

  Stream<List<T>> watch() => col
      .snapshots()
      .map((s) => s.docs.map((d) => fromMap(d.id, d.data())).toList());

  /// Creates or replaces [item]. Returns its id.
  String save(T item) {
    final ref = item.id.isEmpty ? col.doc() : col.doc(item.id);
    unawaited(ref.set(item.toMap()).catchError(
        (Object e) => debugPrint('Save to $collection failed: $e')));
    return ref.id;
  }

  void delete(String id) {
    unawaited(col.doc(id).delete().catchError(
        (Object e) => debugPrint('Delete from $collection failed: $e')));
  }
}

/// User-level document: business profile and invoice counter.
class UserDocRepo {
  UserDocRepo(this.db, this.uid);

  final FirebaseFirestore db;
  final String uid;

  DocumentReference<Map<String, dynamic>> get doc =>
      db.collection('users').doc(uid);

  Stream<BusinessProfile> watchProfile() => doc
      .snapshots()
      .map((s) => BusinessProfile.fromMap(
          (s.data()?['profile'] as Map?)?.cast<String, dynamic>()));

  void saveProfile(BusinessProfile p) {
    unawaited(doc.set({'profile': p.toMap()}, SetOptions(merge: true))
        .catchError((Object e) => debugPrint('Profile save failed: $e')));
  }

  /// Next sequential invoice number, derived from existing invoices so it
  /// works offline and survives restores.
  int nextInvoiceNumber(List<Invoice> existing) {
    var maxSeen = 0;
    final digits = RegExp(r'(\d+)$');
    for (final inv in existing) {
      final m = digits.firstMatch(inv.number);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > maxSeen) maxSeen = n;
      }
    }
    return maxSeen + 1;
  }

  // ─────────────── Backup / restore helpers ───────────────

  /// Every document of every collection, as plain JSON-safe maps.
  Future<Map<String, dynamic>> exportAll() async {
    final data = <String, dynamic>{};
    for (final name in kCollections) {
      final snap = await doc.collection(name).get();
      data[name] = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    }
    final profile = (await doc.get()).data()?['profile'];
    return {
      'app': 'home_management',
      'schemaVersion': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'profile': profile,
      'data': data,
    };
  }

  /// Replaces all current data with the contents of [backup].
  Future<void> importAll(Map<String, dynamic> backup) async {
    if (backup['app'] != 'home_management') {
      throw const FormatException('Not a Home Management backup file');
    }
    final data = (backup['data'] as Map).cast<String, dynamic>();

    for (final name in kCollections) {
      final existing = await doc.collection(name).get();
      await _inBatches(existing.docs.map((d) => (WriteBatch b) => b.delete(d.reference)));

      final rows = (data[name] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e));
      await _inBatches(rows.map((row) {
        final id = '${row.remove('id') ?? ''}';
        final ref = id.isEmpty ? doc.collection(name).doc() : doc.collection(name).doc(id);
        return (WriteBatch b) => b.set(ref, row);
      }));
    }
    if (backup['profile'] is Map) {
      await doc.set({'profile': backup['profile']}, SetOptions(merge: true));
    }
  }

  Future<void> _inBatches(Iterable<void Function(WriteBatch)> ops) async {
    var batch = db.batch();
    var count = 0;
    for (final op in ops) {
      op(batch);
      if (++count == 400) {
        await batch.commit();
        batch = db.batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();
  }
}
