// Resident accounts: building codes, join requests and approved members.
//
// Firestore layout
//   buildingCodes/{code}                 public lookup (get only) for sign-up
//   joinRequests/{residentUid}           one request per resident account
//   users/{managerUid}/members/{residentUid}   approved link resident → flat
//   users/{uid}.role                     'manager' or 'resident'

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'providers.dart';

String _s(dynamic v) => v == null ? '' : '$v';
DateTime _dt(dynamic v) =>
    v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : DateTime.now();

// ─────────────────────────────── Roles ───────────────────────────────

const kRoleManager = 'manager';
const kRoleResident = 'resident';

/// Account that manages buildings and is also a resident of a flat.
const kRoleBoth = 'both';
const _kPendingRole = 'auth.pendingRole';
const _kActiveView = 'view.active';

/// For accounts with both roles: which side of the app is showing.
class ActiveViewController extends StateNotifier<String> {
  ActiveViewController(this._prefs)
      : super(_prefs.getString(_kActiveView) == kRoleResident ? kRoleResident : kRoleManager);
  final SharedPreferences _prefs;

  void set(String view) {
    state = view;
    _prefs.setString(_kActiveView, view);
  }

  void toggle() => set(state == kRoleResident ? kRoleManager : kRoleResident);
}

final activeViewProvider = StateNotifierProvider<ActiveViewController, String>(
    (ref) => ActiveViewController(ref.watch(prefsProvider)));

/// Whether the signed-in account can switch between manager and resident.
final hasBothRolesProvider =
    Provider<bool>((ref) => ref.watch(roleProvider).value == kRoleBoth);

/// Remembers the role picked on the sign-in screen until the account exists.
void setPendingRole(SharedPreferences prefs, String role) =>
    prefs.setString(_kPendingRole, role);

/// The signed-in account's role. Accounts created before roles existed are
/// managers.
final roleProvider = StreamProvider<String>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(kRoleManager);
  final prefs = ref.watch(prefsProvider);
  final doc = ref.watch(firestoreProvider).collection('users').doc(uid);

  /// Role for an account whose document has no role yet.
  Future<String> decide(Map<String, dynamic>? data, {required bool save}) async {
    var chosen = prefs.getString(_kPendingRole) ?? kRoleManager;
    // An account that already manages buildings stays a manager.
    if (chosen == kRoleResident) {
      try {
        final hasData = data?['profile'] != null ||
            (await doc.collection('properties').limit(1).get()).docs.isNotEmpty;
        if (hasData) chosen = kRoleManager;
      } catch (_) {
        // Offline: keep the chosen role.
      }
    }
    if (save) {
      unawaited(doc
          .set({'role': chosen}, SetOptions(merge: true))
          .catchError((Object e) => debugPrint('Role save failed: $e')));
    }
    return chosen;
  }

  return () async* {
    await for (final s in doc.snapshots()) {
      final role = s.data()?['role'];
      if (role is String && role.isNotEmpty) {
        unawaited(prefs.remove(_kPendingRole));
        yield role;
        continue;
      }
      if (s.exists || !s.metadata.isFromCache) {
        yield await decide(s.data(), save: true);
        continue;
      }
      // Nothing cached for this account (new device, or an account created
      // before roles existed). Ask the server once instead of waiting for a
      // snapshot that may never change.
      try {
        final server = await doc
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 8));
        final r = server.data()?['role'];
        if (r is String && r.isNotEmpty) {
          yield r;
        } else {
          yield await decide(server.data(), save: true);
        }
      } catch (_) {
        // Offline: use the choice made at sign-in without saving it, so a
        // resident's stored role is never overwritten.
        yield prefs.getString(_kPendingRole) ?? kRoleManager;
      }
    }
  }();
});

// ─────────────────────────────── Models ───────────────────────────────

class CodeFlat {
  final String id;
  final String name;
  final String floor;
  const CodeFlat(this.id, this.name, this.floor);

  factory CodeFlat.fromMap(Map<String, dynamic> m) =>
      CodeFlat(_s(m['id']), _s(m['name']), _s(m['floor']));
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'floor': floor};
}

/// Public card a resident unlocks with the building code.
class BuildingCode {
  final String code;
  final String managerUid;
  final String propertyId;
  final String propertyName;
  final String address;
  final List<CodeFlat> flats;

  /// Flats that already have an approved resident account.
  final List<String> takenUnitIds;

  const BuildingCode({
    required this.code,
    required this.managerUid,
    required this.propertyId,
    required this.propertyName,
    this.address = '',
    this.flats = const [],
    this.takenUnitIds = const [],
  });

  factory BuildingCode.fromMap(String code, Map<String, dynamic> m) => BuildingCode(
        code: code,
        managerUid: _s(m['managerUid']),
        propertyId: _s(m['propertyId']),
        propertyName: _s(m['propertyName']),
        address: _s(m['address']),
        flats: (m['flats'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => CodeFlat.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        takenUnitIds: (m['takenUnitIds'] as List? ?? const []).map((e) => '$e').toList(),
      );

  Map<String, dynamic> toMap() => {
        'managerUid': managerUid,
        'propertyId': propertyId,
        'propertyName': propertyName,
        'address': address,
        'flats': flats.map((f) => f.toMap()).toList(),
        'takenUnitIds': takenUnitIds,
      };
}

enum RequestStatus { pending, approved, rejected, removed }

class JoinRequest {
  final String residentUid;
  final String code;
  final String managerUid;
  final String propertyId;
  final String propertyName;
  final String unitId;
  final String unitName;
  final String name;
  final String phone;
  final String email;
  final RequestStatus status;
  final DateTime createdAt;

  const JoinRequest({
    required this.residentUid,
    required this.code,
    required this.managerUid,
    required this.propertyId,
    required this.propertyName,
    required this.unitId,
    required this.unitName,
    required this.name,
    this.phone = '',
    this.email = '',
    this.status = RequestStatus.pending,
    required this.createdAt,
  });

  factory JoinRequest.fromMap(String id, Map<String, dynamic> m) => JoinRequest(
        residentUid: id,
        code: _s(m['code']),
        managerUid: _s(m['managerUid']),
        propertyId: _s(m['propertyId']),
        propertyName: _s(m['propertyName']),
        unitId: _s(m['unitId']),
        unitName: _s(m['unitName']),
        name: _s(m['name']),
        phone: _s(m['phone']),
        email: _s(m['email']),
        status: RequestStatus.values.asNameMap()[m['status']] ?? RequestStatus.pending,
        createdAt: _dt(m['createdAt']),
      );

  Map<String, dynamic> toMap() => {
        'residentUid': residentUid,
        'code': code,
        'managerUid': managerUid,
        'propertyId': propertyId,
        'propertyName': propertyName,
        'unitId': unitId,
        'unitName': unitName,
        'name': name,
        'phone': phone,
        'email': email,
        'status': status.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };
}

/// Approved resident account linked to one flat.
class Member {
  final String uid;
  final String propertyId;
  final String unitId;
  final String name;
  final String phone;
  final String email;
  final DateTime joinedAt;

  const Member({
    required this.uid,
    required this.propertyId,
    required this.unitId,
    required this.name,
    this.phone = '',
    this.email = '',
    required this.joinedAt,
  });

  factory Member.fromMap(String id, Map<String, dynamic> m) => Member(
        uid: id,
        propertyId: _s(m['propertyId']),
        unitId: _s(m['unitId']),
        name: _s(m['name']),
        phone: _s(m['phone']),
        email: _s(m['email']),
        joinedAt: _dt(m['joinedAt']),
      );

  Map<String, dynamic> toMap() => {
        'propertyId': propertyId,
        'unitId': unitId,
        'name': name,
        'phone': phone,
        'email': email,
        'joinedAt': joinedAt.millisecondsSinceEpoch,
      };
}

// ─────────────────────────────── Service ───────────────────────────────

class CommunityService {
  CommunityService(this.db);
  final FirebaseFirestore db;

  CollectionReference<Map<String, dynamic>> get _codes => db.collection('buildingCodes');
  CollectionReference<Map<String, dynamic>> get _requests => db.collection('joinRequests');
  CollectionReference<Map<String, dynamic>> _members(String managerUid) =>
      db.collection('users').doc(managerUid).collection('members');

  /// Normalises what a resident typed ("ab-12 cd" → "AB12CD").
  static String clean(String code) => code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  Future<BuildingCode?> lookup(String code) async {
    final c = clean(code);
    if (c.isEmpty) return null;
    final snap = await _codes.doc(c).get();
    final data = snap.data();
    return data == null ? null : BuildingCode.fromMap(c, data);
  }

  /// Creates a new unique code for [property].
  Future<String> createCode({
    required String managerUid,
    required Property property,
    required List<Unit> units,
    required Set<String> takenUnitIds,
  }) async {
    // No 0/O/1/I so codes are easy to read out loud.
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    for (var attempt = 0; attempt < 10; attempt++) {
      final code = List.generate(6, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
      final existing = await _codes.doc(code).get();
      if (existing.exists) continue;
      await _codes.doc(code).set(codeFor(code, managerUid, property, units, takenUnitIds).toMap());
      return code;
    }
    throw Exception('Could not create a building code, please try again');
  }

  static BuildingCode codeFor(String code, String managerUid, Property property,
          List<Unit> units, Set<String> takenUnitIds) =>
      BuildingCode(
        code: code,
        managerUid: managerUid,
        propertyId: property.id,
        propertyName: property.name,
        address: property.address,
        flats: [
          for (final u in units.where((u) => u.propertyId == property.id)) CodeFlat(u.id, u.name, u.floor),
        ],
        takenUnitIds: [
          for (final u in units.where((u) => u.propertyId == property.id))
            if (takenUnitIds.contains(u.id)) u.id,
        ],
      );

  Future<void> deleteCode(String code) => _codes.doc(code).delete();

  Future<void> submitRequest(JoinRequest r) => _requests.doc(r.residentUid).set(r.toMap());

  Future<void> cancelRequest(String residentUid) => _requests.doc(residentUid).delete();

  Future<void> approve(JoinRequest r) async {
    final batch = db.batch()
      ..set(
          _members(r.managerUid).doc(r.residentUid),
          Member(
            uid: r.residentUid,
            propertyId: r.propertyId,
            unitId: r.unitId,
            name: r.name,
            phone: r.phone,
            email: r.email,
            joinedAt: DateTime.now(),
          ).toMap())
      ..update(_requests.doc(r.residentUid), {'status': RequestStatus.approved.name});
    await batch.commit();
  }

  Future<void> reject(JoinRequest r) =>
      _requests.doc(r.residentUid).update({'status': RequestStatus.rejected.name});

  /// Unlinks a resident from their flat. Their account remains; they can
  /// request again.
  Future<void> removeMember(String managerUid, Member m) async {
    await _members(managerUid).doc(m.uid).delete();
    // The resident may already have withdrawn their request.
    try {
      await _requests.doc(m.uid).update({'status': RequestStatus.removed.name});
    } catch (e) {
      debugPrint('Request status not updated: $e');
    }
  }

  Future<void> updateCode(BuildingCode c) => _codes.doc(c.code).set(c.toMap());
}

final communityProvider = Provider((ref) => CommunityService(ref.watch(firestoreProvider)));

// ─────────────────────────── Manager side ───────────────────────────

final buildingCodesProvider = StreamProvider<List<BuildingCode>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection('buildingCodes')
      .where('managerUid', isEqualTo: uid)
      .snapshots()
      .map((s) => s.docs.map((d) => BuildingCode.fromMap(d.id, d.data())).toList());
});

final joinRequestsProvider = StreamProvider<List<JoinRequest>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection('joinRequests')
      .where('managerUid', isEqualTo: uid)
      .snapshots()
      .map((s) => s.docs.map((d) => JoinRequest.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
});

final pendingRequestsProvider = Provider<List<JoinRequest>>((ref) =>
    (ref.watch(joinRequestsProvider).value ?? const <JoinRequest>[])
        .where((r) => r.status == RequestStatus.pending)
        .toList());

final membersProvider = StreamProvider<List<Member>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(uid)
      .collection('members')
      .snapshots()
      .map((s) => s.docs.map((d) => Member.fromMap(d.id, d.data())).toList());
});

/// Linked residents of each flat. A flat can have several (owners, family,
/// co-owners); each of them can manage it.
final membersByUnitProvider = Provider<Map<String, List<Member>>>((ref) {
  final map = <String, List<Member>>{};
  for (final m in ref.watch(membersProvider).value ?? const <Member>[]) {
    map.putIfAbsent(m.unitId, () => []).add(m);
  }
  for (final l in map.values) {
    l.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
  }
  return map;
});

/// "Ahmed, Sara" for showing who is linked to a flat.
String memberNames(List<Member>? members) =>
    (members ?? const <Member>[]).map((m) => m.name).where((n) => n.isNotEmpty).join(', ');

/// Keeps each building code's flat list and taken flats in step with the
/// manager's data. Watched by the manager home shell.
final buildingCodeSyncProvider = Provider<void>((ref) {
  final uid = ref.watch(uidProvider);
  final codes = ref.watch(buildingCodesProvider).value;
  final units = ref.watch(unitsProvider).value;
  final props = ref.watch(propertyByIdProvider);
  final members = ref.watch(membersProvider).value;
  if (uid == null || codes == null || units == null || members == null) return;
  final taken = members.map((m) => m.unitId).toSet();
  final service = ref.read(communityProvider);

  // Every building gets a code automatically.
  final withCode = codes.map((c) => c.propertyId).toSet();
  for (final p in props.values) {
    if (withCode.contains(p.id) || _creatingCodeFor.contains(p.id)) continue;
    _creatingCodeFor.add(p.id);
    unawaited(service
        .createCode(managerUid: uid, property: p, units: units, takenUnitIds: taken)
        .catchError((Object e) {
      debugPrint('Building code for ${p.name} not created: $e');
      return '';
    }).whenComplete(() => _creatingCodeFor.remove(p.id)));
  }

  for (final c in codes) {
    final p = props[c.propertyId];
    if (p == null) continue;
    final desired = CommunityService.codeFor(c.code, uid, p, units, taken);
    if (!mapEquals(_flatten(desired), _flatten(c))) {
      unawaited(service.updateCode(desired).catchError((Object e) => debugPrint('Code sync failed: $e')));
    }
  }
});

/// Buildings whose code is being created right now (avoids duplicates).
final _creatingCodeFor = <String>{};

Map<String, Object> _flatten(BuildingCode c) => {
      'name': c.propertyName,
      'address': c.address,
      'flats': c.flats.map((f) => '${f.id}|${f.name}|${f.floor}').join(','),
      'taken': ([...c.takenUnitIds]..sort()).join(','),
    };

// ─────────────────────────── Resident side ───────────────────────────

/// The signed-in resident's join request (null if none yet).
final myRequestProvider = StreamProvider<JoinRequest?>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(null);
  return ref
      .watch(firestoreProvider)
      .collection('joinRequests')
      .doc(uid)
      .snapshots()
      .map((s) => s.data() == null ? null : JoinRequest.fromMap(s.id, s.data()!));
});

/// Approved link of the signed-in resident.
final membershipProvider = Provider<JoinRequest?>((ref) {
  final r = ref.watch(myRequestProvider).value;
  return r != null && r.status == RequestStatus.approved ? r : null;
});

DocumentReference<Map<String, dynamic>> _managerDoc(Ref ref, JoinRequest m) =>
    ref.watch(firestoreProvider).collection('users').doc(m.managerUid);

final residentProfileProvider = StreamProvider<BusinessProfile>((ref) {
  final m = ref.watch(membershipProvider);
  if (m == null) return Stream.value(const BusinessProfile());
  return _managerDoc(ref, m).snapshots().map((s) =>
      BusinessProfile.fromMap((s.data()?['profile'] as Map?)?.cast<String, dynamic>()));
});

final residentPropertyProvider = StreamProvider<Property?>((ref) {
  final m = ref.watch(membershipProvider);
  if (m == null) return Stream.value(null);
  return _managerDoc(ref, m).collection('properties').doc(m.propertyId).snapshots().map(
      (s) => s.data() == null ? null : Property.fromMap(s.id, s.data()!));
});

final residentUnitProvider = StreamProvider<Unit?>((ref) {
  final m = ref.watch(membershipProvider);
  if (m == null) return Stream.value(null);
  return _managerDoc(ref, m)
      .collection('units')
      .doc(m.unitId)
      .snapshots()
      .map((s) => s.data() == null ? null : Unit.fromMap(s.id, s.data()!));
});

final residentExpensesProvider = StreamProvider<List<Expense>>((ref) {
  final m = ref.watch(membershipProvider);
  if (m == null) return Stream.value(const []);
  return _managerDoc(ref, m)
      .collection('expenses')
      .where('propertyId', isEqualTo: m.propertyId)
      .snapshots()
      .map((s) => s.docs.map((d) => Expense.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.date.compareTo(a.date)));
});

final residentInvoicesProvider = StreamProvider<List<Invoice>>((ref) {
  final m = ref.watch(membershipProvider);
  if (m == null) return Stream.value(const []);
  return _managerDoc(ref, m)
      .collection('invoices')
      .where('unitId', isEqualTo: m.unitId)
      .snapshots()
      .map((s) => s.docs
          .map((d) => Invoice.fromMap(d.id, d.data()))
          .where((i) => i.status != InvoiceStatus.cancelled)
          .toList()
        ..sort((a, b) => b.issueDate.compareTo(a.issueDate)));
});

// ─────────────────────────── Expense proposals ───────────────────────────
//
//   expenseProposals/{id}   submitted by a resident, decided by the manager

/// A resident submission: an expense they paid, or a maintenance request.
enum ProposalKind { expense, maintenance }

enum Urgency { low, normal, urgent }

class ExpenseProposal {
  final String id;
  final ProposalKind kind;

  /// Short summary, e.g. "Elevator stuck on 3rd floor" (maintenance).
  final String title;
  final Urgency urgency;
  final String managerUid;
  final String propertyId;
  final String residentUid;
  final String residentName;
  final String unitId;
  final String unitName;
  final ExpenseCategory category;
  final double amount;
  final DateTime date;
  final String vendor;
  final String notes;
  final SplitMethod split;

  /// Floors that share the cost; empty = all floors.
  final List<String> splitFloors;

  /// Shares as the resident saw them when submitting.
  final List<ExpenseShare> shares;
  final RequestStatus status;
  final String decisionNote;
  final String expenseId;
  final DateTime createdAt;

  /// Photos the resident attached (receipt, the problem, …).
  final List<String> attachmentIds;

  const ExpenseProposal({
    this.id = '',
    this.kind = ProposalKind.expense,
    this.title = '',
    this.urgency = Urgency.normal,
    required this.managerUid,
    required this.propertyId,
    required this.residentUid,
    required this.residentName,
    required this.unitId,
    required this.unitName,
    required this.category,
    required this.amount,
    required this.date,
    this.vendor = '',
    this.notes = '',
    this.split = SplitMethod.equal,
    this.splitFloors = const [],
    this.shares = const [],
    this.status = RequestStatus.pending,
    this.decisionNote = '',
    this.expenseId = '',
    required this.createdAt,
    this.attachmentIds = const [],
  });

  factory ExpenseProposal.fromMap(String id, Map<String, dynamic> m) {
    double d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return ExpenseProposal(
      id: id,
      kind: ProposalKind.values.asNameMap()[m['kind']] ?? ProposalKind.expense,
      title: _s(m['title']),
      urgency: Urgency.values.asNameMap()[m['urgency']] ?? Urgency.normal,
      managerUid: _s(m['managerUid']),
      propertyId: _s(m['propertyId']),
      residentUid: _s(m['residentUid']),
      residentName: _s(m['residentName']),
      unitId: _s(m['unitId']),
      unitName: _s(m['unitName']),
      category: ExpenseCategory.values.asNameMap()[m['category']] ?? ExpenseCategory.other,
      amount: d(m['amount']),
      date: _dt(m['date']),
      vendor: _s(m['vendor']),
      notes: _s(m['notes']),
      split: SplitMethod.values.asNameMap()[m['split']] ?? SplitMethod.equal,
      splitFloors: (m['splitFloors'] as List? ?? const []).map((e) => '$e').toList(),
      shares: (m['shares'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => ExpenseShare.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      status: RequestStatus.values.asNameMap()[m['status']] ?? RequestStatus.pending,
      decisionNote: _s(m['decisionNote']),
      expenseId: _s(m['expenseId']),
      createdAt: _dt(m['createdAt']),
      attachmentIds: (m['attachmentIds'] as List? ?? const []).map((e) => '$e').toList(),
    );
  }

  bool get isMaintenance => kind == ProposalKind.maintenance;

  Map<String, dynamic> toMap() => {
        'kind': kind.name,
        'title': title,
        'urgency': urgency.name,
        'managerUid': managerUid,
        'propertyId': propertyId,
        'residentUid': residentUid,
        'residentName': residentName,
        'unitId': unitId,
        'unitName': unitName,
        'category': category.name,
        'amount': amount,
        'date': date.millisecondsSinceEpoch,
        'vendor': vendor,
        'notes': notes,
        'split': split.name,
        'splitFloors': splitFloors,
        'shares': shares.map((e) => e.toMap()).toList(),
        'status': status.name,
        'decisionNote': decisionNote,
        'expenseId': expenseId,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'attachmentIds': attachmentIds,
      };

  /// The building expense this proposal becomes once approved.
  Expense toExpense({required List<ExpenseShare> shares}) => Expense(
        propertyId: propertyId,
        category: category,
        amount: amount,
        date: date,
        vendor: vendor,
        notes: notes,
        split: shares.isEmpty ? SplitMethod.none : split,
        splitFloors: splitFloors,
        shares: shares,
        proposedByName: residentName,
        proposalId: id,
        // The resident's photos stay with the approved expense.
        attachmentIds: attachmentIds,
        // Maintenance requests: the requester paid; other flats repay them.
        payToUid: isMaintenance ? residentUid : '',
        payToName: isMaintenance ? residentName : '',
        payToUnitId: isMaintenance ? unitId : '',
      );
}

class ProposalService {
  ProposalService(this.db);
  final FirebaseFirestore db;

  CollectionReference<Map<String, dynamic>> get _col => db.collection('expenseProposals');

  Future<void> submit(ExpenseProposal p) => _col.add(p.toMap());

  Future<void> withdraw(String id) => _col.doc(id).delete();

  Future<void> markApproved(String id, String expenseId) => _col.doc(id).update({
        'status': RequestStatus.approved.name,
        'expenseId': expenseId,
        'decisionNote': '',
      });

  Future<void> decline(String id, String note) => _col.doc(id).update({
        'status': RequestStatus.rejected.name,
        'decisionNote': note,
      });
}

final proposalServiceProvider = Provider((ref) => ProposalService(ref.watch(firestoreProvider)));

/// Manager: every proposal sent to this account.
final managerProposalsProvider = StreamProvider<List<ExpenseProposal>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection('expenseProposals')
      .where('managerUid', isEqualTo: uid)
      .snapshots()
      .map((s) => s.docs.map((d) => ExpenseProposal.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
});

final pendingProposalsProvider = Provider<List<ExpenseProposal>>((ref) =>
    (ref.watch(managerProposalsProvider).value ?? const <ExpenseProposal>[])
        .where((p) => p.status == RequestStatus.pending)
        .toList());

/// Resident: proposals this account submitted.
final myProposalsProvider = StreamProvider<List<ExpenseProposal>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection('expenseProposals')
      .where('residentUid', isEqualTo: uid)
      .snapshots()
      .map((s) => s.docs.map((d) => ExpenseProposal.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
});

/// Resident: all flats of their building (needed to preview a split).
final residentBuildingUnitsProvider = StreamProvider<List<Unit>>((ref) {
  final m = ref.watch(membershipProvider);
  if (m == null) return Stream.value(const []);
  return _managerDoc(ref, m)
      .collection('units')
      .where('propertyId', isEqualTo: m.propertyId)
      .snapshots()
      .map((s) => s.docs.map((d) => Unit.fromMap(d.id, d.data())).toList());
});

// ─────────────────────────── Dues payments (resident) ───────────────────────────

/// Resident: confirmed and claimed payments of their building, to show the
/// building overview and their own payment status.
final residentDuesPaymentsProvider = StreamProvider<List<DuesPayment>>((ref) {
  final m = ref.watch(membershipProvider);
  if (m == null) return Stream.value(const []);
  return _managerDoc(ref, m)
      .collection('duesPayments')
      .where('propertyId', isEqualTo: m.propertyId)
      .snapshots()
      .map((s) => s.docs.map((d) => DuesPayment.fromMap(d.id, d.data())).toList());
});

/// Resident: say "I've paid" for their flat's dues for a month.
Future<void> claimDuesPayment(FirebaseFirestore db, JoinRequest m, DuesPayment p) => db
    .collection('users')
    .doc(m.managerUid)
    .collection('duesPayments')
    .doc(p.id)
    .set(p.toMap());
