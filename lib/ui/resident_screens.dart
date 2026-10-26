import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/community.dart';
import '../data/google_auth.dart';
import '../data/models.dart';
import '../data/local_alerts.dart';
import '../data/notifications.dart';
import '../data/phone_account.dart';
import '../data/providers.dart';
import '../data/rent_logic.dart';
import '../l10n/strings.dart';
import 'common.dart';
import 'invoice_pdf.dart';
import 'inbox_screens.dart';
import 'invoices_screen.dart' show PdfPreviewScreen;
import 'properties_screen.dart' show compareFloors;
import 'settings_screen.dart' show LanguageMenuButton;
import 'dues_screen.dart' show dueStateColor;
import 'flat_expenses_screen.dart';
import 'overview_section.dart';
import 'split_editor.dart';

/// Entry point for resident accounts: join → waiting → resident home.
class ResidentGate extends ConsumerWidget {
  const ResidentGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(myRequestProvider);
    return request.when(
      loading: () => PatientLoader(step: 'join request', onRetry: () => ref.invalidate(myRequestProvider)),
      error: (e, _) => ErrorScreen(error: e, onRetry: () => ref.invalidate(myRequestProvider)),
      data: (r) {
        if (r == null) return const JoinBuildingScreen();
        if (r.status == RequestStatus.approved) return const ResidentHome();
        return RequestStatusScreen(request: r);
      },
    );
  }
}

Future<void> _signOut(WidgetRef ref) async {
  await stopBackgroundChecks();
  try {
    await GoogleAuth.signOut();
  } catch (_) {
    // Not signed in with Google.
  }
  await ref.read(firebaseAuthProvider).signOut();
}

List<Widget> _residentActions(BuildContext context, WidgetRef ref) => [
      if (ref.watch(membershipProvider) != null) const InboxBell(),
      if (ref.watch(hasBothRolesProvider))
        IconButton(
          tooltip: context.t.switchToManager,
          icon: const Icon(Icons.manage_accounts_outlined),
          onPressed: () => ref.read(activeViewProvider.notifier).set(kRoleManager),
        ),
      const LanguageMenuButton(),
      IconButton(
        tooltip: context.t.signOut,
        icon: const Icon(Icons.logout),
        onPressed: () async {
          if (await confirmDialog(context, '${context.t.signOut}?', confirmLabel: context.t.signOut)) {
            await _signOut(ref);
          }
        },
      ),
    ];

// ─────────────────────────── Join a building ───────────────────────────

class JoinBuildingScreen extends ConsumerStatefulWidget {
  const JoinBuildingScreen({super.key});

  @override
  ConsumerState<JoinBuildingScreen> createState() => _JoinBuildingScreenState();
}

class _JoinBuildingScreenState extends ConsumerState<JoinBuildingScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  late final _name = TextEditingController(text: ref.read(authStateProvider).value?.displayName ?? '');
  late final _phone =
      TextEditingController(text: displayPhone(phoneOfUser(ref.read(authStateProvider).value) ?? ''));
  bool _prefilled = false;

  /// Fill name / phone from the details given at sign-up, once they load.
  void _prefill(AccountDetails a) {
    if (_prefilled) return;
    _prefilled = true;
    if (_name.text.trim().isEmpty && a.fullName.isNotEmpty) _name.text = a.fullName;
    if (_phone.text.trim().isEmpty && a.phone.isNotEmpty) _phone.text = displayPhone(a.phone);
  }
  BuildingCode? _building;
  String? _unitId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Not in build(): changing a text field while building isn't allowed.
    ref.listenManual<AsyncValue<AccountDetails>>(accountDetailsProvider, (_, next) {
      final a = next.value;
      if (a != null && (a.fullName.isNotEmpty || a.phone.isNotEmpty)) _prefill(a);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final t = context.t;
    setState(() => _busy = true);
    try {
      final b = await ref.read(communityProvider).lookup(_code.text);
      if (!mounted) return;
      if (b == null) {
        toast(context, t.codeNotFound);
      } else {
        setState(() {
          _building = b;
          _unitId = null;
        });
      }
    } catch (e) {
      if (mounted) toast(context, '${t.somethingWrong}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final b = _building;
    final user = ref.read(authStateProvider).value;
    if (b == null || user == null || !_form.currentState!.validate()) return;
    final flat = b.flats.firstWhere((f) => f.id == _unitId);
    setState(() => _busy = true);
    try {
      await ref.read(communityProvider).submitRequest(JoinRequest(
            residentUid: user.uid,
            code: b.code,
            managerUid: b.managerUid,
            propertyId: b.propertyId,
            propertyName: b.propertyName,
            unitId: flat.id,
            unitName: flat.name,
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            // Phone accounts sign in with a hidden address; use the real email.
            email: phoneOfUser(user) != null
                ? (ref.read(accountDetailsProvider).value?.email ?? '')
                : (user.email ?? ''),
            createdAt: DateTime.now(),
          ));
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
    final b = _building;
    // Several residents can share a flat, so every flat is offered.
    final freeFlats = b == null
        ? const <CodeFlat>[]
        : (b.flats.toList()
          ..sort((x, y) {
            final c = compareFloors(x.floor, y.floor);
            return c != 0 ? c : x.name.compareTo(y.name);
          }));

    return Scaffold(
      appBar: AppBar(title: Text(t.joinYourBuilding), actions: _residentActions(context, ref)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(t.joinIntro, style: TextStyle(color: cs.onSurfaceVariant)),
            gap16,
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextFormField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(labelText: t.buildingCode, hintText: 'AB12CD'),
                  onFieldSubmitted: (_) => _lookup(),
                ),
              ),
              gap12,
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: FilledButton(
                  onPressed: _busy ? null : _lookup,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  child: Text(t.find),
                ),
              ),
            ]),
            if (b != null) ...[
              gap16,
              Panel(
                child: Row(children: [
                  Icon(Icons.apartment, color: cs.primary),
                  gap12,
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.propertyName, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (b.address.isNotEmpty)
                        Text(b.address, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    ]),
                  ),
                ]),
              ),
              gap16,
              if (freeFlats.isEmpty)
                Text(t.noFlatsInBuilding, style: TextStyle(color: cs.error))
              else
                DropdownButtonFormField<String>(
                  initialValue: _unitId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: t.yourFlat),
                  items: [
                    for (final f in freeFlats)
                      DropdownMenuItem(
                        value: f.id,
                        child: Text(
                          [
                            f.name,
                            t.floorLabel(f.floor),
                            if (b != null && b.takenUnitIds.contains(f.id)) t.flatHasResidents,
                          ].join(' · '),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  validator: (v) => v == null ? t.selectYourFlat : null,
                  onChanged: (v) => setState(() => _unitId = v),
                ),
              gap12,
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: t.yourName),
                validator: requiredValidator(context),
              ),
              gap12,
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: t.phone),
              ),
              gap16,
              FilledButton.icon(
                onPressed: _busy || freeFlats.isEmpty ? null : _submit,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                icon: const Icon(Icons.send_outlined),
                label: Text(t.sendRequest),
              ),
              gap8,
              Text(t.approvalNote, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Waiting / declined ───────────────────────────

class RequestStatusScreen extends ConsumerWidget {
  const RequestStatusScreen({super.key, required this.request});
  final JoinRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final pending = request.status == RequestStatus.pending;
    return Scaffold(
      appBar: AppBar(actions: _residentActions(context, ref)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(pending ? Icons.hourglass_top : Icons.block,
                size: 64, color: pending ? cs.primary : cs.error),
            gap16,
            Text(pending ? t.waitingForApproval : t.requestNotApproved(request.status),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            gap8,
            Text('${request.unitName} · ${request.propertyName}',
                textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            gap8,
            Text(pending ? t.waitingHint : t.tryAgainHint,
                textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => ref.read(communityProvider).cancelRequest(request.residentUid),
              child: Text(pending ? t.cancelRequest : t.tryAgain),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────── Resident home ───────────────────────────

class ResidentHome extends ConsumerStatefulWidget {
  const ResidentHome({super.key});

  @override
  ConsumerState<ResidentHome> createState() => _ResidentHomeState();
}

class _ResidentHomeState extends ConsumerState<ResidentHome> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final m = ref.watch(membershipProvider);
    final property = ref.watch(residentPropertyProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m?.unitName ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(property?.name ?? m?.propertyName ?? '',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
        actions: _residentActions(context, ref),
      ),
      body: FadeIndexedStack(
          index: _index, children: const [_DuesTab(), _ExpensesTab(), FlatExpensesTab(), _InvoicesTab()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.request_quote_outlined),
              selectedIcon: const Icon(Icons.request_quote),
              label: t.myDues),
          NavigationDestination(
              icon: const Icon(Icons.bolt_outlined), selectedIcon: const Icon(Icons.bolt), label: t.buildingExpenses),
          NavigationDestination(
              icon: const Icon(Icons.home_repair_service_outlined),
              selectedIcon: const Icon(Icons.home_repair_service),
              label: t.flatExpensesTab),
          NavigationDestination(
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: const Icon(Icons.receipt_long),
              label: t.invoices),
        ],
      ),
    );
  }
}

/// Money in the building manager's currency.
String _money(WidgetRef ref, BuildContext context, double v) => formatMoney(
    v,
    ref.watch(residentProfileProvider).value?.currency ?? 'EGP',
    Localizations.localeOf(context).languageCode);

class _DuesTab extends ConsumerWidget {
  const _DuesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final unitAsync = ref.watch(residentUnitProvider);
    final unit = unitAsync.value;
    final property = ref.watch(residentPropertyProvider).value;
    final month = ref.watch(selectedMonthProvider);
    final expenses = ref.watch(residentExpensesProvider).value ?? const <Expense>[];
    final payments = ref.watch(residentDuesPaymentsProvider).value ?? const <DuesPayment>[];
    final units = ref.watch(residentBuildingUnitsProvider).value ?? const <Unit>[];
    String m(double v) => _money(ref, context, v);

    if (unit == null) {
      if (unitAsync.isLoading) {
        return PatientLoader(
            step: 'flat', fullScreen: false, onRetry: () => ref.invalidate(residentUnitProvider));
      }
      // The flat was deleted, or can't be read: say so instead of spinning.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.door_front_door_outlined, size: 48, color: cs.outline),
            const SizedBox(height: 12),
            Text(t.flatNotFound,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(t.flatNotFoundHint, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            if (unitAsync.hasError) ...[
              const SizedBox(height: 8),
              Text('${unitAsync.error}', textAlign: TextAlign.center, style: TextStyle(color: cs.error, fontSize: 12)),
            ],
          ]),
        ),
      );
    }
    final status = monthStatuses(
            propertyId: unit.propertyId, month: month, units: [unit], expenses: expenses, payments: payments)
        .first;
    final due = status.due;
    final p = status.payment;

    Widget line(String label, double value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(
                child: Text(label,
                    style: bold
                        ? const TextStyle(fontWeight: FontWeight.w700)
                        : TextStyle(color: cs.onSurfaceVariant))),
            Text(m(value), style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ]),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        const MonthSwitcher(),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(t.totalDue, style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.8)))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: cs.onPrimary, borderRadius: BorderRadius.circular(20)),
                child: Text(t.dueState(status.state),
                    style: TextStyle(color: dueStateColor(status.state), fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 4),
            AnimatedNumber(
                value: due.total,
                format: m,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(context.fmtMonth(month), style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.8))),
            if (status.state == DueState.unpaid) ...[
              gap12,
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: cs.onPrimary, foregroundColor: cs.primary),
                onPressed: () => _claimPaymentSheet(context, ref, status),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(t.iHavePaid),
              ),
            ],
          ]),
        ),
        if (p != null) ...[
          gap8,
          Text(
            [
              t.paymentStatusLine(p.status),
              m(p.amount),
              t.paymentMethod(p.method),
              context.fmtDate(p.paidAt),
              if (p.note.isNotEmpty) '“${p.note}”',
            ].join(' · '),
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ],
        _FlatStatusPanel(unit: unit, property: property),
        SectionTitle(t.quickActions),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(
            avatar: const Icon(Icons.handyman_outlined, size: 18),
            label: Text(t.maintenanceRequest),
            onPressed: () => pushForm(context, const MaintenanceRequestScreen()),
          ),
          ActionChip(
            avatar: const Icon(Icons.add_card_outlined, size: 18),
            label: Text(t.suggestExpense),
            onPressed: () => pushForm(context, const ProposeExpenseScreen()),
          ),
        ]),
        SectionTitle(t.breakdown),
        Panel(
          child: Column(children: [
            line(t.monthlyFees, due.fixedFee),
            for (final (e, share) in due.expenseShares)
              line('${t.expenseCategory(e.category)}${e.vendor.isEmpty ? '' : ' · ${e.vendor}'}', share),
            const Divider(height: 16),
            line(t.totalDue, due.total, bold: true),
          ]),
        ),
        if (property != null && units.isNotEmpty)
          OverviewSection(
            properties: [property],
            units: units,
            expenses: expenses,
            payments: payments,
            formatMoney: m,
            showLateNames: false,
          ),
      ],
    );
  }
}

/// Resident tells the manager they paid this month's dues.
Future<void> _claimPaymentSheet(BuildContext context, WidgetRef ref, FlatMonthStatus status) async {
  final t = context.t;
  final membership = ref.read(membershipProvider);
  if (membership == null) return;
  final month = ref.read(selectedMonthProvider);
  final amount = TextEditingController(text: numText(status.outstanding > 0 ? status.outstanding : status.due.total));
  final note = TextEditingController();
  var method = PaymentMethod.cash;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${t.iHavePaid} · ${c.fmtMonth(month)}', style: Theme.of(c).textTheme.titleLarge),
          gap8,
          Text(t.claimHint, style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)),
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
          gap12,
          TextField(
            controller: note,
            decoration: InputDecoration(labelText: t.notes, hintText: t.paymentNoteHint),
          ),
          gap16,
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: Text(t.sendForApproval),
          ),
        ]),
      ),
    ),
  );
  final value = parseNumber(amount.text) ?? 0;
  final noteText = note.text.trim();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    amount.dispose();
    note.dispose();
  });
  if (ok != true || value <= 0) return;
  final payment = DuesPayment(
    propertyId: membership.propertyId,
    unitId: membership.unitId,
    period: periodKey(month),
    amount: value,
    method: method,
    note: noteText,
    paidByName: membership.name,
    paidByUid: membership.residentUid,
  );
  try {
    await claimDuesPayment(ref.read(firestoreProvider), membership, payment);
    final notifier = ref.read(notifierProvider);
    await notifier?.sendSame([membership.managerUid], InboxItem(
      title: t.ar ? 'دفعة في انتظار التأكيد' : 'Payment waiting for confirmation',
      body: '${membership.unitName} · ${numText(value)} · ${membership.name}',
      type: NoticeType.proposal,
      senderName: membership.name,
      createdAt: DateTime.now(),
    ));
    if (context.mounted) toast(context, t.paymentClaimSent);
  } catch (e) {
    if (context.mounted) toast(context, '${t.somethingWrong}: $e');
  }
}

class _ExpensesTab extends ConsumerWidget {
  const _ExpensesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final month = ref.watch(selectedMonthProvider);
    final unitId = ref.watch(membershipProvider)?.unitId ?? '';
    final list = (ref.watch(residentExpensesProvider).value ?? const <Expense>[])
        .where((e) => periodKey(e.date) == periodKey(month))
        .toList();
    final total = list.fold<double>(0, (s, e) => s + e.amount);
    final mine = list.fold<double>(0, (s, e) => s + e.shareFor(unitId));
    String m(double v) => _money(ref, context, v);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        const MonthSwitcher(),
        FilledButton.tonalIcon(
          onPressed: () => pushForm(context, const ProposeExpenseScreen()),
          icon: const Icon(Icons.add),
          label: Text(t.suggestExpense),
        ),
        const _MyProposalsPanel(),
        gap12,
        Panel(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.buildingTotal, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                Text(m(total), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.yourShare, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                Text(m(mine), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: cs.primary)),
              ]),
            ),
          ]),
        ),
        gap12,
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: EmptyState(icon: Icons.bolt_outlined, message: t.noExpenses),
          )
        else
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final e in list)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.secondaryContainer,
                    child: Icon(expenseIcon(e.category), size: 20, color: cs.onSecondaryContainer),
                  ),
                  title: Text(t.expenseCategory(e.category) + (e.vendor.isEmpty ? '' : ' · ${e.vendor}')),
                  subtitle: Text([
                    context.fmtDate(e.date),
                    if (e.shareFor(unitId) > 0) '${t.yourShare}: ${m(e.shareFor(unitId))}',
                  ].join(' · ')),
                  trailing: Text(m(e.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
      ],
    );
  }
}

class _InvoicesTab extends ConsumerWidget {
  const _InvoicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final list = ref.watch(residentInvoicesProvider).value ?? const <Invoice>[];
    final membership = ref.watch(membershipProvider);
    final profile = ref.watch(residentProfileProvider).value ?? const BusinessProfile();
    final property = ref.watch(residentPropertyProvider).value;
    final unitAsync = ref.watch(residentUnitProvider);
    final unit = unitAsync.value;

    if (list.isEmpty) {
      return EmptyState(icon: Icons.receipt_long_outlined, message: t.noInvoices);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final inv = list[i];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
          title: Text(inv.number),
          subtitle: Text('${context.fmtDate(inv.issueDate)} · ${t.dueDate}: ${context.fmtDate(inv.dueDate)}'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_money(ref, context, inv.total), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              StatusChip.invoice(context, inv.status),
            ],
          ),
          onTap: () => push(
            context,
            PdfPreviewScreen(
              title: inv.number,
              generate: () => buildInvoicePdf(
                invoice: inv,
                profile: profile,
                arabic: t.ar,
                unit: unit,
                property: property,
                billToName: membership?.name,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────── Resident: propose an expense ───────────────────────────

class ProposeExpenseScreen extends ConsumerStatefulWidget {
  const ProposeExpenseScreen({super.key});

  @override
  ConsumerState<ProposeExpenseScreen> createState() => _ProposeExpenseScreenState();
}

class _ProposeExpenseScreenState extends ConsumerState<ProposeExpenseScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _vendor = TextEditingController();
  final _notes = TextEditingController();
  ExpenseCategory _category = ExpenseCategory.maintenance;
  DateTime _date = DateTime.now();
  SplitMethod _split = SplitMethod.equal;
  Set<String> _excluded = {};
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _vendor.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = context.t;
    final m = ref.read(membershipProvider);
    if (m == null || !_form.currentState!.validate()) return;
    final units = ref.read(residentBuildingUnitsProvider).value ?? const <Unit>[];
    final amount = parseNumber(_amount.text) ?? 0;
    final shares = SplitEditor.compute(units: units, amount: amount, method: _split, excludedFloors: _excluded);
    if (shares.isEmpty) {
      toast(context, t.noFlatsToSplit);
      return;
    }
    setState(() => _busy = true);
    try {
      final proposal = ExpenseProposal(
            managerUid: m.managerUid,
            propertyId: m.propertyId,
            residentUid: m.residentUid,
            residentName: m.name,
            unitId: m.unitId,
            unitName: m.unitName,
            category: _category,
            amount: amount,
            date: _date,
            vendor: _vendor.text.trim(),
            notes: _notes.text.trim(),
            split: _split,
            splitFloors: SplitEditor.includedFloors(units, _excluded),
            shares: shares,
            createdAt: DateTime.now(),
          );
      await ref.read(proposalServiceProvider).submit(proposal);
      try {
        await notifyProposalSubmitted(ref, proposal, arabic: t.ar);
      } catch (e) {
        debugPrint('Notification not sent: $e');
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(t.expenseSubmitted)));
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
    final units = ref.watch(residentBuildingUnitsProvider).value ?? const <Unit>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(t.suggestExpense),
        actions: [TextButton(onPressed: _busy ? null : _submit, child: Text(t.sendForApproval))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(t.suggestExpenseHint, style: TextStyle(color: cs.onSurfaceVariant)),
            gap16,
            Text(t.category, style: Theme.of(context).textTheme.labelLarge),
            gap8,
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final c in ExpenseCategory.values)
                ChoiceChip(
                  avatar: Icon(expenseIcon(c), size: 18),
                  label: Text(t.expenseCategory(c)),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ]),
            gap16,
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: t.amount),
                  validator: numberValidator(context),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              gap12,
              Expanded(
                child: DateField(label: t.date, value: _date, onChanged: (d) => setState(() => _date = d ?? _date)),
              ),
            ]),
            gap12,
            TextFormField(controller: _vendor, decoration: InputDecoration(labelText: t.vendor)),
            if (units.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else
              SplitEditor(
                units: units,
                amount: parseNumber(_amount.text) ?? 0,
                method: _split,
                excludedFloors: _excluded,
                allowNone: false,
                formatMoney: (v) => _money(ref, context, v),
                onChanged: (m, ex) => setState(() {
                  _split = m;
                  _excluded = ex;
                }),
              ),
            gap12,
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(labelText: t.notes, hintText: t.proposalNotesHint),
            ),
            gap16,
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.send_outlined),
              label: Text(t.sendForApproval),
            ),
          ],
        ),
      ),
    );
  }
}

Color proposalColor(RequestStatus s) => switch (s) {
      RequestStatus.pending => const Color(0xFFB26A00),
      RequestStatus.approved => const Color(0xFF2E7D32),
      _ => const Color(0xFFC62828),
    };

/// The resident's own submissions, newest first.
class _MyProposalsPanel extends ConsumerWidget {
  const _MyProposalsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final list = (ref.watch(myProposalsProvider).value ?? const <ExpenseProposal>[])
        .where((p) => p.status != RequestStatus.approved || DateTime.now().difference(p.createdAt).inDays < 30)
        .take(10)
        .toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(t.mySubmissions),
      Panel(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (final p in list)
            ListTile(
              leading: Icon(p.isMaintenance ? Icons.handyman_outlined : expenseIcon(p.category),
                  color: proposalColor(p.status)),
              title: Text(p.isMaintenance
                  ? p.title
                  : '${t.expenseCategory(p.category)}${p.vendor.isEmpty ? '' : ' · ${p.vendor}'}'),
              subtitle: Text([
                context.fmtDate(p.date),
                if (p.isMaintenance) t.maintenanceRequest else t.splitMethod(p.split),
                if (p.decisionNote.isNotEmpty) '“${p.decisionNote}”',
              ].join(' · ')),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (p.amount > 0)
                    Text(_money(ref, context, p.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  StatusChip(label: t.proposalStatus(p.status), color: proposalColor(p.status)),
                ],
              ),
              onLongPress: p.status == RequestStatus.pending
                  ? () async {
                      if (await confirmDialog(context, t.withdrawConfirm, confirmLabel: t.withdraw)) {
                        await ref.read(proposalServiceProvider).withdraw(p.id);
                      }
                    }
                  : null,
            ),
        ]),
      ),
      if (list.any((p) => p.status == RequestStatus.pending))
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(t.withdrawHint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ),
    ]);
  }
}

// ─────────────────────────── Maintenance request ───────────────────────────

/// Resident reports something that needs fixing. The manager approves it and
/// then sets the cost and how it is split between floors / flats.
class MaintenanceRequestScreen extends ConsumerStatefulWidget {
  const MaintenanceRequestScreen({super.key});

  @override
  ConsumerState<MaintenanceRequestScreen> createState() => _MaintenanceRequestScreenState();
}

class _MaintenanceRequestScreenState extends ConsumerState<MaintenanceRequestScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _details = TextEditingController();
  final _estimate = TextEditingController();
  Urgency _urgency = Urgency.normal;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    _estimate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = context.t;
    final m = ref.read(membershipProvider);
    if (m == null || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final request = ExpenseProposal(
        kind: ProposalKind.maintenance,
        title: _title.text.trim(),
        urgency: _urgency,
        managerUid: m.managerUid,
        propertyId: m.propertyId,
        residentUid: m.residentUid,
        residentName: m.name,
        unitId: m.unitId,
        unitName: m.unitName,
        category: ExpenseCategory.maintenance,
        amount: parseNumber(_estimate.text) ?? 0,
        date: DateTime.now(),
        notes: _details.text.trim(),
        split: SplitMethod.equal,
        createdAt: DateTime.now(),
      );
      await ref.read(proposalServiceProvider).submit(request);
      try {
        await ref.read(notifierProvider)?.sendSame([m.managerUid], InboxItem(
          title: t.ar ? 'طلب صيانة جديد' : 'New maintenance request',
          body: '${request.title} · ${m.unitName} · ${t.urgencyLabel(_urgency)}',
          type: NoticeType.proposal,
          senderName: m.name,
          createdAt: DateTime.now(),
        ));
      } catch (e) {
        debugPrint('Notification not sent: $e');
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(t.maintenanceSent)));
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
    return Scaffold(
      appBar: AppBar(
        title: Text(t.maintenanceRequest),
        actions: [TextButton(onPressed: _busy ? null : _submit, child: Text(t.send))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(t.maintenanceHint, style: TextStyle(color: cs.onSurfaceVariant)),
            gap16,
            TextFormField(
              controller: _title,
              maxLength: 80,
              decoration: InputDecoration(labelText: t.whatNeedsFixing, hintText: t.whatNeedsFixingHint),
              validator: requiredValidator(context),
            ),
            gap8,
            TextFormField(
              controller: _details,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(labelText: t.details, hintText: t.detailsHint, alignLabelWithHint: true),
            ),
            gap16,
            Text(t.urgency, style: Theme.of(context).textTheme.labelLarge),
            gap8,
            SegmentedButton<Urgency>(
              showSelectedIcon: false,
              segments: [
                for (final u in Urgency.values) ButtonSegment(value: u, label: Text(t.urgencyLabel(u))),
              ],
              selected: {_urgency},
              onSelectionChanged: (v) => setState(() => _urgency = v.first),
            ),
            gap16,
            TextFormField(
              controller: _estimate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: t.estimatedCost),
              validator: numberValidator(context, isRequired: false),
            ),
            gap16,
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.send_outlined),
              label: Text(t.sendForApproval),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resident chooses whether they live in the flat (occupied) or it's closed.
/// Any resident linked to the flat can change it; the manager is notified.
class _FlatStatusPanel extends ConsumerStatefulWidget {
  const _FlatStatusPanel({required this.unit, required this.property});
  final Unit unit;
  final Property? property;

  @override
  ConsumerState<_FlatStatusPanel> createState() => _FlatStatusPanelState();
}

class _FlatStatusPanelState extends ConsumerState<_FlatStatusPanel> {
  bool _busy = false;

  Future<void> _set(UnitStatus status) async {
    final t = context.t;
    final m = ref.read(membershipProvider);
    if (m == null || status == widget.unit.status) return;
    setState(() => _busy = true);
    try {
      await setFlatStatusAsResident(ref.read(firestoreProvider), m, widget.unit, widget.property, status);
      unawaited(notifyFlatStatusChanged(ref,
              managerUid: m.managerUid,
              residentName: m.name,
              unitName: widget.unit.name,
              occupied: status == UnitStatus.ownerResident,
              arabic: t.ar)
          .catchError((Object e) => debugPrint('Status notice failed: $e')));
      if (mounted) toast(context, t.flatStatusSaved);
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
    // A flat marked "rented" by the manager shows as occupied here.
    final current = widget.unit.status == UnitStatus.closed ? UnitStatus.closed : UnitStatus.ownerResident;
    final p = widget.property;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(t.myFlatStatus),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<UnitStatus>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: UnitStatus.ownerResident,
                  icon: const Icon(Icons.home_outlined),
                  label: Text(t.flatOccupied)),
              ButtonSegment(
                  value: UnitStatus.closed, icon: const Icon(Icons.lock_outline), label: Text(t.flatClosed)),
            ],
            selected: {current},
            onSelectionChanged: _busy ? null : (v) => _set(v.first),
          ),
          gap8,
          Text(
            [
              t.flatStatusHint,
              if (p != null && p.feeOccupied != p.feeClosed)
                t.flatStatusFees(
                  _money(ref, context, p.feeOccupied),
                  _money(ref, context, p.feeClosed),
                ),
            ].join(' '),
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ]),
      ),
    ]);
  }
}
