import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/attachments.dart';
import '../data/maintenance_invoice.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import '../data/dues_logic.dart';
import '../data/community.dart';
import '../data/notifications.dart';
import 'attachments_widgets.dart';
import 'common.dart';
import 'community_screens.dart' show ProposalsBanner;
import 'properties_screen.dart' show compareFloors;
import 'share_payments_ui.dart' show ExpenseSharePaymentsPanel;

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  String? _propertyId; // null = all

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final month = ref.watch(selectedMonthProvider);
    final key = periodKey(month);
    final props = ref.watch(propertiesProvider).value ?? const <Property>[];
    final propById = ref.watch(propertyByIdProvider);
    final unitById = ref.watch(unitByIdProvider);
    final list = (ref.watch(expensesProvider).value ?? const <Expense>[])
        .where((e) => periodKey(e.date) == key)
        .where((e) => _propertyId == null || e.propertyId == _propertyId)
        .toList();
    final total = list.fold<double>(0, (s, e) => s + e.amount);
    final byCategory = <ExpenseCategory, double>{};
    for (final e in list) {
      byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
    }
    final breakdown = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(t.expenses)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => pushForm(context, ExpenseForm(presetPropertyId: _propertyId)),
        icon: const Icon(Icons.add),
        label: Text(t.addExpense),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          const MonthSwitcher(),
          const ProposalsBanner(),
          if (props.length > 1)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ChoiceChip(
                    label: Text(t.allProperties),
                    selected: _propertyId == null,
                    onSelected: (_) => setState(() => _propertyId = null),
                  ),
                  for (final p in props) ...[
                    gap8,
                    ChoiceChip(
                      label: Text(p.name),
                      selected: _propertyId == p.id,
                      onSelected: (_) => setState(() => _propertyId = p.id),
                    ),
                  ],
                ],
              ),
            ),
          gap8,
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.total, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                Text(money(ref, context, total),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (breakdown.isNotEmpty) gap12,
                for (final entry in breakdown)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Icon(expenseIcon(entry.key), size: 18, color: cs.primary),
                      gap8,
                      SizedBox(width: 96, child: Text(t.expenseCategory(entry.key))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: total == 0 ? 0.0 : entry.value / total,
                            minHeight: 8,
                            backgroundColor: cs.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      gap8,
                      Text(money(ref, context, entry.value), style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
              ],
            ),
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
                      propById[e.propertyId]?.name,
                      e.unitId.isEmpty ? t.wholeBuilding : unitById[e.unitId]?.name,
                      if (e.isSplit) t.splitNote(e.shares.length),
                      if (e.proposedByName.isNotEmpty) t.addedByResident(e.proposedByName),
                      if (e.paidByResident) t.paidByResidentNote(e.payToName),
                      context.fmtDate(e.date),
                    ].whereType<String>().join(' · ')),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(money(ref, context, e.amount),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        AttachmentBadge(count: e.attachmentIds.length),
                      ],
                    ),
                    onTap: () => pushForm(context, ExpenseForm(existing: e)),
                  ),
              ]),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────── Form ───────────────────────────────

class ExpenseForm extends ConsumerStatefulWidget {
  const ExpenseForm({super.key, this.existing, this.presetPropertyId, this.fromProposal, this.presetCategory});
  final Expense? existing;
  final String? presetPropertyId;

  /// e.g. maintenance, from the home-page quick action.
  final ExpenseCategory? presetCategory;

  /// Resident submission being edited before approval.
  final ExpenseProposal? fromProposal;

  @override
  ConsumerState<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<ExpenseForm> {
  final _form = GlobalKey<FormState>();
  late final Expense? _e = widget.existing;
  late final ExpenseProposal? _p = widget.fromProposal;
  late final _amount = TextEditingController(text: numText(_e?.amount ?? _p?.amount ?? 0));
  late final _vendor = TextEditingController(text: _e?.vendor ?? _p?.vendor);
  late final _notes = TextEditingController(
      text: _e?.notes ??
          (_p == null
              ? null
              : [
                  if (widget.fromProposal!.isMaintenance) widget.fromProposal!.title,
                  if (widget.fromProposal!.notes.isNotEmpty) widget.fromProposal!.notes,
                ].join('\n')));
  late String? _propertyId = _e?.propertyId ?? _p?.propertyId ?? widget.presetPropertyId;
  late String _unitId = _e?.unitId ?? '';
  late ExpenseCategory _category =
      _e?.category ?? _p?.category ?? widget.presetCategory ?? ExpenseCategory.electricity;
  late DateTime _date = _e?.date ?? _p?.date ?? DateTime.now();
  late SplitMethod _split = _e?.split ?? _p?.split ?? SplitMethod.equal;
  bool _notify = true;

  late final AttachmentService _attachments;
  late final AttachmentController _photos;

  @override
  void initState() {
    super.initState();
    _attachments = ref.read(attachmentServiceProvider);
    final uid = ref.read(uidProvider) ?? '';
    _photos = AttachmentController(
      managerUid: uid,
      propertyId: _propertyId ?? '',
      unitId: _unitId,
      scope: AttachmentScope.building,
      uploaderUid: uid,
      // A resident's photos come along when approving their request.
      initial: _e?.attachmentIds ?? _p?.attachmentIds ?? const [],
    );
  }

  /// Floors excluded from the split. Stored as exclusions so floors added to
  /// the building later are included by default.
  late final Set<String> _excludedFloors = {};
  bool _floorsLoaded = false;

  @override
  void dispose() {
    _photos.discard(_attachments);
    _photos.dispose();
    _amount.dispose();
    _vendor.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Occupancy comes from each flat's status.
  Set<String> get _withTenant => const {};

  List<Unit> get _units => (ref.read(unitsProvider).value ?? const <Unit>[])
      .where((u) => u.propertyId == _propertyId)
      .toList();

  List<String> _floorsOf(List<Unit> units) =>
      units.map((u) => u.floor.trim()).toSet().toList()..sort(compareFloors);

  List<String> _includedFloors(List<Unit> units) {
    final all = _floorsOf(units);
    if (_excludedFloors.isEmpty) return const []; // empty = all floors
    return all.where((f) => !_excludedFloors.contains(f)).toList();
  }

  List<ExpenseShare> _shares(List<Unit> units) {
    if (_unitId.isNotEmpty) return const [];
    final included = _includedFloors(units);
    // Every floor excluded → nobody shares it.
    if (_excludedFloors.isNotEmpty && included.isEmpty) return const [];
    return splitExpense(
      amount: parseNumber(_amount.text) ?? 0,
      units: units,
      method: _split,
      floors: included,
      withTenant: _withTenant,
    );
  }

  void _save() {
    if (!_form.currentState!.validate() || _propertyId == null) return;
    final units = _units;
    final wholeBuilding = _unitId.isEmpty;
    final shares = wholeBuilding ? _shares(units) : const <ExpenseShare>[];
    _photos
      ..propertyId = _propertyId!
      ..unitId = _unitId;
    final photoIds = _photos.commit(_attachments, retag: true);
    final expense = Expense(
          id: _e?.id ?? '',
          propertyId: _propertyId!,
          unitId: _unitId,
          category: _category,
          amount: parseNumber(_amount.text) ?? 0,
          date: _date,
          vendor: _vendor.text.trim(),
          billToTenant: false,
          notes: _notes.text.trim(),
          split: wholeBuilding && shares.isNotEmpty ? _split : SplitMethod.none,
          splitFloors: wholeBuilding ? _includedFloors(units) : const [],
          shares: shares,
          proposedByName: _e?.proposedByName ?? _p?.residentName ?? '',
          proposalId: _e?.proposalId ?? _p?.id ?? '',
          attachmentIds: photoIds,
          // Approving a maintenance request: the requester is repaid by the
          // other flats directly.
          payToUid: _e?.payToUid ?? (_p?.isMaintenance == true ? _p!.residentUid : ''),
          payToName: _e?.payToName ?? (_p?.isMaintenance == true ? _p!.residentName : ''),
          payToUnitId: _e?.payToUnitId ?? (_p?.isMaintenance == true ? _p!.unitId : ''),
        );
    final id = ref.read(expenseRepo).save(expense);
    // Approved maintenance request: keep its invoice (created on approval,
    // updated if the expense is edited later).
    if (expense.paidByResident) {
      final invoices = ref.read(invoicesProvider).value ?? const <Invoice>[];
      final existing = invoices.where((i) => i.id == maintenanceInvoiceId(id)).firstOrNull;
      final profile = ref.read(profileProvider).value ?? const BusinessProfile();
      final title = _p?.title.isNotEmpty == true ? _p!.title : _notes.text.trim().split('\n').first;
      ref.read(invoiceRepo).save(buildMaintenanceInvoice(
            t: context.t,
            expense: expense,
            expenseId: id,
            title: title,
            number: '${profile.invoicePrefix}'
                '${ref.read(userDocRepo).nextInvoiceNumber(invoices).toString().padLeft(4, '0')}',
            existing: existing,
          ));
    }
    final arabic = context.t.ar;
    final profile = ref.read(profileProvider).value ?? const BusinessProfile();
    final managerName = profile.name.isEmpty ? context.t.roleManager : profile.name;
    void report(Object e) => debugPrint('Notification not sent: $e');
    final proposal = _p;
    if (proposal != null) {
      ref.read(proposalServiceProvider).markApproved(proposal.id, id).catchError((Object e) {
        debugPrint('Proposal not marked approved: $e');
      });
      notifyProposalDecision(ref, proposal, approved: true, managerName: managerName, arabic: arabic)
          .catchError(report);
    }
    // Tell the building's residents about new expenses.
    if (_e == null && _notify) {
      notifyExpenseAdded(ref, expense, managerName: managerName, currency: profile.currency, arabic: arabic)
          .catchError(report);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final props = ref.watch(propertiesProvider).value ?? const <Property>[];
    if (_propertyId == null && props.length == 1) _propertyId = props.first.id;
    final units = (ref.watch(unitsProvider).value ?? const <Unit>[])
        .where((u) => u.propertyId == _propertyId)
        .toList();

    // When editing, restore which floors were left out of the split.
    if (!_floorsLoaded && units.isNotEmpty) {
      _floorsLoaded = true;
      final saved = _e?.splitFloors ?? _p?.splitFloors ?? const <String>[];
      if (saved.isNotEmpty) {
        _excludedFloors.addAll(_floorsOf(units).where((f) => !saved.contains(f)));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_p != null
            ? (widget.fromProposal!.isMaintenance ? t.approveAndSetShares : t.editAndApprove)
            : (_e == null
                ? (widget.presetCategory == ExpenseCategory.maintenance ? t.maintenanceRequest : t.addExpense)
                : t.editExpense)),
        actions: [
          if (_e != null)
            IconButton(
              tooltip: t.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmDialog(context, t.deleteConfirm, confirmLabel: t.delete)) {
                  ref.read(expenseRepo).delete(_e.id);
                  if (_e.paidByResident) ref.read(invoiceRepo).delete(maintenanceInvoiceId(_e.id));
                  for (final id in _e.attachmentIds) {
                    _attachments.delete(_photos.managerUid, id).catchError((Object e) => debugPrint('$e'));
                  }
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          TextButton(onPressed: props.isEmpty ? null : _save, child: Text(_p != null ? t.approve : t.save)),
        ],
      ),
      body: props.isEmpty
          ? EmptyState(icon: Icons.apartment_outlined, message: t.getStarted)
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_p != null || (_e?.proposedByName.isNotEmpty ?? false)) ...[
                    Panel(
                      child: Row(children: [
                        const Icon(Icons.person_outline),
                        gap12,
                        Expanded(
                          child: Text(_p != null
                              ? t.submittedBy(widget.fromProposal!.residentName, widget.fromProposal!.unitName)
                              : t.addedByResident(_e!.proposedByName)),
                        ),
                      ]),
                    ),
                    gap16,
                  ],
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
                  DropdownButtonFormField<String>(
                    initialValue: _propertyId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t.property),
                    items: [
                      for (final p in props) DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    validator: (v) => v == null ? t.requiredField : null,
                    onChanged: (v) => setState(() {
                      _propertyId = v;
                      _unitId = '';
                      _excludedFloors.clear();
                    }),
                  ),
                  gap12,
                  DropdownButtonFormField<String>(
                    // Re-create when the property changes so the value resets.
                    key: ValueKey(_propertyId),
                    initialValue: units.any((u) => u.id == _unitId) ? _unitId : '',
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t.unit),
                    items: [
                      DropdownMenuItem(value: '', child: Text(t.wholeBuilding)),
                      for (final u in units) DropdownMenuItem(value: u.id, child: Text(u.name)),
                    ],
                    onChanged: (v) => setState(() => _unitId = v ?? ''),
                  ),
                  gap12,
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
                      child: DateField(
                        label: t.date,
                        value: _date,
                        onChanged: (d) => setState(() => _date = d ?? _date),
                      ),
                    ),
                  ]),
                  gap12,
                  TextFormField(controller: _vendor, decoration: InputDecoration(labelText: t.vendor)),
                  if (_unitId.isEmpty && units.isNotEmpty) _splitSection(context, units),
                  if (_e == null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.notifications_active_outlined),
                      title: Text(t.notifyResidents),
                      subtitle: Text(t.notifyResidentsHint),
                      value: _notify,
                      onChanged: (v) => setState(() => _notify = v),
                    ),
                  gap12,
                  TextFormField(controller: _notes, maxLines: 3, decoration: InputDecoration(labelText: t.notes)),
                  gap16,
                  AttachmentPicker(controller: _photos, label: t.receiptPhotos),
                  if (_e != null && _e.paidByResident && _e.isSplit) ExpenseSharePaymentsPanel(expense: _e),
                ],
              ),
            ),
    );
  }

  Widget _splitSection(BuildContext context, List<Unit> units) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final floors = _floorsOf(units);
    final shares = _shares(units);
    final byId = {for (final u in units) u.id: u};
    final amount = parseNumber(_amount.text) ?? 0;

    // Preview grouped by floor.
    final grouped = <String, List<ExpenseShare>>{};
    for (final sh in shares) {
      grouped.putIfAbsent(byId[sh.unitId]?.floor.trim() ?? '', () => []).add(sh);
    }
    final previewFloors = grouped.keys.toList()..sort(compareFloors);
    final hasAreas = units.any((u) => u.area > 0);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(t.splitBetweenFlats),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final m in SplitMethod.values)
          if (m != SplitMethod.area || hasAreas || _split == SplitMethod.area)
            ChoiceChip(
              label: Text(t.splitMethod(m)),
              selected: _split == m,
              onSelected: (_) => setState(() => _split = m),
            ),
      ]),
      if (_split != SplitMethod.none) ...[
        if (floors.length > 1) ...[
          gap12,
          Text(t.floorsThatShare, style: Theme.of(context).textTheme.labelLarge),
          gap8,
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final f in floors)
              FilterChip(
                label: Text(t.floorLabel(f)),
                selected: !_excludedFloors.contains(f),
                onSelected: (on) => setState(() => on ? _excludedFloors.remove(f) : _excludedFloors.add(f)),
              ),
          ]),
        ],
        gap12,
        Panel(
          padding: EdgeInsets.zero,
          child: shares.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(amount <= 0 ? t.enterAmountToSplit : t.noFlatsToSplit,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(t.splitSummary(shares.length, money(ref, context, amount)),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  for (final f in previewFloors) ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 2),
                      child: Text(t.floorLabel(f),
                          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                    for (final sh in grouped[f]!)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(children: [
                          Expanded(child: Text(byId[sh.unitId]?.name ?? '')),
                          Text(money(ref, context, sh.amount),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ],
                  gap8,
                ]),
        ),
        const SizedBox(height: 4),
        Text(t.splitSavedHint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ],
    ]);
  }
}
