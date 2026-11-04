// Private flat expenses: costs a flat's residents record for their own flat
// (a repair inside the flat, its own electricity meter, furniture, …).
//
// Stored at users/{managerUid}/flatExpenses/{id}. Firestore rules let only
// residents linked to that flat read and write them; the building manager
// (the account that owns users/{managerUid}) can see every flat's entries.
// A manager who lives in one of their own flats picks it (users/{uid}.homeFlat)
// and keeps that flat's expenses the same way residents do.
// They are never split between flats and are not part of the building's
// expenses, dues or fund balance.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'community.dart';
import 'models.dart';
import 'phone_account.dart';
import 'providers.dart';

const kFlatExpensesCollection = 'flatExpenses';

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String _s(dynamic v) => v == null ? '' : '$v';
DateTime _dt(dynamic v) => v is num
    ? DateTime.fromMillisecondsSinceEpoch(v.toInt())
    : v is Timestamp
        ? v.toDate()
        : DateTime.now();

class FlatExpense {
  final String id;
  final String propertyId;
  final String unitId;
  final ExpenseCategory category;
  final String title;
  final double amount;
  final DateTime date;
  final String notes;
  final String addedByUid;
  final String addedByName;
  final DateTime createdAt;
  final List<String> attachmentIds;

  const FlatExpense({
    this.id = '',
    required this.propertyId,
    required this.unitId,
    this.category = ExpenseCategory.other,
    this.title = '',
    required this.amount,
    required this.date,
    this.notes = '',
    required this.addedByUid,
    this.addedByName = '',
    required this.createdAt,
    this.attachmentIds = const [],
  });

  factory FlatExpense.fromMap(String id, Map<String, dynamic> m) => FlatExpense(
        id: id,
        propertyId: _s(m['propertyId']),
        unitId: _s(m['unitId']),
        category: ExpenseCategory.values.asNameMap()[m['category']] ?? ExpenseCategory.other,
        title: _s(m['title']),
        amount: _d(m['amount']),
        date: _dt(m['date']),
        notes: _s(m['notes']),
        addedByUid: _s(m['addedByUid']),
        addedByName: _s(m['addedByName']),
        createdAt: _dt(m['createdAt']),
        attachmentIds: (m['attachmentIds'] as List? ?? const []).map((e) => '$e').toList(),
      );

  Map<String, dynamic> toMap() => {
        'propertyId': propertyId,
        'unitId': unitId,
        'category': category.name,
        'title': title,
        'amount': amount,
        'date': date.millisecondsSinceEpoch,
        'notes': notes,
        'addedByUid': addedByUid,
        'addedByName': addedByName,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'attachmentIds': attachmentIds,
      };
}

List<FlatExpense> _parse(QuerySnapshot<Map<String, dynamic>> s) =>
    s.docs.map((d) => FlatExpense.fromMap(d.id, d.data())).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

/// The flat whose private expenses this account keeps: a resident's linked
/// flat, or the flat the building manager lives in.
typedef MyFlat = ({
  String managerUid,
  String propertyId,
  String unitId,
  String unitName,
  String uid,
  String name,
});

/// Manager: the flat of their own buildings they live in (null if none).
typedef HomeFlat = ({String propertyId, String unitId});

final managerHomeFlatProvider = StreamProvider<HomeFlat?>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreProvider).collection('users').doc(uid).snapshots().map((s) {
    final m = (s.data()?['homeFlat'] as Map?)?.cast<String, dynamic>();
    final unitId = _s(m?['unitId']);
    return unitId.isEmpty ? null : (propertyId: _s(m?['propertyId']), unitId: unitId);
  });
});

/// Manager sets (or, with null, clears) the flat they live in.
Future<void> setManagerHomeFlat(FirebaseFirestore db, String uid, HomeFlat? flat) =>
    db.collection('users').doc(uid).set({
      'homeFlat': flat == null ? FieldValue.delete() : {'propertyId': flat.propertyId, 'unitId': flat.unitId},
    }, SetOptions(merge: true));

final myFlatProvider = Provider<MyFlat?>((ref) {
  final m = ref.watch(membershipProvider);
  if (m != null) {
    return (
      managerUid: m.managerUid,
      propertyId: m.propertyId,
      unitId: m.unitId,
      unitName: m.unitName,
      uid: m.residentUid,
      name: m.name,
    );
  }
  final uid = ref.watch(uidProvider);
  final home = ref.watch(managerHomeFlatProvider).value;
  if (uid == null || home == null) return null;
  final unit = ref.watch(unitByIdProvider)[home.unitId];
  if (unit == null) return null; // the flat was deleted
  final account = ref.watch(accountDetailsProvider).value?.fullName ?? '';
  final display = ref.watch(authStateProvider).value?.displayName ?? '';
  return (
    managerUid: uid,
    propertyId: unit.propertyId,
    unitId: unit.id,
    unitName: unit.name,
    uid: uid,
    name: account.isNotEmpty ? account : (display.isNotEmpty ? display : (ref.watch(profileProvider).value?.name ?? '')),
  );
});

/// The private expenses of my flat (a resident's flat, or the manager's home).
final residentFlatExpensesProvider = StreamProvider<List<FlatExpense>>((ref) {
  final f = ref.watch(myFlatProvider);
  if (f == null) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(f.managerUid)
      .collection(kFlatExpensesCollection)
      // The rules require this filter: residents may only list their flat.
      .where('unitId', isEqualTo: f.unitId)
      .snapshots()
      .map(_parse);
});

/// Manager: private expenses of every flat in their buildings.
final managerFlatExpensesProvider = StreamProvider<List<FlatExpense>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(uid)
      .collection(kFlatExpensesCollection)
      .snapshots()
      .map(_parse);
});

/// Writes for residents of a flat. Any resident linked to the flat can add,
/// edit or delete its entries.
class FlatExpenseService {
  FlatExpenseService(this.db, this.flat);
  final FirebaseFirestore db;
  final MyFlat flat;

  CollectionReference<Map<String, dynamic>> get _col =>
      db.collection('users').doc(flat.managerUid).collection(kFlatExpensesCollection);

  Future<void> save(FlatExpense e) =>
      e.id.isEmpty ? _col.add(e.toMap()) : _col.doc(e.id).set(e.toMap());

  Future<void> delete(String id) => _col.doc(id).delete();
}

final flatExpenseServiceProvider = Provider<FlatExpenseService?>((ref) {
  final f = ref.watch(myFlatProvider);
  return f == null ? null : FlatExpenseService(ref.watch(firestoreProvider), f);
});
