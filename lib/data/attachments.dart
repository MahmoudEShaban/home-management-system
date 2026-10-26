// Image attachments (receipts, bills, photos of a problem, proof of payment).
//
// The free Firebase plan has no Cloud Storage, so each photo is shrunk on the
// phone to a small JPEG (normally 100–400 KB) and saved as its own Firestore
// document at users/{managerUid}/attachments/{id}. The expense, proposal,
// payment or flat expense keeps the ids in `attachmentIds`, so the photo
// stays linked to it.
//
// Who can see a photo (Firestore rules):
//   scope 'building' – the manager and residents of that building
//                      (building expenses and expense / maintenance requests)
//   scope 'flat'     – the manager and residents of that flat
//                      (proof of payment, private flat expenses)

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import 'providers.dart';

const kAttachmentsCollection = 'attachments';

/// Firestore documents are limited to 1 MiB; stay well below it.
const kMaxAttachmentBytes = 700 * 1024;
const kMaxAttachmentsPerItem = 5;

enum AttachmentScope { building, flat }

class Attachment {
  final String id;
  final String propertyId;
  final String unitId;
  final AttachmentScope scope;
  final Uint8List bytes;
  final String uploadedByUid;
  final DateTime createdAt;

  const Attachment({
    required this.id,
    required this.propertyId,
    this.unitId = '',
    required this.scope,
    required this.bytes,
    required this.uploadedByUid,
    required this.createdAt,
  });

  factory Attachment.fromMap(String id, Map<String, dynamic> m) {
    final data = m['data'];
    return Attachment(
      id: id,
      propertyId: '${m['propertyId'] ?? ''}',
      unitId: '${m['unitId'] ?? ''}',
      scope: AttachmentScope.values.asNameMap()[m['scope']] ?? AttachmentScope.building,
      bytes: data is Blob ? data.bytes : Uint8List(0),
      uploadedByUid: '${m['uploadedByUid'] ?? ''}',
      createdAt: m['createdAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch((m['createdAt'] as num).toInt())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'propertyId': propertyId,
        'unitId': unitId,
        'scope': scope.name,
        'data': Blob(bytes),
        'contentType': 'image/jpeg',
        'uploadedByUid': uploadedByUid,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };
}

/// Re-encodes [input] as a JPEG under [kMaxAttachmentBytes], shrinking it
/// step by step if needed. Returns null if the image can't be read.
Uint8List? compressForUpload(Uint8List input) {
  if (input.length <= kMaxAttachmentBytes && _isJpeg(input)) return input;
  final decoded = img.decodeImage(input);
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  var maxSide = 1280;
  var quality = 70;
  for (var i = 0; i < 8; i++) {
    final longest = image.width > image.height ? image.width : image.height;
    final resized = longest > maxSide
        ? img.copyResize(image,
            width: image.width >= image.height ? maxSide : null,
            height: image.height > image.width ? maxSide : null,
            interpolation: img.Interpolation.average)
        : image;
    final out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    if (out.length <= kMaxAttachmentBytes) return out;
    image = resized;
    maxSide = (maxSide * 0.8).round();
    quality = quality > 45 ? quality - 10 : quality;
  }
  return null;
}

bool _isJpeg(Uint8List b) => b.length > 2 && b[0] == 0xFF && b[1] == 0xD8;

/// Key for loading one attachment: the manager account that owns it + id.
typedef AttachmentKey = ({String managerUid, String id});

CollectionReference<Map<String, dynamic>> attachmentsOf(FirebaseFirestore db, String managerUid) =>
    db.collection('users').doc(managerUid).collection(kAttachmentsCollection);

/// Photos picked on this phone, kept in memory so they show instantly
/// (even offline, before Firestore has synced them).
final _localBytes = <String, Uint8List>{};

final attachmentBytesProvider = FutureProvider.autoDispose.family<Uint8List?, AttachmentKey>((ref, key) async {
  final local = _localBytes[key.id];
  if (local != null) return local;
  if (key.managerUid.isEmpty || key.id.isEmpty) return null;
  final snap = await attachmentsOf(ref.watch(firestoreProvider), key.managerUid).doc(key.id).get();
  final data = snap.data();
  if (data == null) return null;
  final bytes = Attachment.fromMap(snap.id, data).bytes;
  return bytes.isEmpty ? null : bytes;
});

class AttachmentService {
  AttachmentService(this.db);
  final FirebaseFirestore db;

  /// Saves a photo and returns its id straight away. The write isn't
  /// awaited, like other writes in the app, so it works offline.
  String add({
    required String managerUid,
    required String propertyId,
    required String unitId,
    required AttachmentScope scope,
    required String uploaderUid,
    required Uint8List jpeg,
  }) {
    final doc = attachmentsOf(db, managerUid).doc();
    _localBytes[doc.id] = jpeg;
    doc
        .set(Attachment(
          id: doc.id,
          propertyId: propertyId,
          unitId: unitId,
          scope: scope,
          bytes: jpeg,
          uploadedByUid: uploaderUid,
          createdAt: DateTime.now(),
        ).toMap())
        .catchError((Object e) {
      debugPrint('Attachment upload failed: $e');
    });
    return doc.id;
  }

  Future<void> delete(String managerUid, String id) async {
    _localBytes.remove(id);
    await attachmentsOf(db, managerUid).doc(id).delete();
  }
}

final attachmentServiceProvider = Provider((ref) => AttachmentService(ref.watch(firestoreProvider)));
