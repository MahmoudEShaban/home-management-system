// In-app inbox. Works on the free Firebase (Spark) plan: the app writes one
// inbox item per recipient, and each phone turns new items into system
// notifications itself (see local_alerts.dart).
//
// Firestore layout
//   inbox/{uid}/items/{id}        one copy per recipient (title, body, read)
//   users/{managerUid}/announcements/{id}   history of messages a manager sent

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'community.dart';
import 'models.dart';
import 'providers.dart';

String _s(dynamic v) => v == null ? '' : '$v';
DateTime _dt(dynamic v) =>
    v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : DateTime.now();

enum NoticeType { expense, announcement, proposal, decision }

class InboxItem {
  final String id;
  final String title;
  final String body;
  final NoticeType type;
  final String senderName;
  final String senderUid;
  final String propertyName;
  final bool read;
  final DateTime createdAt;

  const InboxItem({
    this.id = '',
    required this.title,
    required this.body,
    required this.type,
    this.senderName = '',
    this.senderUid = '',
    this.propertyName = '',
    this.read = false,
    required this.createdAt,
  });

  factory InboxItem.fromMap(String id, Map<String, dynamic> m) => InboxItem(
        id: id,
        title: _s(m['title']),
        body: _s(m['body']),
        type: NoticeType.values.asNameMap()[m['type']] ?? NoticeType.announcement,
        senderName: _s(m['senderName']),
        senderUid: _s(m['senderUid']),
        propertyName: _s(m['propertyName']),
        read: m['read'] == true,
        createdAt: _dt(m['createdAt']),
      );

  Map<String, dynamic> toMap({required String senderUid}) => {
        'title': title,
        'body': body,
        'type': type.name,
        'senderUid': senderUid,
        'senderName': senderName,
        'propertyName': propertyName,
        'read': false,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };
}

class Announcement {
  final String id;
  final String title;
  final String body;
  final String target; // human-readable audience
  final int recipients;
  final DateTime sentAt;

  const Announcement(this.id, this.title, this.body, this.target, this.recipients, this.sentAt);

  factory Announcement.fromMap(String id, Map<String, dynamic> m) => Announcement(
        id,
        _s(m['title']),
        _s(m['body']),
        _s(m['target']),
        (m['recipients'] as num?)?.toInt() ?? 0,
        _dt(m['sentAt']),
      );
}

// ─────────────────────────────── Sending ───────────────────────────────

class Notifier {
  Notifier(this.db, this.senderUid);
  final FirebaseFirestore db;
  final String senderUid;

  /// Writes one inbox item per recipient (batched, 400 per commit).
  Future<int> send(Map<String, InboxItem> itemsByUid) async {
    var batch = db.batch();
    var n = 0;
    for (final e in itemsByUid.entries) {
      batch.set(db.collection('inbox').doc(e.key).collection('items').doc(), e.value.toMap(senderUid: senderUid));
      if (++n % 400 == 0) {
        await batch.commit();
        batch = db.batch();
      }
    }
    if (n % 400 != 0) await batch.commit();
    return n;
  }

  Future<int> sendSame(Iterable<String> uids, InboxItem item) =>
      send({for (final u in uids.toSet()) u: item});
}

final notifierProvider = Provider<Notifier?>((ref) {
  final uid = ref.watch(uidProvider);
  return uid == null ? null : Notifier(ref.watch(firestoreProvider), uid);
});

/// Manager: tell every linked resident of the expense's building about it,
/// with their own share in the message.
Future<void> notifyExpenseAdded(
  WidgetRef ref,
  Expense e, {
  required String managerName,
  required String currency,
  required bool arabic,
}) async {
  final notifier = ref.read(notifierProvider);
  if (notifier == null) return;
  final members = (ref.read(membersProvider).value ?? const <Member>[])
      .where((m) => m.propertyId == e.propertyId && (e.unitId.isEmpty || m.unitId == e.unitId))
      .toList();
  if (members.isEmpty) return;
  final property = ref.read(propertyByIdProvider)[e.propertyId];
  String money(double v) => '${v == v.roundToDouble() ? v.toInt() : v.toStringAsFixed(2)} $currency';
  final category = _categoryName(e.category, arabic);
  final now = DateTime.now();
  await notifier.send({
    for (final m in members)
      m.uid: InboxItem(
        title: arabic ? 'مصروف جديد: $category' : 'New expense: $category',
        body: [
          if (e.vendor.isNotEmpty) e.vendor,
          arabic ? 'الإجمالي ${money(e.amount)}' : 'Total ${money(e.amount)}',
          if (e.shareFor(m.unitId) > 0)
            arabic ? 'نصيبك ${money(e.shareFor(m.unitId))}' : 'Your share ${money(e.shareFor(m.unitId))}',
          if (e.proposedByName.isNotEmpty) arabic ? 'أضافه ${e.proposedByName}' : 'Added by ${e.proposedByName}',
        ].join(' · '),
        type: NoticeType.expense,
        senderName: managerName,
        propertyName: property?.name ?? '',
        createdAt: now,
      ),
  });
}

String _num(double v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(2);

String _categoryName(ExpenseCategory c, bool ar) {
  const en = {
    ExpenseCategory.electricity: 'Electricity',
    ExpenseCategory.water: 'Water',
    ExpenseCategory.gas: 'Gas',
    ExpenseCategory.internet: 'Internet',
    ExpenseCategory.maintenance: 'Maintenance',
    ExpenseCategory.cleaning: 'Cleaning',
    ExpenseCategory.security: 'Security',
    ExpenseCategory.elevator: 'Elevator',
    ExpenseCategory.taxes: 'Taxes & fees',
    ExpenseCategory.other: 'Other',
  };
  const arabic = {
    ExpenseCategory.electricity: 'كهرباء',
    ExpenseCategory.water: 'مياه',
    ExpenseCategory.gas: 'غاز',
    ExpenseCategory.internet: 'إنترنت',
    ExpenseCategory.maintenance: 'صيانة',
    ExpenseCategory.cleaning: 'نظافة',
    ExpenseCategory.security: 'أمن وحراسة',
    ExpenseCategory.elevator: 'مصعد',
    ExpenseCategory.taxes: 'ضرائب ورسوم',
    ExpenseCategory.other: 'أخرى',
  };
  return (ar ? arabic : en)[c]!;
}

/// Resident → manager: a new expense is waiting for approval.
Future<void> notifyProposalSubmitted(WidgetRef ref, ExpenseProposal p, {required bool arabic}) async {
  final notifier = ref.read(notifierProvider);
  if (notifier == null) return;
  final category = _categoryName(p.category, arabic);
  await notifier.sendSame([p.managerUid], InboxItem(
    title: arabic ? 'مصروف في انتظار موافقتك' : 'Expense waiting for your approval',
    body: '$category · ${_num(p.amount)} · ${p.residentName} (${p.unitName})',
    type: NoticeType.proposal,
    senderName: p.residentName,
    createdAt: DateTime.now(),
  ));
}

/// Manager → resident: their submission was approved or declined.
/// Resident → manager: the flat's status changed (occupied / closed).
Future<void> notifyFlatStatusChanged(WidgetRef ref,
    {required String managerUid,
    required String residentName,
    required String unitName,
    required bool occupied,
    required bool arabic}) async {
  final notifier = ref.read(notifierProvider);
  if (notifier == null) return;
  await notifier.sendSame([managerUid], InboxItem(
    title: arabic ? 'تغيرت حالة شقة' : 'Flat status changed',
    body: arabic
        ? '$unitName · ${occupied ? 'مشغولة (يسكنها المالك)' : 'مغلقة'} · $residentName'
        : '$unitName · ${occupied ? 'Occupied' : 'Closed'} · $residentName',
    type: NoticeType.decision,
    senderName: residentName,
    createdAt: DateTime.now(),
  ));
}

Future<void> notifyProposalDecision(WidgetRef ref, ExpenseProposal p,
    {required bool approved, String note = '', required String managerName, required bool arabic}) async {
  final notifier = ref.read(notifierProvider);
  if (notifier == null) return;
  final category = _categoryName(p.category, arabic);
  await notifier.sendSame([p.residentUid], InboxItem(
    title: approved
        ? (arabic ? 'تمت الموافقة على مصروفك' : 'Your expense was approved')
        : (arabic ? 'تم رفض مصروفك' : 'Your expense was declined'),
    body: [category, _num(p.amount), if (note.isNotEmpty) note].join(' · '),
    type: NoticeType.decision,
    senderName: managerName,
    createdAt: DateTime.now(),
  ));
}

/// Manager announcement. [propertyId] null = all buildings; [unitId] narrows
/// it to one flat. Returns how many residents received it.
Future<int> sendAnnouncement(
  WidgetRef ref, {
  required String title,
  required String body,
  String? propertyId,
  String? unitId,
  required String targetLabel,
  required String managerName,
}) async {
  final notifier = ref.read(notifierProvider);
  final uid = ref.read(uidProvider);
  if (notifier == null || uid == null) return 0;
  final props = ref.read(propertyByIdProvider);
  final members = (ref.read(membersProvider).value ?? const <Member>[])
      .where((m) => propertyId == null || m.propertyId == propertyId)
      .where((m) => unitId == null || m.unitId == unitId)
      .toList();
  final now = DateTime.now();
  final count = await notifier.send({
    for (final m in members)
      m.uid: InboxItem(
        title: title,
        body: body,
        type: NoticeType.announcement,
        senderName: managerName,
        propertyName: props[m.propertyId]?.name ?? '',
        createdAt: now,
      ),
  });
  await ref.read(firestoreProvider).collection('users').doc(uid).collection('announcements').add({
    'title': title,
    'body': body,
    'target': targetLabel,
    'propertyId': propertyId ?? '',
    'unitId': unitId ?? '',
    'recipients': count,
    'sentAt': now.millisecondsSinceEpoch,
  });
  return count;
}

// ─────────────────────────────── Reading ───────────────────────────────

final inboxProvider = StreamProvider<List<InboxItem>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection('inbox')
      .doc(uid)
      .collection('items')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map((d) => InboxItem.fromMap(d.id, d.data())).toList());
});

final unreadCountProvider =
    Provider<int>((ref) => (ref.watch(inboxProvider).value ?? const <InboxItem>[]).where((i) => !i.read).length);

final announcementsProvider = StreamProvider<List<Announcement>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(uid)
      .collection('announcements')
      .orderBy('sentAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map((d) => Announcement.fromMap(d.id, d.data())).toList());
});

class InboxActions {
  InboxActions(this.db, this.uid);
  final FirebaseFirestore db;
  final String uid;

  CollectionReference<Map<String, dynamic>> get _items => db.collection('inbox').doc(uid).collection('items');

  Future<void> markRead(String id) => _items.doc(id).update({'read': true});

  Future<void> markAllRead(List<InboxItem> items) async {
    final batch = db.batch();
    for (final i in items.where((i) => !i.read)) {
      batch.update(_items.doc(i.id), {'read': true});
    }
    await batch.commit();
  }

  Future<void> delete(String id) => _items.doc(id).delete();
}

final inboxActionsProvider = Provider<InboxActions?>((ref) {
  final uid = ref.watch(uidProvider);
  return uid == null ? null : InboxActions(ref.watch(firestoreProvider), uid);
});
