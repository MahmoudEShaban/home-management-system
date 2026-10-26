import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/attachments.dart';
import '../data/community.dart';
import '../data/models.dart';
import '../data/notifications.dart';
import '../data/providers.dart';
import '../data/rent_logic.dart';
import '../data/share_payments.dart';
import '../l10n/strings.dart';
import 'attachments_widgets.dart';
import 'common.dart';
import 'dues_screen.dart' show dueStateColor;
import 'resident_screens.dart' show residentPhotoController;

// Repaying the resident who paid for an approved maintenance request.

String _residentMoney(WidgetRef ref, BuildContext context, double v) => formatMoney(
    v,
    ref.watch(residentProfileProvider).value?.currency ?? 'EGP',
    Localizations.localeOf(context).languageCode);

/// Short name for a maintenance expense ("Elevator repair" or the category).
String maintenanceTitle(L10n t, Expense e) {
  final first = e.notes.split('\n').first.trim();
  return first.isNotEmpty ? first : t.expenseCategory(e.category);
}

Color _shareColor(BuildContext context, SharePayment? p) {
  if (p == null || p.status == DuesPaymentStatus.rejected) return dueStateColor(DueState.unpaid);
  return p.isConfirmed ? dueStateColor(DueState.paid) : dueStateColor(DueState.claimed);
}

String _shareLabel(L10n t, SharePayment? p) {
  if (p == null) return t.dueState(DueState.unpaid);
  return switch (p.status) {
    DuesPaymentStatus.confirmed => t.dueState(DueState.paid),
    DuesPaymentStatus.claimed => t.waitingFor(p.payeeName),
    DuesPaymentStatus.rejected => t.paymentDeclinedShort,
  };
}

Future<void> _notify(WidgetRef ref, String toUid, String viaManager, String title, String body, String senderName) async {
  final notifier = ref.read(notifierProvider);
  if (notifier == null || toUid.isEmpty) return;
  try {
    await notifier.sendSame([toUid], InboxItem(
      title: title,
      body: body,
      type: NoticeType.decision,
      senderName: senderName,
      createdAt: DateTime.now(),
      viaManager: viaManager,
    ));
  } catch (e) {
    debugPrint('Notification not sent: $e');
  }
}

// ─────────────────────────── Resident: My dues section ───────────────────────────

/// On the resident's "My dues" page: maintenance shares to repay to the
/// resident who paid, claims waiting for *your* confirmation (for requests
/// you submitted), and how much of your requests has been repaid.
class MaintenanceSharesSection extends ConsumerWidget {
  const MaintenanceSharesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final m = ref.watch(membershipProvider);
    if (m == null) return const SizedBox.shrink();
    final expenses = (ref.watch(residentExpensesProvider).value ?? const <Expense>[])
        .where((e) => e.paidByResident && e.isSplit)
        .toList();
    final payments = ref.watch(residentSharePaymentsProvider).value ?? const <SharePayment>[];
    final byId = {for (final p in payments) p.id: p};
    String money(double v) => _residentMoney(ref, context, v);

    // Shares this flat owes to another resident (not yet confirmed).
    final toPay = [
      for (final e in expenses)
        if (e.payToUnitId != m.unitId && e.shareFor(m.unitId) > 0.005)
          (e, byId[SharePayment.docId(e.id, m.unitId)]),
    ].where((x) => x.$2?.isConfirmed != true).toList();
    // Claims from other flats for requests this person submitted.
    final toConfirm = payments.where((p) => p.payeeUid == m.residentUid && p.isClaimed).toList();
    // Requests this person submitted: repaid so far.
    final mine = expenses.where((e) => e.payToUid == m.residentUid).toList();

    if (toPay.isEmpty && toConfirm.isEmpty && mine.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(t.maintenanceShares),
      if (toPay.isNotEmpty)
        Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final (e, p) in toPay)
              ListTile(
                leading: const Icon(Icons.handyman_outlined),
                title: Text(maintenanceTitle(t, e)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${t.payTo(e.payToName)} · ${context.fmtDate(e.date)}'),
                  const SizedBox(height: 4),
                  StatusChip(label: _shareLabel(t, p), color: _shareColor(context, p)),
                  if (p?.status == DuesPaymentStatus.rejected && p!.decisionNote.isNotEmpty)
                    Text('“${p.decisionNote}”', style: TextStyle(color: cs.error, fontSize: 12)),
                ]),
                isThreeLine: true,
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(money(e.shareFor(m.unitId)), style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (p == null || p.status == DuesPaymentStatus.rejected)
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                      onPressed: () => _paySheet(context, ref, e),
                      child: Text(t.iHavePaid),
                    ),
                ]),
              ),
          ]),
        ),
      if (toConfirm.isNotEmpty) ...[
        gap12,
        Text(t.sharesToConfirm, style: Theme.of(context).textTheme.labelLarge),
        gap8,
        for (final p in toConfirm) ...[
          SharePaymentCard(payment: p, managerUid: m.managerUid, viaManager: m.managerUid, expenses: expenses),
          gap8,
        ],
      ],
      if (mine.isNotEmpty) ...[
        gap12,
        Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final e in mine)
              Builder(builder: (context) {
                final owed = e.shares.where((s) => s.unitId != m.unitId).toList();
                final total = owed.fold<double>(0, (s, x) => s + x.amount);
                final got = owed.fold<double>(0, (s, x) {
                  final p = byId[SharePayment.docId(e.id, x.unitId)];
                  return s + (p?.isConfirmed == true ? p!.amount : 0);
                });
                return ListTile(
                  leading: Icon(Icons.savings_outlined, color: cs.primary),
                  title: Text(maintenanceTitle(t, e)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.repaidOf(money(got), money(total))),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: total <= 0 ? 1 : (got / total).clamp(0, 1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ]),
                );
              }),
          ]),
        ),
      ],
    ]);
  }

  Future<void> _paySheet(BuildContext context, WidgetRef ref, Expense e) async {
    final t = context.t;
    final m = ref.read(membershipProvider);
    if (m == null) return;
    final share = e.shareFor(m.unitId);
    final amount = TextEditingController(text: numText(share));
    final note = TextEditingController();
    var method = PaymentMethod.cash;
    final attachments = ref.read(attachmentServiceProvider);
    // Building scope: the resident being repaid (another flat) must see it.
    final photos = residentPhotoController(ref, AttachmentScope.building);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.of(c).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${t.iHavePaid} · ${maintenanceTitle(t, e)}', style: Theme.of(c).textTheme.titleLarge),
              gap8,
              Text(t.sharePayHint(e.payToName), style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)),
              gap16,
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: t.amount),
              ),
              gap12,
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final pm in PaymentMethod.values)
                  ChoiceChip(
                    label: Text(t.paymentMethod(pm)),
                    selected: method == pm,
                    onSelected: (_) => setSheet(() => method = pm),
                  ),
              ]),
              gap12,
              TextField(
                controller: note,
                decoration: InputDecoration(labelText: t.notes, hintText: t.paymentNoteHint),
              ),
              gap16,
              AttachmentPicker(controller: photos, label: t.paymentProof),
              gap16,
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: Text(t.sendToName(e.payToName)),
              ),
            ]),
          ),
        ),
      ),
    );
    final value = parseNumber(amount.text) ?? 0;
    final noteText = note.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      amount.dispose();
      note.dispose();
      photos.dispose();
    });
    if (ok != true || value <= 0) {
      photos.discard(attachments);
      return;
    }
    try {
      await claimSharePayment(ref.read(firestoreProvider), m, e,
          amount: value, method: method, note: noteText, attachmentIds: photos.commit(attachments));
      await _notify(
        ref,
        e.payToUid,
        m.managerUid,
        t.ar ? 'دفعة نصيب صيانة في انتظار تأكيدك' : 'Maintenance share paid — please confirm',
        '${maintenanceTitle(t, e)} · ${m.unitName} · ${numText(value)} · ${m.name}',
        m.name,
      );
      if (context.mounted) toast(context, t.shareClaimSent(e.payToName));
    } catch (err) {
      if (context.mounted) toast(context, '${t.somethingWrong}: $err');
    }
  }
}

/// A share payment waiting for confirmation: who paid, how much, proof,
/// Confirm / Decline. Used by the requester and by the manager.
class SharePaymentCard extends ConsumerWidget {
  const SharePaymentCard({
    super.key,
    required this.payment,
    required this.managerUid,
    required this.viaManager,
    this.expenses = const [],
    this.formatMoney,
  });
  final SharePayment payment;
  final String managerUid;

  /// Manager uid for resident-to-resident notices ('' when the manager acts).
  final String viaManager;
  final List<Expense> expenses;
  final String Function(double)? formatMoney;

  Future<void> _decide(BuildContext context, WidgetRef ref, bool confirm) async {
    final t = context.t;
    var note = '';
    if (!confirm) {
      final ctrl = TextEditingController();
      final res = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(t.rejectPayment),
          content: TextField(
            controller: ctrl,
            autofocus: true,
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
    try {
      await decideSharePayment(ref.read(firestoreProvider), managerUid, payment, confirm: confirm, note: note);
      final me = ref.read(membershipProvider)?.name ?? (ref.read(profileProvider).value?.name ?? '');
      await _notify(
        ref,
        payment.paidByUid,
        viaManager,
        confirm
            ? (t.ar ? 'تم تأكيد دفع نصيب الصيانة' : 'Maintenance share confirmed')
            : (t.ar ? 'لم يتم تأكيد دفع نصيب الصيانة' : 'Maintenance share not confirmed'),
        [payment.unitName, numText(payment.amount), if (note.isNotEmpty) note].join(' · '),
        me,
      );
      if (context.mounted) toast(context, confirm ? t.paymentConfirmed : t.paymentRejected);
    } catch (e) {
      if (context.mounted) toast(context, '${t.somethingWrong}: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final p = payment;
    final e = expenses.where((x) => x.id == p.expenseId).firstOrNull;
    final fmt = formatMoney ?? ((double v) => _residentMoney(ref, context, v));
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p.unitName} · ${p.paidByName}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                [
                  if (e != null) maintenanceTitle(t, e),
                  t.paymentMethod(p.method),
                  context.fmtDate(p.paidAt),
                ].join(' · '),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
              if (p.note.isNotEmpty) Text('“${p.note}”'),
            ]),
          ),
          Text(fmt(p.amount), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ]),
        if (p.attachmentIds.isNotEmpty) ...[
          gap8,
          AttachmentStrip(managerUid: managerUid, ids: p.attachmentIds),
        ],
        gap12,
        Row(children: [
          Expanded(
            child: OutlinedButton(onPressed: () => _decide(context, ref, false), child: Text(t.rejectPayment)),
          ),
          gap12,
          Expanded(
            child: FilledButton(onPressed: () => _decide(context, ref, true), child: Text(t.confirmPayment)),
          ),
        ]),
      ]),
    );
  }
}

// ─────────────────────────── Manager: expense page ───────────────────────────

/// On a resident-paid maintenance expense: each flat's repayment status.
/// The manager can confirm on the requester's behalf.
class ExpenseSharePaymentsPanel extends ConsumerWidget {
  const ExpenseSharePaymentsPanel({super.key, required this.expense});
  final Expense expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final uid = ref.watch(uidProvider) ?? '';
    final payments = ref.watch(managerSharePaymentsProvider).value ?? const <SharePayment>[];
    final byUnit = {for (final p in payments.where((p) => p.expenseId == expense.id)) p.unitId: p};
    final units = ref.watch(unitByIdProvider);
    String m(double v) => money(ref, context, v);
    final owed = expense.shares.where((s) => s.unitId != expense.payToUnitId).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(t.repaymentsTo(expense.payToName)),
      Text(t.repaymentsHint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      gap8,
      Panel(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (final s in owed)
            ListTile(
              dense: true,
              title: Text(units[s.unitId]?.name ?? s.unitId),
              subtitle: Align(
                alignment: AlignmentDirectional.centerStart,
                child: StatusChip(label: _shareLabel(t, byUnit[s.unitId]), color: _shareColor(context, byUnit[s.unitId])),
              ),
              trailing: Text(m(s.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
      for (final p in byUnit.values.where((p) => p.isClaimed)) ...[
        gap8,
        SharePaymentCard(payment: p, managerUid: uid, viaManager: '', formatMoney: m, expenses: [expense]),
      ],
    ]);
  }
}
