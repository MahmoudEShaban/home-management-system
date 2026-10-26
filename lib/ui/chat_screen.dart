import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../data/chat.dart';
import '../data/community.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import 'common.dart';

/// Bumped when a room is marked as seen, so unread badges refresh.
final chatSeenTickProvider = StateProvider<int>((ref) => 0);

// ─────────────────────────── App bar button ───────────────────────────

/// Chat icon with an unread badge. Residents open their building's chat;
/// managers open it directly (one building) or pick a building.
class ChatButton extends ConsumerWidget {
  const ChatButton({super.key, this.manager = false});
  final bool manager;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    ref.watch(chatSeenTickProvider);
    final prefs = ref.watch(prefsProvider);
    final uid = ref.watch(uidProvider) ?? '';
    final List<(ChatRoom, String)> rooms;
    if (manager) {
      rooms = [
        for (final p in ref.watch(propertiesProvider).value ?? const <Property>[])
          ((managerUid: uid, propertyId: p.id), p.name),
      ];
    } else {
      final r = ref.watch(residentChatRoomProvider);
      final m = ref.watch(membershipProvider);
      rooms = r == null ? const [] : [(r, ref.watch(residentPropertyProvider).value?.name ?? m?.propertyName ?? '')];
    }
    if (rooms.isEmpty) return const SizedBox.shrink();
    var unread = 0;
    for (final (room, _) in rooms) {
      unread += unreadCount(prefs, room, ref.watch(chatMessagesProvider(room)).value ?? const [], uid);
    }
    return IconButton(
      tooltip: t.buildingChat,
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.forum_outlined),
      ),
      onPressed: () => rooms.length == 1
          ? push(context, ChatScreen(room: rooms.single.$1, title: rooms.single.$2, manager: manager))
          : push(context, BuildingChatsScreen(rooms: rooms)),
    );
  }
}

/// Manager with several buildings: pick a chat room.
class BuildingChatsScreen extends ConsumerWidget {
  const BuildingChatsScreen({super.key, required this.rooms});
  final List<(ChatRoom, String)> rooms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    ref.watch(chatSeenTickProvider);
    final prefs = ref.watch(prefsProvider);
    final uid = ref.watch(uidProvider) ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(t.buildingChats)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text(t.chatRetentionHint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          gap12,
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final (room, name) in rooms)
                Builder(builder: (context) {
                  final msgs = ref.watch(chatMessagesProvider(room)).value ?? const <ChatMessage>[];
                  final unread = unreadCount(prefs, room, msgs, uid);
                  final last = msgs.isEmpty ? null : msgs.last;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: cs.primaryContainer,
                      child: Icon(Icons.apartment, color: cs.onPrimaryContainer),
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      last == null ? t.noMessagesYet : '${last.senderName}: ${last.text}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: unread > 0 ? Badge(label: Text('$unread')) : const Icon(Icons.chevron_right),
                    onTap: () => push(context, ChatScreen(room: room, title: name, manager: true)),
                  );
                }),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Chat room ───────────────────────────

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.room, required this.title, this.manager = false});
  final ChatRoom room;
  final String title;
  final bool manager;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = context.t;
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final uid = ref.read(uidProvider) ?? '';
    final String name;
    final String flat;
    if (widget.manager) {
      final profile = ref.read(profileProvider).value;
      final display = ref.read(authStateProvider).value?.displayName ?? '';
      name = (profile?.name.isNotEmpty ?? false) ? profile!.name : (display.isNotEmpty ? display : t.roleManager);
      flat = '';
    } else {
      final m = ref.read(membershipProvider);
      name = m?.name ?? '';
      flat = m?.unitName ?? '';
    }
    final now = DateTime.now();
    _text.clear();
    try {
      await ref.read(chatServiceProvider).send(
            widget.room,
            ChatMessage(
              text: text.length > kChatMaxLength ? text.substring(0, kChatMaxLength) : text,
              senderUid: uid,
              senderName: name,
              senderFlat: flat,
              fromManager: widget.manager,
              createdAt: now,
              expireAt: now.add(kChatRetention),
            ),
          );
    } catch (e) {
      if (mounted) {
        _text.text = text;
        toast(context, '${t.somethingWrong}: $e');
      }
    }
  }

  Future<void> _delete(ChatMessage m) async {
    final t = context.t;
    if (!await confirmDialog(context, t.deleteMessageConfirm, confirmLabel: t.delete)) return;
    try {
      await ref.read(chatServiceProvider).delete(widget.room, m.id);
    } catch (e) {
      if (mounted) toast(context, '${t.somethingWrong}: $e');
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final uid = ref.watch(uidProvider) ?? '';
    final async = ref.watch(chatMessagesProvider(widget.room));
    final now = DateTime.now();
    // The query may still hold a message that expired while the room is open.
    final msgs = (async.value ?? const <ChatMessage>[]).where((m) => m.expireAt.isAfter(now)).toList();
    if (msgs.length != _lastCount) {
      _lastCount = msgs.length;
      _scrollToEnd();
      final prefs = ref.read(prefsProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        markChatSeen(prefs, widget.room, msgs);
        if (mounted) ref.read(chatSeenTickProvider.notifier).state++;
      });
    }
    final lang = Localizations.localeOf(context).languageCode;
    final time = DateFormat.jm(lang);

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(t.buildingChat, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ]),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: cs.surfaceContainerHigh,
          child: Row(children: [
            Icon(Icons.schedule, size: 16, color: cs.onSurfaceVariant),
            gap8,
            Expanded(child: Text(t.chatRetentionHint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
          ]),
        ),
        Expanded(
          child: async.isLoading && msgs.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : async.hasError
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('${t.somethingWrong}: ${async.error}', textAlign: TextAlign.center),
                      ),
                    )
                  : msgs.isEmpty
                      ? EmptyState(icon: Icons.forum_outlined, message: t.chatEmpty)
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          itemCount: msgs.length,
                          itemBuilder: (context, i) {
                            final m = msgs[i];
                            final mine = m.senderUid == uid;
                            final prev = i == 0 ? null : msgs[i - 1];
                            final newDay = prev == null ||
                                prev.createdAt.day != m.createdAt.day ||
                                prev.createdAt.month != m.createdAt.month;
                            final sameSender = prev != null && !newDay && prev.senderUid == m.senderUid &&
                                m.createdAt.difference(prev.createdAt).inMinutes < 5;
                            return Column(children: [
                              if (newDay)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                        color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
                                    child: Text(_dayLabel(context, m.createdAt),
                                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                  ),
                                ),
                              _Bubble(
                                message: m,
                                mine: mine,
                                showName: !mine && !sameSender,
                                time: time.format(m.createdAt),
                                onLongPress: mine || widget.manager ? () => _delete(m) : null,
                              ),
                            ]);
                          },
                        ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: kChatMaxLength,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: t.typeMessage,
                    counterText: '',
                    filled: true,
                    fillColor: cs.surfaceContainerHigh,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: t.send,
                onPressed: _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  String _dayLabel(BuildContext context, DateTime d) {
    final t = context.t;
    final today = DateTime.now();
    final y = today.subtract(const Duration(days: 1));
    if (d.year == today.year && d.month == today.month && d.day == today.day) return t.today;
    if (d.year == y.year && d.month == y.month && d.day == y.day) return t.yesterday;
    return context.fmtDate(d);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.showName,
    required this.time,
    this.onLongPress,
  });
  final ChatMessage message;
  final bool mine;
  final bool showName;
  final String time;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final bg = mine ? cs.primary : (message.fromManager ? cs.tertiaryContainer : cs.surfaceContainerHighest);
    final fg = mine ? cs.onPrimary : (message.fromManager ? cs.onTertiaryContainer : cs.onSurface);
    final who = [
      message.senderName,
      if (message.fromManager) t.roleManager else if (message.senderFlat.isNotEmpty) message.senderFlat,
    ].where((s) => s.isNotEmpty).join(' · ');
    return Entrance(
      offset: 8,
      duration: const Duration(milliseconds: 250),
      child: Align(
        alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          child: Padding(
            padding: EdgeInsets.only(top: showName ? 8 : 2),
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadiusDirectional.only(
                    topStart: const Radius.circular(16),
                    topEnd: const Radius.circular(16),
                    bottomStart: Radius.circular(mine ? 16 : 4),
                    bottomEnd: Radius.circular(mine ? 4 : 16),
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (showName)
                    Text(who,
                        style: TextStyle(
                            color: message.fromManager ? fg : cs.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                  Text(message.text, style: TextStyle(color: fg, fontSize: 15, height: 1.3)),
                  const SizedBox(height: 2),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(time, style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 10)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
