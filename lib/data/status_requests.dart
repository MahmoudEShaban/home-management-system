// Flat status change requests: a resident asks to mark their flat as
// occupied ("Living here") or closed ("Not occupied"); the building manager
// approves or declines. Only the manager changes the flat itself.
//
// Stored at users/{managerUid}/statusRequests/{unitId}: one request per flat,
// so a new request replaces an older one.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'community.dart';
import 'models.dart';
import 'providers.dart';

const kStatusRequests = 'statusRequests';

DateTime _dt(dynamic v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : DateTime.now();

class FlatStatusRequest {
  final String unitId;
  final String propertyId;
  final String unitName;
  final UnitStatus fromStatus;
  final UnitStatus toStatus;
  final String residentUid;
  final String residentName;
  final RequestStatus status;
  final String decisionNote;
  final DateTime createdAt;

  const FlatStatusRequest({
    required this.unitId,
    required this.propertyId,
    this.unitName = '',
    required this.fromStatus,
    required this.toStatus,
    required this.residentUid,
    this.residentName = '',
    this.status = RequestStatus.pending,
    this.decisionNote = '',
    required this.createdAt,
  });

  bool get isPending => status == RequestStatus.pending;

  factory FlatStatusRequest.fromMap(String unitId, Map<String, dynamic> m) => FlatStatusRequest(
        unitId: unitId,
        propertyId: '${m['propertyId'] ?? ''}',
        unitName: '${m['unitName'] ?? ''}',
        fromStatus: UnitStatus.values.asNameMap()[m['fromStatus']] ?? UnitStatus.closed,
        toStatus: UnitStatus.values.asNameMap()[m['toStatus']] ?? UnitStatus.closed,
        residentUid: '${m['residentUid'] ?? ''}',
        residentName: '${m['residentName'] ?? ''}',
        status: RequestStatus.values.asNameMap()[m['status']] ?? RequestStatus.pending,
        decisionNote: '${m['decisionNote'] ?? ''}',
        createdAt: _dt(m['createdAt']),
      );

  Map<String, dynamic> toMap() => {
        'unitId': unitId,
        'propertyId': propertyId,
        'unitName': unitName,
        'fromStatus': fromStatus.name,
        'toStatus': toStatus.name,
        'residentUid': residentUid,
        'residentName': residentName,
        'status': status.name,
        'decisionNote': decisionNote,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };
}

CollectionReference<Map<String, dynamic>> _col(FirebaseFirestore db, String managerUid) =>
    db.collection('users').doc(managerUid).collection(kStatusRequests);

/// Resident: the latest request for their flat (null if none).
final myFlatStatusRequestProvider = StreamProvider<FlatStatusRequest?>((ref) {
  final m = ref.watch(membershipProvider);
  if (m == null) return Stream.value(null);
  return _col(ref.watch(firestoreProvider), m.managerUid)
      .doc(m.unitId)
      .snapshots()
      .map((s) => s.data() == null ? null : FlatStatusRequest.fromMap(s.id, s.data()!));
});

/// Manager: requests waiting for a decision, oldest first.
final pendingStatusRequestsProvider = StreamProvider<List<FlatStatusRequest>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return _col(ref.watch(firestoreProvider), uid)
      .where('status', isEqualTo: RequestStatus.pending.name)
      .snapshots()
      .map((s) => s.docs.map((d) => FlatStatusRequest.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
});

/// Resident: ask to change the flat's status.
Future<void> requestFlatStatus(FirebaseFirestore db, JoinRequest m, Unit unit, UnitStatus to) =>
    _col(db, m.managerUid).doc(unit.id).set(FlatStatusRequest(
          unitId: unit.id,
          propertyId: m.propertyId,
          unitName: unit.name,
          fromStatus: unit.status,
          toStatus: to,
          residentUid: m.residentUid,
          residentName: m.name,
          createdAt: DateTime.now(),
        ).toMap());

/// Resident: withdraw a request that is still waiting.
Future<void> cancelFlatStatusRequest(FirebaseFirestore db, JoinRequest m) =>
    _col(db, m.managerUid).doc(m.unitId).delete();

/// Manager: record the decision on a request.
Future<void> decideFlatStatusRequest(FirebaseFirestore db, String managerUid, String unitId,
        {required bool approved, String note = ''}) =>
    _col(db, managerUid).doc(unitId).update({
      'status': (approved ? RequestStatus.approved : RequestStatus.rejected).name,
      'decisionNote': note,
      'decidedAt': DateTime.now().millisecondsSinceEpoch,
    });
