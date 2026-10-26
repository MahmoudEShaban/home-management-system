// Building chat: one chat room per building for its manager and residents.
//
// Messages live at users/{managerUid}/chats/{propertyId}/messages/{id} and
// are kept for [kChatRetention] (3 days). Each message carries `expireAt`.
// The app only shows unexpired messages, Firestore rules refuse to return
// them a day after they expire, and the manager's app deletes expired
// messages of all its buildings.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'community.dart';
import 'providers.dart';

const kChatRetention = Duration(days: 3);
const kChatMaxLength = 1000;
const _kChatSeen = 'chat.seen.'; // + propertyId → millis of the last message seen

/// Which building's chat: the manager account that owns it + building id.
typedef ChatRoom = ({String managerUid, String propertyId});

class ChatMessage {
  final String id;
  final String text;
  final String senderUid;
  final String senderName;

  /// Flat name for residents, empty for the manager.
  final String senderFlat;
  final bool fromManager;
  final DateTime createdAt;
  final DateTime expireAt;

  const ChatMessage({
    this.id = '',
    required this.text,
    required this.senderUid,
    this.senderName = '',
    this.senderFlat = '',
    this.fromManager = false,
    required this.createdAt,
    required this.expireAt,
  });

  factory ChatMessage.fromMap(String id, Map<String, dynamic> m) {
    DateTime ts(dynamic v) => v is Timestamp
        ? v.toDate()
        : v is num
            ? DateTime.fromMillisecondsSinceEpoch(v.toInt())
            : DateTime.now();
    return ChatMessage(
      id: id,
      text: '${m['text'] ?? ''}',
      senderUid: '${m['senderUid'] ?? ''}',
      senderName: '${m['senderName'] ?? ''}',
      senderFlat: '${m['senderFlat'] ?? ''}',
      fromManager: m['fromManager'] == true,
      createdAt: ts(m['createdAt']),
      expireAt: ts(m['expireAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'text': text,
        'senderUid': senderUid,
        'senderName': senderName,
        'senderFlat': senderFlat,
        'fromManager': fromManager,
        'createdAt': Timestamp.fromDate(createdAt),
        'expireAt': Timestamp.fromDate(expireAt),
      };
}

CollectionReference<Map<String, dynamic>> chatMessagesOf(FirebaseFirestore db, ChatRoom room) =>
    db.collection('users').doc(room.managerUid).collection('chats').doc(room.propertyId).collection('messages');

/// Messages of the last 3 days, oldest first. The `expireAt` filter is also
/// what the Firestore rules require.
final chatMessagesProvider = StreamProvider.autoDispose.family<List<ChatMessage>, ChatRoom>((ref, room) {
  if (room.managerUid.isEmpty || room.propertyId.isEmpty) return Stream.value(const []);
  return chatMessagesOf(ref.watch(firestoreProvider), room)
      .where('expireAt', isGreaterThan: Timestamp.now())
      .orderBy('expireAt', descending: true)
      .limit(300)
      .snapshots()
      .map((s) => s.docs.map((d) => ChatMessage.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
});

/// The resident's own building chat (null if not linked yet).
final residentChatRoomProvider = Provider<ChatRoom?>((ref) {
  final m = ref.watch(membershipProvider);
  return m == null ? null : (managerUid: m.managerUid, propertyId: m.propertyId);
});

class ChatService {
  ChatService(this.db);
  final FirebaseFirestore db;

  Future<void> send(ChatRoom room, ChatMessage msg) => chatMessagesOf(db, room).add(msg.toMap());

  Future<void> delete(ChatRoom room, String id) => chatMessagesOf(db, room).doc(id).delete();

  /// Manager: deletes expired messages of one building's room.
  Future<void> purgeExpired(ChatRoom room) async {
    try {
      final old = await chatMessagesOf(db, room)
          .where('expireAt', isLessThanOrEqualTo: Timestamp.now())
          .limit(400)
          .get();
      if (old.docs.isEmpty) return;
      final batch = db.batch();
      for (final d in old.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Chat cleanup skipped: $e');
    }
  }
}

final chatServiceProvider = Provider((ref) => ChatService(ref.watch(firestoreProvider)));

/// Unread messages from others since the last time this phone showed the room.
int unreadCount(SharedPreferences prefs, ChatRoom room, List<ChatMessage> msgs, String myUid) {
  final seen = prefs.getInt('$_kChatSeen${room.propertyId}') ?? 0;
  return msgs.where((m) => m.senderUid != myUid && m.createdAt.millisecondsSinceEpoch > seen).length;
}

void markChatSeen(SharedPreferences prefs, ChatRoom room, List<ChatMessage> msgs) {
  if (msgs.isEmpty) return;
  final last = msgs.last.createdAt.millisecondsSinceEpoch;
  if ((prefs.getInt('$_kChatSeen${room.propertyId}') ?? 0) < last) {
    prefs.setInt('$_kChatSeen${room.propertyId}', last);
  }
}

/// Manager: clears expired messages of every building once per app start.
final chatCleanupProvider = FutureProvider<void>((ref) async {
  final uid = ref.watch(uidProvider);
  final props = ref.watch(propertiesProvider).value;
  if (uid == null || props == null) return;
  final service = ref.read(chatServiceProvider);
  for (final p in props) {
    await service.purgeExpired((managerUid: uid, propertyId: p.id));
  }
});
