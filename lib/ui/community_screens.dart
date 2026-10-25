import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/community.dart';
import '../data/notifications.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import 'common.dart';
import 'expenses_screen.dart' show ExpenseForm;
import 'split_editor.dart';

// ─────────────────── Property page: building code card ───────────────────

/// Shows the building's resident code (or a button to create one), plus how
/// many residents are linked and waiting.
class ResidentAccessPanel extends ConsumerStatefulWidget {
  const ResidentAccessPanel({super.key, required this.property});
  final Property property;

  @override
  ConsumerState<ResidentAccessPanel> createState() => _ResidentAccessPanelState();
}

class _ResidentAccessPanelState extends ConsumerState<ResidentAccessPanel> {
  bool _busy = false;

  Future<void> _create() async {
    final uid = ref.read(uidProvider);
    if (uid == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(communityProvider).createCode(
            managerUid: uid,
            property: widget.property,
            units: ref.read(unitsProvider).value ?? const [],
            takenUnitIds: ref.read(membersByUnitProvider).keys.toSet(),
          );
    } catch (e) {
      if (mounted) toast(context, '${context.t.somethingWrong}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final code = (ref.watch(buildingCodesProvider).value ?? const <BuildingCode>[])
        .where((c) => c.propertyId == widget.property.id)
        .firstOrNull;
    final members = (ref.watch(membersProvider).value ?? const <Member>[])
        .where((m) => m.propertyId == widget.property.id)
        .length;
    final pending = ref
        .watch(pendingRequestsProvider)
        .where((r) => r.propertyId == widget.property.id)
        .length;

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.groups_outlined, color: cs.primary),
          gap8,
          Expanded(
            child: Text(t.residentAccess,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text(t.residentsLinked(members), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ]),
        gap12,
        if (code == null) ...[
          Text(t.residentAccessHint, style: TextStyle(color: cs.onSurfaceVariant)),
          gap12,
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _create,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.vpn_key_outlined),
            label: Text(t.createBuildingCode),
          ),
        ] else ...[
          Text(t.buildingCode, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: SelectableText(
                code.code,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      color: cs.primary,
                    ),
              ),
            ),
            IconButton(
              tooltip: t.copy,
              icon: const Icon(Icons.copy_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code.code));
                if (context.mounted) toast(context, t.codeCopied);
              },
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'disable' &&
                    await confirmDialog(context, t.disableCodeConfirm, confirmLabel: t.disableCode)) {
                  await ref.read(communityProvider).deleteCode(code.code);
                }
              },
              itemBuilder: (_) => [PopupMenuItem(value: 'disable', child: Text(t.disableCode))],
            ),
          ]),
          Text(t.shareCodeHint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ],
        if (pending > 0) ...[
          gap12,
          FilledButton.icon(
            onPressed: () => push(context, const JoinRequestsScreen()),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: Text(t.requestsWaiting(pending)),
          ),
        ],
      ]),
    );
  }
}

// ─────────────────── Dashboard banner ───────────────────

class JoinRequestsBanner extends ConsumerWidget {
  const JoinRequestsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingRequestsProvider);
    if (pending.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: Icon(Icons.person_add_alt_1_outlined, color: cs.onTertiaryContainer),
          title: Text(context.t.requestsWaiting(pending.length),
              style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600)),
          trailing: Icon(Icons.chevron_right, color: cs.onTertiaryContainer),
          onTap: () => push(context, const JoinRequestsScreen()),
        ),
      ),
    );
  }
}

// ─────────────────── Requests screen ───────────────────

class JoinRequestsScreen extends ConsumerWidget {
  const JoinRequestsScreen({super.key});

  Future<void> _approve(BuildContext context, WidgetRef ref, JoinRequest r) async {
    final t = context.t;
    try {
      await ref.read(communityProvider).approve(r);
      if (context.mounted) toast(context, t.requestApproved);
    } catch (e) {
      if (context.mounted) toast(context, '${t.somethingWrong}: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final all = ref.watch(joinRequestsProvider).value ?? const <JoinRequest>[];
    final pending = all.where((r) => r.status == RequestStatus.pending).toList();
    final decided = all.where((r) => r.status != RequestStatus.pending).take(20).toList();

    return Scaffold(
      appBar: AppBar(title: Text(t.joinRequests)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: EmptyState(icon: Icons.how_to_reg_outlined, message: t.noRequests),
            ),
          for (final r in pending) ...[
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const CircleAvatar(child: Icon(Icons.person_outline)),
                  gap12,
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text([r.email, r.phone].where((s) => s.isNotEmpty).join(' · '),
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    ]),
                  ),
                ]),
                gap12,
                Row(children: [
                  Icon(Icons.door_front_door_outlined, size: 18, color: cs.primary),
                  gap8,
                  Expanded(child: Text('${r.unitName} · ${r.propertyName}')),
                ]),
                const SizedBox(height: 4),
                Text(context.fmtDate(r.createdAt), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                gap12,
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        if (await confirmDialog(context, t.rejectConfirm(r.name), confirmLabel: t.reject)) {
                          await ref.read(communityProvider).reject(r);
                        }
                      },
                      child: Text(t.reject),
                    ),
                  ),
                  gap12,
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _approve(context, ref, r),
                      child: Text(t.approve),
                    ),
                  ),
                ]),
              ]),
            ),
            gap12,
          ],
          if (decided.isNotEmpty) ...[
            SectionTitle(t.recentDecisions),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final r in decided)
                  ListTile(
                    title: Text(r.name),
                    subtitle: Text('${r.unitName} · ${r.propertyName}'),
                    trailing: StatusChip(
                      label: t.requestStatus(r.status),
                      color: r.status == RequestStatus.approved ? const Color(0xFF2E7D32) : Colors.grey,
                    ),
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────── Flat page: linked resident ───────────────────

class LinkedResidentPanel extends ConsumerWidget {
  const LinkedResidentPanel({super.key, required this.unitId});
  final String unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final members = ref.watch(membersByUnitProvider)[unitId] ?? const <Member>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(members.length > 1 ? t.residentAccountsCount(members.length) : t.residentAccount),
      Panel(
        padding: EdgeInsets.zero,
        child: members.isEmpty
            ? ListTile(
                leading: Icon(Icons.person_off_outlined, color: cs.outline),
                title: Text(t.noResidentAccount),
                subtitle: Text(t.noResidentAccountHint),
              )
            : Column(children: [
                for (final member in members)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.verified_user_outlined)),
                    title: Text(member.name),
                    subtitle: Text([member.email, member.phone].where((s) => s.isNotEmpty).join(' · ')),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        final uid = ref.read(uidProvider);
                        if (v == 'remove' &&
                            uid != null &&
                            await confirmDialog(context, t.unlinkConfirm(member.name), confirmLabel: t.unlink)) {
                          await ref.read(communityProvider).removeMember(uid, member);
                        }
                      },
                      itemBuilder: (_) => [PopupMenuItem(value: 'remove', child: Text(t.unlink))],
                    ),
                  ),
                if (members.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(t.sharedFlatHint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  ),
              ]),
      ),
    ]);
  }
}

// ─────────────────── Resident expense approvals ───────────────────

class ProposalsBanner extends ConsumerWidget {
  const ProposalsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingProposalsProvider);
    if (pending.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: Icon(Icons.pending_actions_outlined, color: cs.onSecondaryContainer),
          title: Text(context.t.expensesWaiting(pending.length),
              style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w600)),
          trailing: Icon(Icons.chevron_right, color: cs.onSecondaryContainer),
          onTap: () => push(context, const ExpenseApprovalsScreen()),
        ),
      ),
    );
  }
}

class ExpenseApprovalsScreen extends ConsumerWidget {
  const ExpenseApprovalsScreen({super.key});

  /// Shares recalculated on the manager's current flat data, using the
  /// resident's chosen method and floors.
  static List<ExpenseShare> sharesFor(WidgetRef ref, ExpenseProposal p) {
    final units = (ref.read(unitsProvider).value ?? const <Unit>[])
        .where((u) => u.propertyId == p.propertyId)
        .toList();
    const withTenant = <String>{};
    final floors = SplitEditor.floorsOf(units);
    final excluded = p.splitFloors.isEmpty ? <String>{} : floors.where((f) => !p.splitFloors.contains(f)).toSet();
    return SplitEditor.compute(
        units: units, amount: p.amount, method: p.split, excludedFloors: excluded, withTenant: withTenant);
  }

  static Future<void> approve(BuildContext context, WidgetRef ref, ExpenseProposal p) async {
    final t = context.t;
    final shares = sharesFor(ref, p);
    final expense = p.toExpense(shares: shares);
    final id = ref.read(expenseRepo).save(expense);
    final profile = ref.read(profileProvider).value ?? const BusinessProfile();
    final managerName = profile.name.isEmpty ? t.roleManager : profile.name;
    try {
      await ref.read(proposalServiceProvider).markApproved(p.id, id);
      await notifyProposalDecision(ref, p, approved: true, managerName: managerName, arabic: t.ar);
      await notifyExpenseAdded(ref, expense, managerName: managerName, currency: profile.currency, arabic: t.ar);
      if (context.mounted) toast(context, t.expenseApproved);
    } catch (e) {
      if (context.mounted) toast(context, '${t.somethingWrong}: $e');
    }
  }

  static Future<void> decline(BuildContext context, WidgetRef ref, ExpenseProposal p) async {
    final t = context.t;
    final ctrl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.declineExpense),
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
    if (note == null) return;
    await ref.read(proposalServiceProvider).decline(p.id, note);
    final profile = ref.read(profileProvider).value ?? const BusinessProfile();
    try {
      await notifyProposalDecision(ref, p,
          approved: false,
          note: note,
          managerName: profile.name.isEmpty ? t.roleManager : profile.name,
          arabic: t.ar);
    } catch (e) {
      debugPrint('Notification not sent: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final all = ref.watch(managerProposalsProvider).value ?? const <ExpenseProposal>[];
    final pending = all.where((p) => p.status == RequestStatus.pending).toList();
    final decided = all.where((p) => p.status != RequestStatus.pending).take(20).toList();
    final unitById = ref.watch(unitByIdProvider);
    final propById = ref.watch(propertyByIdProvider);
    String m(double v) => money(ref, context, v);

    return Scaffold(
      appBar: AppBar(title: Text(t.expenseApprovals)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: EmptyState(icon: Icons.task_alt, message: t.noExpensesWaiting),
            ),
          for (final p in pending) ...[
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(
                    backgroundColor: cs.secondaryContainer,
                    child: Icon(p.isMaintenance ? Icons.handyman_outlined : expenseIcon(p.category),
                        color: cs.onSecondaryContainer),
                  ),
                  gap12,
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (p.isMaintenance)
                        Row(children: [
                          Flexible(child: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w600))),
                          gap8,
                          StatusChip(
                            label: t.urgencyLabel(p.urgency),
                            color: p.urgency == Urgency.urgent
                                ? const Color(0xFFC62828)
                                : p.urgency == Urgency.low
                                    ? Colors.grey
                                    : const Color(0xFFB26A00),
                          ),
                        ])
                      else
                        Text('${t.expenseCategory(p.category)}${p.vendor.isEmpty ? '' : ' · ${p.vendor}'}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${propById[p.propertyId]?.name ?? ''} · ${context.fmtDate(p.date)}',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    ]),
                  ),
                  if (p.amount > 0)
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(m(p.amount),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      if (p.isMaintenance)
                        Text(t.estimatedCostShort, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                    ]),
                ]),
                gap12,
                Row(children: [
                  Icon(Icons.person_outline, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(t.submittedBy(p.residentName, p.unitName),
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  ),
                ]),
                if (!p.isMaintenance) const SizedBox(height: 4),
                if (!p.isMaintenance) Row(children: [
                  Icon(Icons.call_split, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      [
                        t.splitMethod(p.split),
                        if (p.splitFloors.isNotEmpty) p.splitFloors.map(t.floorLabel).join(', '),
                      ].join(' · '),
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
                ]),
                if (p.notes.isNotEmpty) ...[
                  gap8,
                  Text('“${p.notes}”'),
                ],
                gap8,
                if (!p.isMaintenance)
                  // Per-flat preview on current data.
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(t.splitSummary(sharesFor(ref, p).length, m(p.amount)), style: const TextStyle(fontSize: 14)),
                    children: [
                      for (final sh in sharesFor(ref, p))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            Expanded(child: Text(unitById[sh.unitId]?.name ?? '')),
                            Text(m(sh.amount)),
                          ]),
                        ),
                    ],
                  ),
                ),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => decline(context, ref, p),
                      child: Text(t.reject),
                    ),
                  ),
                  gap8,
                  if (p.isMaintenance)
                    // The manager decides the cost and each flat's share.
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => pushForm(context, ExpenseForm(fromProposal: p)),
                        child: Text(t.approveAndSetShares, textAlign: TextAlign.center),
                      ),
                    )
                  else ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pushForm(context, ExpenseForm(fromProposal: p)),
                        child: Text(t.editAndApprove, textAlign: TextAlign.center),
                      ),
                    ),
                    gap8,
                    Expanded(
                      child: FilledButton(
                        onPressed: () => approve(context, ref, p),
                        child: Text(t.approve),
                      ),
                    ),
                  ],
                ]),
              ]),
            ),
            gap12,
          ],
          if (decided.isNotEmpty) ...[
            SectionTitle(t.recentDecisions),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final p in decided)
                  ListTile(
                    leading: Icon(expenseIcon(p.category)),
                    title: Text('${t.expenseCategory(p.category)} · ${m(p.amount)}'),
                    subtitle: Text(t.submittedBy(p.residentName, p.unitName)),
                    trailing: StatusChip(
                      label: t.proposalStatus(p.status),
                      color: p.status == RequestStatus.approved ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                    ),
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
