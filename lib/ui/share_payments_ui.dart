import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/attachments.dart';
import '../data/community.dart';
import '../data/models.dart';
import '../data/notifications.dart';
import '../data/providers.dart';
import '../data/dues_logic.dart';
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

Color shareStatusColor(ShareStatus s) {
  if (s.settled) return dueStateColor(DueState.paid);
  if (s.hasPending) return dueStateColor(DueState.claimed);
  return dueStateColor(DueState.unpaid);
}

String shareStatusLabel(L10n t, ShareStatus s, String payeeName) {
  if (s.settled) return t.dueState(DueState.paid);
  if (s.hasPending) return t.waitingFor(payeeName);
  if (s.confirmed > 0.005) return t.partlyPaid;
  final last = s.payments.isEmpty ? null : s.payments.first;
  if (last != null && last.status == DuesPaymentStatus.rejected) return t.paymentDeclinedShort;
  return t.dueState(DueState.unpaid);
}

String _paymentLabel(L10n t, SharePayment p) => switch (p.status) {
      DuesPaymentStatus.confirmed => t.paymentConfirmedShort,
      DuesPaymentStatus.claimed => t.waitingFor(p.payeeName),
      DuesPaymentStatus.rejected => t.paymentDeclinedShort,
    };

Color _paymentColor(SharePayment p) => switch (p.status) {
      DuesPaymentStatus.confirmed => dueStateColor(DueState.paid),
      DuesPaymentStatus.claimed => dueStateColor(DueState.claimed),
      DuesPaymentStatus.rejected => dueStateColor(DueState.unpaid),
    };

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
    String money(double v) => _residentMoney(ref, context, v);

    // Shares this flat owes to another resident (not yet fully confirmed).
    final toPay = [
      for (final e in expenses)
        if (e.payToUnitId != m.unitId && e.shareFor(m.unitId) > 0.005) (e, ShareStatus.of(e, m.unitId, payments)),
    ].where((x) => !x.$2.settled).toList();
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
            for (final (e, st) in toPay)
              ListTile(
                leading: const Icon(Icons.handyman_outlined),
                title: Text(maintenanceTitle(t, e)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${t.payTo(e.payToName)} · ${context.fmtDate(e.date)}'),
                  if (st.confirmed > 0.005 || st.hasPending)
                    Text(t.paidSoFar(money(st.confirmed + st.pending), money(st.owed)),
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  const SizedBox(height: 4),
                  StatusChip(label: shareStatusLabel(t, st, e.payToName), color: shareStatusColor(st)),
                ]),
                isThreeLine: true,
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(money(st.remaining > 0 ? st.remaining : st.owed), style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (st.remaining > 0)
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                      onPressed: () => payMaintenanceShare(context, ref, e, st),
                      child: Text(t.payShare),
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
                final got = payments
                    .where((p) => p.expenseId == e.id && p.isConfirmed && p.unitId != m.unitId)
                    .fold<double>(0, (s, p) => s + p.amount);
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
}

/// Sheet to pay (part of) this flat's share of a resident-paid maintenance
/// expense. The claim goes to the resident who paid for confirmation.
Future<void> payMaintenanceShare(BuildContext context, WidgetRef ref, Expense e, ShareStatus st) async {
  final t = context.t;
  final m = ref.read(membershipProvider);
  if (m == null) return;
  final amount = TextEditingController(text: numText(st.remaining));
  final formKey = GlobalKey<FormState>();
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
            gap12,
            Text(t.shareSummary(_residentMoney(ref, c, st.owed), _residentMoney(ref, c, st.confirmed + st.pending),
                _residentMoney(ref, c, st.remaining))),
            gap16,
            Form(
              key: formKey,
              child: TextFormField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: t.amountYouPaid, helperText: t.partPaymentHint),
                validator: (v) {
                  final x = parseNumber(v ?? '');
                  if (x == null || x <= 0) return t.invalidNumber;
                  if (x > st.remaining + 0.01) return t.moreThanRemaining(_residentMoney(ref, c, st.remaining));
                  return null;
                },
              ),
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
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(c, true);
              },
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
    final mine = payments.where((p) => p.expenseId == expense.id).toList();
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
              subtitle: Builder(builder: (context) {
                final st = ShareStatus.of(expense, s.unitId, payments);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.paidSoFar(m(st.confirmed), m(st.owed)), style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 2),
                  StatusChip(label: shareStatusLabel(t, st, expense.payToName), color: shareStatusColor(st)),
                ]);
              }),
              trailing: Text(m(s.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
      for (final p in mine.where((p) => p.isClaimed)) ...[
        gap8,
        SharePaymentCard(payment: p, managerUid: uid, viaManager: '', formatMoney: m, expenses: [expense]),
      ],
    ]);
  }
}

// ─────────────────────────── Resident: Maintenance requests page ───────────────────────────

/// Every approved maintenance request (paid by a resident) that this flat
/// shares in: choose one, see what's owed, paid and left, and pay any
/// amount towards it. Each payment goes to the requester to confirm.
class MaintenanceSharesToPay extends ConsumerStatefulWidget {
  const MaintenanceSharesToPay({super.key});

  @override
  ConsumerState<MaintenanceSharesToPay> createState() => _MaintenanceSharesToPayState();
}

class _MaintenanceSharesToPayState extends ConsumerState<MaintenanceSharesToPay> {
  bool _showSettled = false;
  String? _open; // expanded request

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final m = ref.watch(membershipProvider);
    if (m == null) return const SizedBox.shrink();
    final payments = ref.watch(residentSharePaymentsProvider).value ?? const <SharePayment>[];
    final all = [
      for (final e in (ref.watch(residentExpensesProvider).value ?? const <Expense>[]))
        if (e.paidByResident && e.isSplit && e.payToUnitId != m.unitId && e.shareFor(m.unitId) > 0.005)
          (e, ShareStatus.of(e, m.unitId, payments)),
    ];
    final outstanding = all.where((x) => !x.$2.settled).toList();
    final list = _showSettled ? all : outstanding;
    final left = outstanding.fold<double>(0, (s, x) => s + x.$2.remaining);
    String money(double v) => _residentMoney(ref, context, v);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Panel(
          child: Row(children: [
            Icon(Icons.account_balance_wallet_outlined, color: cs.primary),
            gap12,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.leftToPayTotal, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                AnimatedNumber(
                    value: left, format: money, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              ]),
            ),
            Text(t.requestsCount(outstanding.length), style: TextStyle(color: cs.onSurfaceVariant)),
          ]),
        ),
        gap8,
        Text(t.sharesToPayHint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.showFullyPaid),
          value: _showSettled,
          onChanged: (v) => setState(() => _showSettled = v),
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: EmptyState(icon: Icons.task_alt, message: all.isEmpty ? t.noSharesToPay : t.allSharesPaid),
          ),
        for (final (e, st) in list) ...[
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InkWell(
                onTap: () => setState(() => _open = _open == e.id ? null : e.id),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(maintenanceTitle(t, e),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text('${t.payTo(e.payToName)} · ${context.fmtDate(e.date)}',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    ]),
                  ),
                  StatusChip(label: shareStatusLabel(t, st, e.payToName), color: shareStatusColor(st)),
                  Icon(_open == e.id ? Icons.expand_less : Icons.expand_more, color: cs.outline),
                ]),
              ),
              gap12,
              Row(children: [
                Expanded(child: _Mini(label: t.yourShare, value: money(st.owed))),
                Expanded(child: _Mini(label: t.paid, value: money(st.confirmed))),
                Expanded(child: _Mini(label: t.leftToPay, value: money(st.remaining), strong: st.remaining > 0)),
              ]),
              gap8,
              LinearProgressIndicator(
                value: st.owed <= 0 ? 1 : ((st.confirmed + st.pending) / st.owed).clamp(0, 1),
                borderRadius: BorderRadius.circular(4),
              ),
              if (st.hasPending)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(t.pendingAmount(money(st.pending), e.payToName),
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                alignment: Alignment.topCenter,
                child: _open == e.id && st.payments.isNotEmpty
                    ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        gap12,
                        Text(t.yourPayments, style: Theme.of(context).textTheme.labelLarge),
                        for (final p in st.payments)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('${money(p.amount)} · ${t.paymentMethod(p.method)}'),
                            subtitle: Text([
                              context.fmtDate(p.paidAt),
                              p.paidByName,
                              if (p.note.isNotEmpty) '“${p.note}”',
                              if (p.decisionNote.isNotEmpty) '${p.payeeName}: “${p.decisionNote}”',
                            ].where((s) => s.isNotEmpty).join(' · ')),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              AttachmentBadge(count: p.attachmentIds.length),
                              gap8,
                              StatusChip(label: _paymentLabel(t, p), color: _paymentColor(p)),
                            ]),
                            onTap: p.attachmentIds.isEmpty
                                ? null
                                : () => openAttachmentViewer(context, m.managerUid, p.attachmentIds),
                          ),
                      ])
                    : const SizedBox(width: double.infinity),
              ),
              if (st.remaining > 0) ...[
                gap12,
                FilledButton.icon(
                  onPressed: () => payMaintenanceShare(context, ref, e, st),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(t.payShare),
                ),
              ],
            ]),
          ),
          gap12,
        ],
      ],
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value, this.strong = false});
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(value,
            style: TextStyle(fontWeight: FontWeight.w700, color: strong ? cs.primary : null, fontSize: 15)),
      ),
    ]);
  }
}
