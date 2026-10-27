import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/community.dart';
import '../data/models.dart';
import '../data/notifications.dart';
import '../data/providers.dart';
import '../data/status_requests.dart';
import '../l10n/strings.dart';
import 'common.dart';
import 'properties_screen.dart' show unitStatusColor, unitStatusIcon, withStatus;

// Manager: approve or decline residents' requests to mark their flat as
// occupied ("Living here") or closed ("Not occupied").

String _statusLabel(L10n t, UnitStatus s) => s == UnitStatus.closed ? t.flatClosed : t.flatOccupied;

class StatusRequestsBanner extends ConsumerWidget {
  const StatusRequestsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingStatusRequestsProvider).value ?? const <FlatStatusRequest>[];
    if (pending.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Entrance(
        child: Material(
          color: cs.tertiaryContainer,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: Icon(Icons.swap_horiz, color: cs.onTertiaryContainer),
            title: Text(context.t.statusRequestsWaiting(pending.length),
                style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600)),
            trailing: Icon(Icons.chevron_right, color: cs.onTertiaryContainer),
            onTap: () => push(context, const StatusRequestsScreen()),
          ),
        ),
      ),
    );
  }
}

class StatusRequestsScreen extends ConsumerWidget {
  const StatusRequestsScreen({super.key});

  Future<void> _decide(BuildContext context, WidgetRef ref, FlatStatusRequest r, {required bool approve}) async {
    final t = context.t;
    final uid = ref.read(uidProvider);
    if (uid == null) return;
    var note = '';
    if (!approve) {
      final ctrl = TextEditingController();
      final res = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(t.declineStatusChange),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(labelText: t.reasonOptional),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(t.cancel)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: Text(t.reject),
            ),
          ],
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
      if (res == null) return;
      note = res;
    }
    final unit = ref.read(unitByIdProvider)[r.unitId];
    final property = ref.read(propertyByIdProvider)[r.propertyId];
    try {
      if (approve) {
        if (unit == null) {
          if (context.mounted) toast(context, t.flatNotFound);
          return;
        }
        // Same rule as when you change it yourself: a flat on the building's
        // default cost moves to the default for the new status.
        ref.read(unitRepo).save(withStatus(unit, r.toStatus, property));
      }
      await decideFlatStatusRequest(ref.read(firestoreProvider), uid, r.unitId, approved: approve, note: note);
      final profile = ref.read(profileProvider).value ?? const BusinessProfile();
      final residents = (ref.read(membersByUnitProvider)[r.unitId] ?? const <Member>[]).map((m) => m.uid);
      notifyFlatStatusDecision(ref,
              residentUids: residents,
              unitName: unit?.name ?? r.unitName,
              occupied: r.toStatus != UnitStatus.closed,
              approved: approve,
              note: note,
              managerName: profile.name.isEmpty ? t.roleManager : profile.name,
              arabic: t.ar)
          .catchError((Object e) => debugPrint('Notification not sent: $e'));
      if (context.mounted) toast(context, approve ? t.statusChangeApproved : t.statusChangeDeclined);
    } catch (e) {
      if (context.mounted) toast(context, '${t.somethingWrong}: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final pending = ref.watch(pendingStatusRequestsProvider).value ?? const <FlatStatusRequest>[];
    final units = ref.watch(unitByIdProvider);
    final props = ref.watch(propertyByIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.statusRequests)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text(t.statusRequestsHint, style: TextStyle(color: cs.onSurfaceVariant)),
          gap12,
          if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: EmptyState(icon: Icons.swap_horiz, message: t.noStatusRequests),
            ),
          for (final r in pending) ...[
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  [units[r.unitId]?.name ?? r.unitName, props[r.propertyId]?.name ?? '']
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text('${r.residentName} · ${context.fmtDate(r.createdAt)}',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                gap12,
                Row(children: [
                  _StatusPill(label: _statusLabel(t, units[r.unitId]?.status ?? r.fromStatus),
                      status: units[r.unitId]?.status ?? r.fromStatus),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, size: 18, color: cs.outline),
                  ),
                  _StatusPill(label: _statusLabel(t, r.toStatus), status: r.toStatus),
                ]),
                gap12,
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _decide(context, ref, r, approve: false),
                      child: Text(t.reject),
                    ),
                  ),
                  gap12,
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _decide(context, ref, r, approve: true),
                      child: Text(t.approve),
                    ),
                  ),
                ]),
              ]),
            ),
            gap12,
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.status});
  final String label;
  final UnitStatus status;

  @override
  Widget build(BuildContext context) {
    final color = unitStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(unitStatusIcon(status), size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    );
  }
}
