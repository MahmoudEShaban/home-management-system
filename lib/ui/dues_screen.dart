import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/community.dart';
import '../data/models.dart';
import '../data/notifications.dart';
import '../data/providers.dart';
import '../data/rent_logic.dart';
import '../l10n/strings.dart';
import 'common.dart';
import 'properties_screen.dart' show compareFloors, unitStatusColor, unitStatusIcon;

Color dueStateColor(DueState s) => switch (s) {
      DueState.paid => const Color(0xFF2E7D32),
      DueState.claimed => const Color(0xFF1565C0),
      DueState.unpaid => const Color(0xFFB26A00),
      DueState.nothingDue => Colors.grey,
    };

class DueStateChip extends StatelessWidget {
  const DueStateChip(this.state, {super.key});
  final DueState state;

  @override
  Widget build(BuildContext context) =>
      StatusChip(label: context.t.dueState(state), color: dueStateColor(state));
}

// ─────────────────────────── Manager payment actions ───────────────────────────

Future<void> _notifyResident(WidgetRef ref, String unitId, String title, String body) async {
  final member = ref.read(memberByUnitProvider)[unitId];
  final notifier = ref.read(notifierProvider);
  if (member == null || notifier == null) return;
  final profile = ref.read(profileProvider).value ?? const BusinessProfile();
  try {
    await notifier.sendSame([member.uid], InboxItem(
      title: title,
      body: body,
      type: NoticeType.decision,
      senderName: profile.name,
      createdAt: DateTime.now(),
    ));
  } catch (e) {
    debugPrint('Notification not sent: $e');
  }
}

/// Records a payment the manager received directly (cash, transfer…).
Future<void> recordPaymentSheet(BuildContext context, WidgetRef ref, FlatMonthStatus s) async {
  final t = context.t;
  final amount = TextEditingController(text: numText(s.outstanding > 0 ? s.outstanding : s.due.total));
  var method = PaymentMethod.cash;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${t.markAsPaid} · ${s.due.unit.name}', style: Theme.of(c).textTheme.titleLarge),
          gap16,
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: t.amount),
          ),
          gap12,
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final m in PaymentMethod.values)
              ChoiceChip(
                label: Text(t.paymentMethod(m)),
                selected: method == m,
                onSelected: (_) => setSheet(() => method = m),
              ),
          ]),
          gap16,
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: Text(t.save),
          ),
        ]),
      ),
    ),
  );
  final value = parseNumber(amount.text) ?? 0;
  WidgetsBinding.instance.addPostFrameCallback((_) => amount.dispose());
  if (ok != true || value <= 0) return;
  ref.read(duesPaymentRepo).save(DuesPayment(
        propertyId: s.due.unit.propertyId,
        unitId: s.due.unit.id,
        period: periodKey(_monthOf(ref, s)),
        amount: value,
        method: method,
        status: DuesPaymentStatus.confirmed,
        paidByName: t.roleManager,
        confirmedAt: DateTime.now(),
      ));
}

DateTime _monthOf(WidgetRef ref, FlatMonthStatus s) =>
    s.payment != null ? periodStart(s.payment!.period) : ref.read(selectedMonthProvider);

Future<void> confirmPayment(BuildContext context, WidgetRef ref, DuesPayment p) async {
  final t = context.t;
  ref.read(duesPaymentRepo).save(p.copyWith(status: DuesPaymentStatus.confirmed, confirmedAt: DateTime.now()));
  await _notifyResident(ref, p.unitId, t.paymentConfirmedTitle,
      '${context.fmtPeriod(p.period)} · ${money(ref, context, p.amount)}');
}

Future<void> rejectPayment(BuildContext context, WidgetRef ref, DuesPayment p) async {
  final t = context.t;
  final ctrl = TextEditingController();
  final note = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(t.rejectPayment),
      content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(labelText: t.reasonOptional)),
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
  if (note == null || !context.mounted) return;
  ref.read(duesPaymentRepo).save(p.copyWith(status: DuesPaymentStatus.rejected, note: note));
  await _notifyResident(ref, p.unitId, t.paymentRejectedTitle,
      [context.fmtPeriod(p.period), if (note.isNotEmpty) note].join(' · '));
}

/// Manager menu for one flat's payment.
class PaymentActions extends ConsumerWidget {
  const PaymentActions({super.key, required this.status});
  final FlatMonthStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final p = status.payment;
    return Wrap(spacing: 8, runSpacing: 4, children: [
      if (status.state == DueState.claimed && p != null) ...[
        FilledButton.icon(
          onPressed: () => confirmPayment(context, ref, p),
          icon: const Icon(Icons.check, size: 18),
          label: Text(t.confirmPayment),
        ),
        OutlinedButton(onPressed: () => rejectPayment(context, ref, p), child: Text(t.reject)),
      ],
      if (status.state == DueState.unpaid)
        FilledButton.tonalIcon(
          onPressed: () => recordPaymentSheet(context, ref, status),
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: Text(t.markAsPaid),
        ),
      if (status.state == DueState.paid && p != null)
        TextButton(
          onPressed: () async {
            if (await confirmDialog(context, t.undoPaymentConfirm, confirmLabel: t.undoPayment)) {
              ref.read(duesPaymentRepo).delete(p.id);
            }
          },
          child: Text(t.undoPayment),
        ),
    ]);
  }
}

// ─────────────────────────── Monthly dues (manager) ───────────────────────────

/// What each flat of a building owes for the selected month, and whether it
/// has paid.
class MonthlyDuesScreen extends ConsumerWidget {
  const MonthlyDuesScreen({super.key, required this.propertyId});
  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final property = ref.watch(propertyByIdProvider)[propertyId];
    final month = ref.watch(selectedMonthProvider);
    final statuses = monthStatuses(
      propertyId: propertyId,
      month: month,
      units: ref.watch(unitsProvider).value ?? const <Unit>[],
      expenses: ref.watch(expensesProvider).value ?? const <Expense>[],
      payments: ref.watch(duesPaymentsProvider).value ?? const <DuesPayment>[],
    );
    String m(double v) => money(ref, context, v);

    final total = statuses.fold<double>(0, (s, d) => s + d.due.total);
    final collected = statuses.fold<double>(0, (s, d) => s + (d.payment?.isConfirmed == true ? d.payment!.amount : 0));
    final paidCount = statuses.where((s) => s.state == DueState.paid).length;
    final claimedCount = statuses.where((s) => s.state == DueState.claimed).length;

    final byFloor = <String, List<FlatMonthStatus>>{};
    for (final s in statuses) {
      byFloor.putIfAbsent(s.due.unit.floor.trim(), () => []).add(s);
    }
    final floors = byFloor.keys.toList()..sort(compareFloors);

    Widget figure(String label, String value, {Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: color)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: Text('${t.monthlyDues}${property == null ? '' : ' · ${property.name}'}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const MonthSwitcher(),
          Panel(
            child: Column(children: [
              Row(children: [
                figure(t.totalDue, m(total), color: cs.primary),
                figure(t.collected, m(collected), color: const Color(0xFF2E7D32)),
              ]),
              gap12,
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total <= 0 ? 0.0 : (collected / total).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
              gap8,
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(t.paidSummary(paidCount, statuses.length, claimedCount),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ),
            ]),
          ),
          if (statuses.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: EmptyState(icon: Icons.grid_view_outlined, message: t.noUnits),
            ),
          for (final f in floors) ...[
            SectionTitle(t.floorLabel(f)),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final s in byFloor[f]!) ...[
                  _DueTile(status: s),
                  if (s != byFloor[f]!.last) const Divider(height: 1, indent: 16, endIndent: 16),
                ],
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _DueTile extends ConsumerWidget {
  const _DueTile({required this.status});
  final FlatMonthStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final due = status.due;
    final u = due.unit;
    final p = status.payment;
    String m(double v) => money(ref, context, v);

    Widget line(String label, double value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(color: cs.onSurfaceVariant))),
            Text(m(value)),
          ]),
        );

    return Theme(
      // Remove the default divider lines ExpansionTile draws.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(unitStatusIcon(u.status), color: unitStatusColor(u.status)),
        title: Text(u.name),
        subtitle: Row(children: [DueStateChip(status.state)]),
        trailing: Text(m(due.total),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        childrenPadding: const EdgeInsetsDirectional.fromSTEB(72, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line(t.monthlyFees, due.fixedFee),
          for (final (e, share) in due.expenseShares)
            line('${t.expenseCategory(e.category)}${e.vendor.isEmpty ? '' : ' · ${e.vendor}'}', share),
          const Divider(height: 12),
          Row(children: [
            Expanded(child: Text(t.totalDue, style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(m(due.total), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          if (p != null) ...[
            gap8,
            Text(
              [
                t.paymentStatusLine(p.status),
                m(p.amount),
                t.paymentMethod(p.method),
                if (p.paidByName.isNotEmpty) p.paidByName,
                context.fmtDate(p.paidAt),
                if (p.note.isNotEmpty) '“${p.note}”',
              ].join(' · '),
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
          if (status.state != DueState.nothingDue) ...[gap8, PaymentActions(status: status)],
        ],
      ),
    );
  }
}

// ─────────────────────────── Payments to confirm ───────────────────────────

class PaymentsToConfirmBanner extends ConsumerWidget {
  const PaymentsToConfirmBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claimed = (ref.watch(duesPaymentsProvider).value ?? const <DuesPayment>[])
        .where((p) => p.status == DuesPaymentStatus.claimed)
        .length;
    if (claimed == 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF1565C0).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: const Icon(Icons.price_check, color: Color(0xFF1565C0)),
          title: Text(context.t.paymentsToConfirm(claimed),
              style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => push(context, const PaymentsToConfirmScreen()),
        ),
      ),
    );
  }
}

class PaymentsToConfirmScreen extends ConsumerWidget {
  const PaymentsToConfirmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final claimed = (ref.watch(duesPaymentsProvider).value ?? const <DuesPayment>[])
        .where((p) => p.status == DuesPaymentStatus.claimed)
        .toList()
      ..sort((a, b) => b.paidAt.compareTo(a.paidAt));
    final unitById = ref.watch(unitByIdProvider);
    final propById = ref.watch(propertyByIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.confirmPayments)),
      body: claimed.isEmpty
          ? EmptyState(icon: Icons.task_alt, message: t.noPaymentsToConfirm)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                for (final p in claimed) ...[
                  Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${unitById[p.unitId]?.name ?? ''} · ${propById[p.propertyId]?.name ?? ''}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              [
                                context.fmtPeriod(p.period),
                                t.paymentMethod(p.method),
                                p.paidByName,
                                context.fmtDate(p.paidAt),
                              ].where((s) => s.isNotEmpty).join(' · '),
                              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                            ),
                            if (p.note.isNotEmpty) Text('“${p.note}”'),
                          ]),
                        ),
                        Text(money(ref, context, p.amount),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ]),
                      gap12,
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(onPressed: () => rejectPayment(context, ref, p), child: Text(t.reject)),
                        ),
                        gap12,
                        Expanded(
                          child: FilledButton(
                            onPressed: () => confirmPayment(context, ref, p),
                            child: Text(t.confirmPayment),
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

// ─────────────────────────── Late flats ───────────────────────────

class LateFlatsScreen extends ConsumerWidget {
  const LateFlatsScreen({super.key, required this.late});
  final List<LateFlat> late;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final propById = ref.watch(propertyByIdProvider);
    final memberByUnit = ref.watch(memberByUnitProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.lateFlats)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text(t.lateFlatsHint, style: TextStyle(color: cs.onSurfaceVariant)),
          gap12,
          for (final l in late) ...[
            Panel(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded, color: Color(0xFFB26A00)),
                title: Text(
                    [l.unit.name, if (memberByUnit[l.unit.id] != null) memberByUnit[l.unit.id]!.name].join(' · ')),
                subtitle: Text(
                    '${propById[l.unit.propertyId]?.name ?? ''}\n${l.periods.map(context.fmtPeriod).join(', ')}'),
                isThreeLine: true,
                trailing: Text(money(ref, context, l.outstanding),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB26A00))),
                onTap: () {
                  // Open the oldest unpaid month for this building.
                  ref.read(selectedMonthProvider.notifier).state = periodStart(l.periods.last);
                  push(context, MonthlyDuesScreen(propertyId: l.unit.propertyId));
                },
              ),
            ),
            gap8,
          ],
        ],
      ),
    );
  }
}
