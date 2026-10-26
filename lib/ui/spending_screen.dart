import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/community.dart';
import '../data/flat_expenses.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/share_payments.dart';
import '../l10n/strings.dart';
import 'attachments_widgets.dart';
import 'common.dart';
import 'share_payments_ui.dart' show maintenanceTitle;

// "My payments & spending": everything a flat has paid — monthly dues to the
// building, maintenance shares repaid to neighbours, repairs paid up front
// (minus what neighbours repaid), and private flat expenses.

enum SpendKind { dues, share, repair, repaid, flat }

class SpendItem {
  final SpendKind kind;
  final DateTime date;
  final String title;
  final String detail;

  /// Money out of the flat's pocket; negative for money received back.
  final double amount;

  /// Waiting for confirmation (not counted in the totals).
  final bool pending;
  final String byUid;
  final String byName;
  final List<String> attachmentIds;

  const SpendItem({
    required this.kind,
    required this.date,
    required this.title,
    this.detail = '',
    required this.amount,
    this.pending = false,
    this.byUid = '',
    this.byName = '',
    this.attachmentIds = const [],
  });
}

/// All spending items of one flat, newest first.
List<SpendItem> flatSpending({
  required L10n t,
  required String unitId,
  required List<DuesPayment> dues,
  required List<SharePayment> shares,
  required List<FlatExpense> flatExpenses,
  required List<Expense> expenses,
  required String Function(String period) periodLabel,
}) {
  final items = <SpendItem>[];
  for (final p in dues.where((p) => p.unitId == unitId && p.status != DuesPaymentStatus.rejected)) {
    items.add(SpendItem(
      kind: SpendKind.dues,
      date: p.paidAt,
      title: t.spendDues(periodLabel(p.period)),
      detail: t.paymentMethod(p.method),
      amount: p.amount,
      pending: !p.isConfirmed,
      byUid: p.paidByUid,
      byName: p.paidByName,
      attachmentIds: p.attachmentIds,
    ));
  }
  final expenseById = {for (final e in expenses) e.id: e};
  for (final p in shares.where((p) => p.unitId == unitId && p.status != DuesPaymentStatus.rejected)) {
    final e = expenseById[p.expenseId];
    items.add(SpendItem(
      kind: SpendKind.share,
      date: p.paidAt,
      title: e == null ? t.maintenanceShare : maintenanceTitle(t, e),
      detail: t.payTo(p.payeeName),
      amount: p.amount,
      pending: !p.isConfirmed,
      byUid: p.paidByUid,
      byName: p.paidByName,
      attachmentIds: p.attachmentIds,
    ));
  }
  for (final e in expenses.where((e) => e.paidByResident && e.payToUnitId == unitId)) {
    items.add(SpendItem(
      kind: SpendKind.repair,
      date: e.date,
      title: maintenanceTitle(t, e),
      detail: t.repairYouPaid,
      amount: e.amount,
      byUid: e.payToUid,
      byName: e.payToName,
      attachmentIds: e.attachmentIds,
    ));
    // Neighbours' confirmed repayments come back to this flat.
    for (final p in shares.where((p) => p.expenseId == e.id && p.isConfirmed && p.unitId != unitId)) {
      items.add(SpendItem(
        kind: SpendKind.repaid,
        date: p.decidedAt ?? p.paidAt,
        title: maintenanceTitle(t, e),
        detail: t.repaidBy(p.unitName),
        amount: -p.amount,
        byUid: e.payToUid,
        byName: e.payToName,
      ));
    }
  }
  for (final f in flatExpenses.where((f) => f.unitId == unitId)) {
    items.add(SpendItem(
      kind: SpendKind.flat,
      date: f.date,
      title: f.title.isEmpty ? t.expenseCategory(f.category) : f.title,
      detail: t.expenseCategory(f.category),
      amount: f.amount,
      byUid: f.addedByUid,
      byName: f.addedByName,
      attachmentIds: f.attachmentIds,
    ));
  }
  items.sort((a, b) => b.date.compareTo(a.date));
  return items;
}

enum _Range { month, year, all }

/// Spending of one flat. [manager] reads the manager's own data (flat page);
/// otherwise the signed-in resident's flat.
class SpendingScreen extends ConsumerStatefulWidget {
  const SpendingScreen({super.key, this.manager = false, this.unitId, this.title});
  final bool manager;
  final String? unitId;
  final String? title;

  @override
  ConsumerState<SpendingScreen> createState() => _SpendingScreenState();
}

class _SpendingScreenState extends ConsumerState<SpendingScreen> {
  _Range _range = _Range.year;
  bool _onlyMine = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final m = ref.watch(membershipProvider);
    final unitId = widget.unitId ?? m?.unitId ?? '';
    final myUid = ref.watch(uidProvider) ?? '';
    final lang = Localizations.localeOf(context).languageCode;
    final currency = widget.manager
        ? (ref.watch(profileProvider).value?.currency ?? 'EGP')
        : (ref.watch(residentProfileProvider).value?.currency ?? 'EGP');
    String money(double v) => formatMoney(v, currency, lang);
    final managerUid = widget.manager ? myUid : (m?.managerUid ?? '');

    final all = flatSpending(
      t: t,
      unitId: unitId,
      dues: widget.manager
          ? (ref.watch(duesPaymentsProvider).value ?? const [])
          : (ref.watch(residentDuesPaymentsProvider).value ?? const []),
      shares: widget.manager
          ? (ref.watch(managerSharePaymentsProvider).value ?? const [])
          : (ref.watch(residentSharePaymentsProvider).value ?? const []),
      flatExpenses: widget.manager
          ? (ref.watch(managerFlatExpensesProvider).value ?? const [])
          : (ref.watch(residentFlatExpensesProvider).value ?? const []),
      expenses: widget.manager
          ? (ref.watch(expensesProvider).value ?? const [])
          : (ref.watch(residentExpensesProvider).value ?? const []),
      periodLabel: context.fmtPeriod,
    );
    final month = ref.watch(selectedMonthProvider);
    bool inRange(DateTime d) => switch (_range) {
          _Range.month => d.year == month.year && d.month == month.month,
          _Range.year => d.year == month.year,
          _Range.all => true,
        };
    final items = all.where((i) => inRange(i.date) && (!_onlyMine || i.byUid == myUid)).toList();
    double sum(Iterable<SpendItem> xs) => xs.fold<double>(0, (s, i) => s + i.amount);
    final done = items.where((i) => !i.pending);
    final dues = sum(done.where((i) => i.kind == SpendKind.dues));
    final shares = sum(done.where((i) => i.kind == SpendKind.share));
    final repairs = sum(done.where((i) => i.kind == SpendKind.repair || i.kind == SpendKind.repaid));
    final flat = sum(done.where((i) => i.kind == SpendKind.flat));
    final total = dues + shares + repairs + flat;
    final pending = sum(items.where((i) => i.pending));
    final rangeLabel = switch (_range) {
      _Range.month => context.fmtMonth(month),
      _Range.year => '${month.year}',
      _Range.all => t.allTime,
    };

    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? t.mySpending)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          SegmentedButton<_Range>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: _Range.month, label: Text(t.monthly)),
              ButtonSegment(value: _Range.year, label: Text(t.annually)),
              ButtonSegment(value: _Range.all, label: Text(t.allTime)),
            ],
            selected: {_range},
            onSelectionChanged: (v) => setState(() => _range = v.first),
          ),
          if (_range != _Range.all) const MonthSwitcher(),
          if (_range == _Range.all) gap12,
          // Total
          Entrance(
            scale: 0.96,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.45)!],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t.totalSpent} · $rangeLabel', style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.85))),
                const SizedBox(height: 4),
                AnimatedNumber(
                  value: total,
                  format: money,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w800),
                ),
                if (pending > 0.005)
                  Text(t.pendingNotCounted(money(pending)),
                      style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.85), fontSize: 12)),
              ]),
            ),
          ),
          gap12,
          // Breakdown
          Row(children: [
            Expanded(child: _Figure(icon: Icons.apartment, label: t.spendToBuilding, value: money(dues))),
            gap12,
            Expanded(child: _Figure(icon: Icons.handyman_outlined, label: t.spendShares, value: money(shares))),
          ]),
          gap12,
          Row(children: [
            Expanded(child: _Figure(icon: Icons.build_circle_outlined, label: t.spendRepairsNet, value: money(repairs))),
            gap12,
            Expanded(child: _Figure(icon: Icons.lock_outline, label: t.spendPrivate, value: money(flat))),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(widget.manager ? t.onlyPaidByYou : t.onlyPaidByMe),
            subtitle: Text(t.onlyMineHint),
            value: _onlyMine,
            onChanged: widget.manager ? null : (v) => setState(() => _onlyMine = v),
          ),
          SectionTitle(t.history),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: EmptyState(icon: Icons.receipt_long_outlined, message: t.noSpending),
            )
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final i in items)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _kindColor(cs, i.kind).withValues(alpha: 0.14),
                      child: Icon(_kindIcon(i.kind), size: 20, color: _kindColor(cs, i.kind)),
                    ),
                    title: Text(i.title),
                    subtitle: Text([
                      _kindLabel(t, i.kind),
                      if (i.detail.isNotEmpty) i.detail,
                      context.fmtDate(i.date),
                      if (i.byName.isNotEmpty) i.byName,
                      if (i.pending) t.waitingConfirmation,
                    ].join(' · ')),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          i.amount < 0 ? '+${money(-i.amount)}' : money(i.amount),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: i.pending ? cs.outline : (i.amount < 0 ? const Color(0xFF2E7D32) : null),
                          ),
                        ),
                        AttachmentBadge(count: i.attachmentIds.length),
                      ],
                    ),
                    onTap: i.attachmentIds.isEmpty
                        ? null
                        : () => openAttachmentViewer(context, managerUid, i.attachmentIds),
                  ),
              ]),
            ),
        ],
      ),
    );
  }

  static IconData _kindIcon(SpendKind k) => switch (k) {
        SpendKind.dues => Icons.apartment,
        SpendKind.share => Icons.handyman_outlined,
        SpendKind.repair => Icons.build_circle_outlined,
        SpendKind.repaid => Icons.call_received,
        SpendKind.flat => Icons.lock_outline,
      };

  static Color _kindColor(ColorScheme cs, SpendKind k) => switch (k) {
        SpendKind.dues => cs.primary,
        SpendKind.share => const Color(0xFFB26A00),
        SpendKind.repair => cs.tertiary,
        SpendKind.repaid => const Color(0xFF2E7D32),
        SpendKind.flat => cs.secondary,
      };

  static String _kindLabel(L10n t, SpendKind k) => switch (k) {
        SpendKind.dues => t.spendToBuilding,
        SpendKind.share => t.maintenanceShare,
        SpendKind.repair => t.repairYouPaid,
        SpendKind.repaid => t.repaidToYou,
        SpendKind.flat => t.spendPrivate,
      };
}

class _Figure extends StatelessWidget {
  const _Figure({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: cs.primary),
          gap8,
          Expanded(
            child: Text(label,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ),
        ]),
        gap8,
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      ]),
    );
  }
}
