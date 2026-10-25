import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/community.dart';
import '../data/models.dart';
import '../data/notifications.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import 'common.dart';
import 'properties_screen.dart' show compareFloors;

IconData noticeIcon(NoticeType t) => switch (t) {
      NoticeType.expense => Icons.bolt,
      NoticeType.announcement => Icons.campaign_outlined,
      NoticeType.proposal => Icons.pending_actions_outlined,
      NoticeType.decision => Icons.task_alt,
    };

/// App-bar bell with unread count; opens the inbox.
class InboxBell extends ConsumerWidget {
  const InboxBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return IconButton(
      tooltip: context.t.notificationsTitle,
      onPressed: () => push(context, const InboxScreen()),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final items = ref.watch(inboxProvider).value ?? const <InboxItem>[];
    final actions = ref.watch(inboxActionsProvider);
    final isManager = ref.watch(roleProvider).value != kRoleResident;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.notificationsTitle),
        actions: [
          if (items.any((i) => !i.read))
            TextButton(
              onPressed: () => actions?.markAllRead(items),
              child: Text(t.markAllRead),
            ),
        ],
      ),
      floatingActionButton: isManager
          ? FloatingActionButton.extended(
              onPressed: () => pushForm(context, const ComposeMessageScreen()),
              icon: const Icon(Icons.campaign_outlined),
              label: Text(t.sendMessage),
            )
          : null,
      body: items.isEmpty
          ? EmptyState(icon: Icons.notifications_none, message: t.noNotifications)
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) {
                final n = items[i];
                return Dismissible(
                  key: ValueKey(n.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: cs.errorContainer,
                    alignment: AlignmentDirectional.centerEnd,
                    padding: const EdgeInsetsDirectional.only(end: 24),
                    child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
                  ),
                  onDismissed: (_) => actions?.delete(n.id),
                  child: ListTile(
                    tileColor: n.read ? null : cs.primaryContainer.withValues(alpha: 0.25),
                    leading: CircleAvatar(
                      backgroundColor: n.read ? cs.surfaceContainerHighest : cs.primaryContainer,
                      child: Icon(noticeIcon(n.type), size: 20,
                          color: n.read ? cs.onSurfaceVariant : cs.onPrimaryContainer),
                    ),
                    title: Text(n.title,
                        style: TextStyle(fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SizedBox(height: 2),
                      Text(n.body),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (n.senderName.isNotEmpty) n.senderName,
                          if (n.propertyName.isNotEmpty) n.propertyName,
                          '${context.fmtDate(n.createdAt)} ${TimeOfDay.fromDateTime(n.createdAt).format(context)}',
                        ].join(' · '),
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                      ),
                    ]),
                    isThreeLine: true,
                    onTap: () {
                      if (!n.read) actions?.markRead(n.id);
                    },
                  ),
                );
              },
            ),
    );
  }
}

// ─────────────────────────── Compose (manager) ───────────────────────────

class ComposeMessageScreen extends ConsumerStatefulWidget {
  const ComposeMessageScreen({super.key, this.presetPropertyId});
  final String? presetPropertyId;

  @override
  ConsumerState<ComposeMessageScreen> createState() => _ComposeMessageScreenState();
}

class _ComposeMessageScreenState extends ConsumerState<ComposeMessageScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  late String? _propertyId = widget.presetPropertyId; // null = all buildings
  String? _unitId; // null = whole building
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  List<Member> _recipients() => (ref.read(membersProvider).value ?? const <Member>[])
      .where((m) => _propertyId == null || m.propertyId == _propertyId)
      .where((m) => _unitId == null || m.unitId == _unitId)
      .toList();

  Future<void> _send() async {
    final t = context.t;
    if (!_form.currentState!.validate()) return;
    final props = ref.read(propertyByIdProvider);
    final units = ref.read(unitByIdProvider);
    final target = _propertyId == null
        ? t.allBuildings
        : [props[_propertyId]?.name ?? '', if (_unitId != null) units[_unitId]?.name ?? ''].join(' · ');
    final profile = ref.read(profileProvider).value ?? const BusinessProfile();
    setState(() => _busy = true);
    try {
      final n = await sendAnnouncement(
        ref,
        title: _title.text.trim(),
        body: _body.text.trim(),
        propertyId: _propertyId,
        unitId: _unitId,
        targetLabel: target,
        managerName: profile.name.isEmpty ? t.roleManager : profile.name,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(t.messageSent(n))));
    } catch (e) {
      if (mounted) toast(context, '${t.somethingWrong}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final props = ref.watch(propertiesProvider).value ?? const <Property>[];
    final membersByUnit = ref.watch(membersByUnitProvider);
    final flats = (ref.watch(unitsProvider).value ?? const <Unit>[])
        .where((u) => u.propertyId == _propertyId && membersByUnit.containsKey(u.id))
        .toList()
      ..sort((a, b) => compareFloors(a.floor, b.floor));
    ref.watch(membersProvider);
    final count = _recipients().length;
    final history = ref.watch(announcementsProvider).value ?? const <Announcement>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(t.sendMessage),
        actions: [TextButton(onPressed: _busy || count == 0 ? null : _send, child: Text(t.send))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            DropdownButtonFormField<String?>(
              initialValue: _propertyId,
              isExpanded: true,
              decoration: InputDecoration(labelText: t.sendTo),
              items: [
                DropdownMenuItem(value: null, child: Text(t.allBuildings)),
                for (final p in props) DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() {
                _propertyId = v;
                _unitId = null;
              }),
            ),
            if (_propertyId != null) ...[
              gap12,
              DropdownButtonFormField<String?>(
                key: ValueKey(_propertyId),
                initialValue: _unitId,
                isExpanded: true,
                decoration: InputDecoration(labelText: t.unit),
                items: [
                  DropdownMenuItem(value: null, child: Text(t.allFlatsInBuilding)),
                  for (final u in flats)
                    DropdownMenuItem(
                      value: u.id,
                      child: Text('${u.name} · ${memberNames(membersByUnit[u.id])}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _unitId = v),
              ),
            ],
            gap8,
            Row(children: [
              Icon(Icons.people_outline, size: 16, color: count == 0 ? cs.error : cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(count == 0 ? t.noRecipients : t.recipientsCount(count),
                    style: TextStyle(color: count == 0 ? cs.error : cs.onSurfaceVariant, fontSize: 12)),
              ),
            ]),
            gap16,
            TextFormField(
              controller: _title,
              maxLength: 80,
              decoration: InputDecoration(labelText: t.messageTitle, hintText: t.messageTitleHint),
              validator: requiredValidator(context),
            ),
            gap8,
            TextFormField(
              controller: _body,
              minLines: 4,
              maxLines: 10,
              maxLength: 1000,
              decoration: InputDecoration(labelText: t.messageBody, alignLabelWithHint: true),
              validator: requiredValidator(context),
            ),
            gap8,
            FilledButton.icon(
              onPressed: _busy || count == 0 ? null : _send,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_outlined),
              label: Text(t.send),
            ),
            if (history.isNotEmpty) ...[
              SectionTitle(t.sentMessages),
              Panel(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final a in history.take(20))
                    ListTile(
                      leading: const Icon(Icons.campaign_outlined),
                      title: Text(a.title),
                      subtitle: Text(
                          '${a.target} · ${t.recipientsCount(a.recipients)} · ${context.fmtDate(a.sentAt)}\n${a.body}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                      isThreeLine: true,
                    ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
