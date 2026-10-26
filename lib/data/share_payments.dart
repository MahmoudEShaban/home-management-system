// Repaying a resident who paid for an approved maintenance request.
//
// When the building manager approves a resident's maintenance request and
// sets each flat's share, that resident (the "payee") is owed the other
// flats' shares. Each flat says "I've paid" (with optional proof) and the
// payee — not the manager — confirms or declines. The manager can see every
// share and can confirm on the payee's behalf.
//
// Stored at users/{managerUid}/sharePayments/{id}: one document per payment,
// so a flat can pay its share in several parts.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'community.dart';
import 'models.dart';
import 'providers.dart';

const kSharePayments = 'sharePayments';

DateTime _dt(dynamic v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : DateTime.now();
double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

class SharePayment {
  final String id;
  final String expenseId;
  final String propertyId;
  final String unitId;
  final String unitName;
  final double amount;
  final PaymentMethod method;
  final DuesPaymentStatus status;
  final String note;
  final String decisionNote;
  final String paidByUid;
  final String paidByName;

  /// The resident who submitted the maintenance request and confirms.
  final String payeeUid;
  final String payeeName;
  final List<String> attachmentIds;
  final DateTime paidAt;
  final DateTime? decidedAt;

  const SharePayment({
    this.id = '',
    required this.expenseId,
    required this.propertyId,
    required this.unitId,
    this.unitName = '',
    required this.amount,
    this.method = PaymentMethod.cash,
    this.status = DuesPaymentStatus.claimed,
    this.note = '',
    this.decisionNote = '',
    required this.paidByUid,
    this.paidByName = '',
    required this.payeeUid,
    this.payeeName = '',
    this.attachmentIds = const [],
    required this.paidAt,
    this.decidedAt,
  });

  bool get isConfirmed => status == DuesPaymentStatus.confirmed;
  bool get isClaimed => status == DuesPaymentStatus.claimed;

  factory SharePayment.fromMap(String id, Map<String, dynamic> m) => SharePayment(
        id: id,
        expenseId: '${m['expenseId'] ?? ''}',
        propertyId: '${m['propertyId'] ?? ''}',
        unitId: '${m['unitId'] ?? ''}',
        unitName: '${m['unitName'] ?? ''}',
        amount: _d(m['amount']),
        method: PaymentMethod.values.asNameMap()[m['method']] ?? PaymentMethod.cash,
        status: DuesPaymentStatus.values.asNameMap()[m['status']] ?? DuesPaymentStatus.claimed,
        note: '${m['note'] ?? ''}',
        decisionNote: '${m['decisionNote'] ?? ''}',
        paidByUid: '${m['paidByUid'] ?? ''}',
        paidByName: '${m['paidByName'] ?? ''}',
        payeeUid: '${m['payeeUid'] ?? ''}',
        payeeName: '${m['payeeName'] ?? ''}',
        attachmentIds: (m['attachmentIds'] as List? ?? const []).map((e) => '$e').toList(),
        paidAt: _dt(m['paidAt']),
        decidedAt: m['decidedAt'] is num ? _dt(m['decidedAt']) : null,
      );

  Map<String, dynamic> toMap() => {
        'expenseId': expenseId,
        'propertyId': propertyId,
        'unitId': unitId,
        'unitName': unitName,
        'amount': amount,
        'method': method.name,
        'status': status.name,
        'note': note,
        'decisionNote': decisionNote,
        'paidByUid': paidByUid,
        'paidByName': paidByName,
        'payeeUid': payeeUid,
        'payeeName': payeeName,
        'attachmentIds': attachmentIds,
        'paidAt': paidAt.millisecondsSinceEpoch,
        'decidedAt': decidedAt?.millisecondsSinceEpoch,
      };
}

CollectionReference<Map<String, dynamic>> sharePaymentsOf(FirebaseFirestore db, String managerUid) =>
    db.collection('users').doc(managerUid).collection(kSharePayments);

List<SharePayment> _parse(QuerySnapshot<Map<String, dynamic>> s) =>
    s.docs.map((d) => SharePayment.fromMap(d.id, d.data())).toList()..sort((a, b) => b.paidAt.compareTo(a.paidAt));

/// Resident: share payments in their building (theirs, and those owed to them).
final residentSharePaymentsProvider = StreamProvider<List<SharePayment>>((ref) {
  final m = ref.watch(membershipProvider);
  if (m == null) return Stream.value(const []);
  return sharePaymentsOf(ref.watch(firestoreProvider), m.managerUid)
      .where('propertyId', isEqualTo: m.propertyId)
      .snapshots()
      .map(_parse);
});

/// Manager: every share payment.
final managerSharePaymentsProvider = StreamProvider<List<SharePayment>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return sharePaymentsOf(ref.watch(firestoreProvider), uid).snapshots().map(_parse);
});

/// Resident says their flat paid its share of [e] to the requester.
Future<void> claimSharePayment(
  FirebaseFirestore db,
  JoinRequest m,
  Expense e, {
  required double amount,
  required PaymentMethod method,
  String note = '',
  List<String> attachmentIds = const [],
}) =>
    sharePaymentsOf(db, m.managerUid).add(SharePayment(
          expenseId: e.id,
          propertyId: m.propertyId,
          unitId: m.unitId,
          unitName: m.unitName,
          amount: amount,
          method: method,
          note: note,
          paidByUid: m.residentUid,
          paidByName: m.name,
          payeeUid: e.payToUid,
          payeeName: e.payToName,
          attachmentIds: attachmentIds,
          paidAt: DateTime.now(),
        ).toMap());

/// The requester (or the manager) confirms or declines a share payment.
Future<void> decideSharePayment(FirebaseFirestore db, String managerUid, SharePayment p,
        {required bool confirm, String note = ''}) =>
    sharePaymentsOf(db, managerUid).doc(p.id).update({
      'status': (confirm ? DuesPaymentStatus.confirmed : DuesPaymentStatus.rejected).name,
      'decisionNote': note,
      'decidedAt': DateTime.now().millisecondsSinceEpoch,
    });

/// Where one flat stands on its share of a resident-paid maintenance expense.
class ShareStatus {
  final double owed;
  final double confirmed;
  final double pending;
  final List<SharePayment> payments; // this flat's, newest first, incl. declined

  const ShareStatus(this.owed, this.confirmed, this.pending, this.payments);

  /// Still to pay after confirmed and waiting payments.
  double get remaining => (owed - confirmed - pending) > 0.005 ? owed - confirmed - pending : 0;
  bool get settled => confirmed + 0.005 >= owed;
  bool get hasPending => pending > 0.005;

  static ShareStatus of(Expense e, String unitId, List<SharePayment> all) {
    final mine = all.where((p) => p.expenseId == e.id && p.unitId == unitId).toList();
    double sum(bool Function(SharePayment) f) => mine.where(f).fold<double>(0, (s, p) => s + p.amount);
    return ShareStatus(e.shareFor(unitId), sum((p) => p.isConfirmed), sum((p) => p.isClaimed), mine);
  }
}
