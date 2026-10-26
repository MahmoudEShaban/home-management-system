// Private flat expenses: costs a flat's residents record for their own flat
// (a repair inside the flat, its own electricity meter, furniture, …).
//
// Stored at users/{managerUid}/flatExpenses/{id}. Firestore rules let only
// residents linked to that flat read and write them; the building manager
// (the account that owns users/{managerUid}) can see every flat's entries.
// They are never split between flats and are not part of the building's
// expenses, dues or fund balance.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'community.dart';
import 'models.dart';
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

/// Resident: the private expenses of their own flat.
final residentFlatExpensesProvider = StreamProvider<List<FlatExpense>>((ref) {
  final m = ref.watch(membershipProvider);
  if (m == null) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(m.managerUid)
      .collection(kFlatExpensesCollection)
      // The rules require this filter: residents may only list their flat.
      .where('unitId', isEqualTo: m.unitId)
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
  FlatExpenseService(this.db, this.membership);
  final FirebaseFirestore db;
  final JoinRequest membership;

  CollectionReference<Map<String, dynamic>> get _col =>
      db.collection('users').doc(membership.managerUid).collection(kFlatExpensesCollection);

  Future<void> save(FlatExpense e) =>
      e.id.isEmpty ? _col.add(e.toMap()) : _col.doc(e.id).set(e.toMap());

  Future<void> delete(String id) => _col.doc(id).delete();
}

final flatExpenseServiceProvider = Provider<FlatExpenseService?>((ref) {
  final m = ref.watch(membershipProvider);
  return m == null ? null : FlatExpenseService(ref.watch(firestoreProvider), m);
});
