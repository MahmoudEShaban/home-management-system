import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../data/rent_logic.dart';
import '../l10n/strings.dart';
import '../data/community.dart';
import 'common.dart';
import 'community_screens.dart';
import 'dues_screen.dart';

Color unitStatusColor(UnitStatus s) => switch (s) {
      UnitStatus.ownerResident => const Color(0xFF2E7D32),
      UnitStatus.closed => const Color(0xFF6D6D6D),
      UnitStatus.rented => const Color(0xFF1565C0),
    };

IconData unitStatusIcon(UnitStatus s) => switch (s) {
      UnitStatus.ownerResident => Icons.home_outlined,
      UnitStatus.closed => Icons.lock_outline,
      UnitStatus.rented => Icons.key_outlined,
    };

/// Changes a flat's status. If its fee still equals the old status default,
/// the fee follows the new status default.
Unit withStatus(Unit u, UnitStatus s, Property? p) {
  if (p == null || u.monthlyFee != p.defaultFee(u.status)) return u.copyWith(status: s);
  return u.copyWith(status: s, monthlyFee: p.defaultFee(s));
}

/// Floor choices for flats in [p]: ground, 1..N, roof (as configured).
List<String> floorOptions(Property? p) => p?.levels ?? const [];

/// Ground floor first, then ascending, then roof; other text last.
int compareFloors(String a, String b) {
  int? rank(String f) => f.trim() == kRoofFloor ? 100000 : int.tryParse(f.trim());
  final na = rank(a);
  final nb = rank(b);
  if (na != null && nb != null) return na.compareTo(nb);
  if (na != null) return -1;
  if (nb != null) return 1;
  return a.compareTo(b);
}

// ─────────────────────────────── List ───────────────────────────────

class PropertiesScreen extends ConsumerWidget {
  const PropertiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final props = ref.watch(propertiesProvider);
    final units = ref.watch(unitsProvider).value ?? const <Unit>[];

    return Scaffold(
      appBar: AppBar(title: Text(t.properties)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => pushForm(context, const PropertyForm()),
        icon: const Icon(Icons.add),
        label: Text(t.addProperty),
      ),
      body: props.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline, message: '${t.somethingWrong}\n$e'),
        data: (list) => list.isEmpty
            ? EmptyState(icon: Icons.apartment_outlined, message: t.getStarted)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => gap12,
                itemBuilder: (context, i) {
                  final p = list[i];
                  final pUnits = units.where((u) => u.propertyId == p.id);
                  return _PropertyCard(
                    property: p,
                    unitCount: pUnits.length,
                    fees: FeeSummary.of(pUnits, const {}),
                    onTap: () => push(context, PropertyDetailScreen(propertyId: p.id)),
                  );
                },
              ),
      ),
    );
  }
}

class _PropertyCard extends ConsumerWidget {
  const _PropertyCard({
    required this.property,
    required this.unitCount,
    required this.fees,
    required this.onTap,
  });
  final Property property;
  final int unitCount;
  final FeeSummary fees;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final code = (ref.watch(buildingCodesProvider).value ?? const <BuildingCode>[])
        .where((c) => c.propertyId == property.id)
        .firstOrNull;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Panel(
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              property.type == PropertyType.commercial ? Icons.storefront : Icons.apartment,
              color: cs.onPrimaryContainer,
            ),
          ),
          gap16,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(property.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (property.address.isNotEmpty)
                  Text(property.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                Text(
                  [
                    if (property.levels.isNotEmpty) t.structureLabel(property),
                    t.unitsCount(unitCount),
                    t.flatsSummary(fees.occupied, fees.closed),
                  ].join(' · '),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
                if (fees.total > 0)
                  Text('${t.monthlyTotal}: ${money(ref, context, fees.total)}',
                      style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                if (code != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      Icon(Icons.vpn_key_outlined, size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(t.codeLabel(code.code),
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, letterSpacing: 1)),
                    ]),
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ]),
      ),
    );
  }
}

// ─────────────────────────────── Detail ───────────────────────────────

class PropertyDetailScreen extends ConsumerWidget {
  const PropertyDetailScreen({super.key, required this.propertyId});
  final String propertyId;

  Future<void> _addFlats(BuildContext context, Property property, int existing) async {
    final t = context.t;
    final ctrl = TextEditingController(text: '1');
    final count = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.addFlats),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: t.howManyFlats),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(c, (parseNumber(ctrl.text) ?? 0).round()),
            child: Text(t.confirm),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (count == null || count <= 0 || !context.mounted) return;
    await pushForm(
      context,
      FlatsSetupScreen(property: property, count: count.clamp(1, 200), startNumber: existing + 1),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final property = ref.watch(propertyByIdProvider)[propertyId];
    if (property == null) {
      return Scaffold(appBar: AppBar(), body: EmptyState(icon: Icons.apartment, message: t.nothingYet));
    }
    final units = (ref.watch(unitsProvider).value ?? const <Unit>[])
        .where((u) => u.propertyId == propertyId)
        .toList();
    final fees = FeeSummary.of(units, const {});
    final cs = Theme.of(context).colorScheme;

    // Group flats by floor.
    final byFloor = <String, List<Unit>>{};
    for (final u in units) {
      byFloor.putIfAbsent(u.floor.trim(), () => []).add(u);
    }
    final floorKeys = byFloor.keys.toList()..sort(compareFloors);

    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: color)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(property.name),
        actions: [
          IconButton(
            tooltip: t.edit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => pushForm(context, PropertyForm(existing: property)),
          ),
          IconButton(
            tooltip: t.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (units.isNotEmpty) {
                toast(context, t.deletePropertyBlocked);
                return;
              }
              if (await confirmDialog(context, t.deleteConfirm, confirmLabel: t.delete)) {
                ref.read(propertyRepo).delete(property.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addFlats(context, property, units.length),
        icon: const Icon(Icons.add),
        label: Text(t.addFlats),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  StatusChip(label: t.propertyType(property.type), color: cs.primary),
                  const Spacer(),
                  if (property.levels.isNotEmpty)
                    Flexible(
                      child: Text(t.structureLabel(property),
                          textAlign: TextAlign.end,
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ),
                ]),
                if (property.address.isNotEmpty) ...[
                  gap12,
                  Row(children: [
                    Icon(Icons.place_outlined, size: 18, color: cs.onSurfaceVariant),
                    gap8,
                    Expanded(child: Text(property.address)),
                  ]),
                ],
                const Divider(height: 24),
                Row(children: [
                  stat(t.numberOfFlats, '${units.length}'),
                  stat(t.occupied, '${fees.occupied}', color: unitStatusColor(UnitStatus.ownerResident)),
                  stat(t.unitStatus(UnitStatus.closed), '${fees.closed}', color: unitStatusColor(UnitStatus.closed)),
                ]),
                gap12,
                Row(children: [
                  stat(t.monthlyTotal, money(ref, context, fees.total), color: cs.primary),
                  FilledButton.tonalIcon(
                    onPressed: () => push(context, MonthlyDuesScreen(propertyId: property.id)),
                    icon: const Icon(Icons.request_quote_outlined, size: 18),
                    label: Text(t.monthlyDues),
                  ),
                ]),
                if (property.notes.isNotEmpty) ...[
                  gap12,
                  Text(property.notes, style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          gap12,
          ResidentAccessPanel(property: property),
          if (units.isEmpty) ...[
            SectionTitle(t.units),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.noUnits),
                gap12,
                FilledButton.tonalIcon(
                  onPressed: () => _addFlats(context, property, 0),
                  icon: const Icon(Icons.grid_view_outlined),
                  label: Text(t.setUpFlats),
                ),
              ]),
            ),
          ],
          for (final floor in floorKeys) ...[
            SectionTitle(t.floorLabel(floor),
                trailing: Text(t.unitsCount(byFloor[floor]!.length),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final u in byFloor[floor]!) ...[
                  _FlatTile(unit: u, property: property),
                  if (u != byFloor[floor]!.last) const Divider(height: 1, indent: 72),
                ],
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _FlatTile extends ConsumerWidget {
  const _FlatTile({required this.unit, required this.property});
  final Unit unit;
  final Property property;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final color = unitStatusColor(unit.status);
    final members = ref.watch(membersByUnitProvider)[unit.id];
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(unitStatusIcon(unit.status), size: 20, color: color),
      ),
      title: Text(unit.name),
      subtitle: Text([
        if (members != null && members.isNotEmpty) t.residentLabel(memberNames(members)),
        if (unit.monthlyFee > 0) '${money(ref, context, unit.monthlyFee)} ${t.perMonth}',
      ].join(' · ')),
      trailing: PopupMenuButton<UnitStatus>(
        tooltip: t.status,
        initialValue: unit.status,
        onSelected: (s) => ref.read(unitRepo).save(withStatus(unit, s, property)),
        itemBuilder: (_) => [
          for (final s in UnitStatus.values)
            PopupMenuItem(
              value: s,
              child: Row(children: [
                Icon(unitStatusIcon(s), size: 18, color: unitStatusColor(s)),
                gap8,
                Text(t.unitStatus(s)),
              ]),
            ),
        ],
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          StatusChip(label: t.unitStatus(unit.status), color: color),
          Icon(Icons.arrow_drop_down, color: color),
        ]),
      ),
      onTap: () => push(context, UnitDetailScreen(unitId: unit.id)),
    );
  }
}

class UnitDetailScreen extends ConsumerWidget {
  const UnitDetailScreen({super.key, required this.unitId});
  final String unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final unit = ref.watch(unitByIdProvider)[unitId];
    if (unit == null) {
      return Scaffold(appBar: AppBar(), body: EmptyState(icon: Icons.door_front_door, message: t.nothingYet));
    }
    final property = ref.watch(propertyByIdProvider)[unit.propertyId];
    final linked = ref.watch(membersByUnitProvider)[unitId] ?? const <Member>[];
    final month = ref.watch(selectedMonthProvider);
    final due = monthlyDues(
      propertyId: unit.propertyId,
      month: month,
      units: [unit],
      expenses: ref.watch(expensesProvider).value ?? const <Expense>[],
    ).first;
    final cs = Theme.of(context).colorScheme;

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(color: cs.onSurfaceVariant))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text('${unit.name}${property == null ? '' : ' · ${property.name}'}'),
        actions: [
          IconButton(
            tooltip: t.edit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => pushForm(context, UnitForm(propertyId: unit.propertyId, existing: unit)),
          ),
          IconButton(
            tooltip: t.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (linked.isNotEmpty) {
                toast(context, t.deleteUnitBlocked);
                return;
              }
              if (await confirmDialog(context, t.deleteConfirm, confirmLabel: t.delete)) {
                ref.read(unitRepo).delete(unit.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Panel(
            child: Column(children: [
              Row(children: [
                Expanded(child: Text(t.status, style: TextStyle(color: cs.onSurfaceVariant))),
                StatusChip(label: t.unitStatus(unit.status), color: unitStatusColor(unit.status)),
              ]),
              gap8,
              row(t.flatMonthlyFee, money(ref, context, unit.monthlyFee)),
              row(t.floor, t.floorLabel(unit.floor)),
              row(t.type, t.unitType(unit.type)),
              if (unit.area > 0) row(t.area, numText(unit.area)),
              if (unit.notes.isNotEmpty) ...[gap8, Text(unit.notes)],
            ]),
          ),
          gap12,
          SegmentedButton<UnitStatus>(
            showSelectedIcon: false,
            segments: [
              for (final s in UnitStatus.values)
                ButtonSegment(value: s, label: Text(t.unitStatus(s)), icon: Icon(unitStatusIcon(s), size: 18)),
            ],
            selected: {unit.status},
            onSelectionChanged: (s) => ref.read(unitRepo).save(withStatus(unit, s.first, property)),
          ),
          LinkedResidentPanel(unitId: unit.id),
          SectionTitle(t.duesThisMonth,
              trailing: Text(context.fmtMonth(month), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
          Panel(
            child: Column(children: [
              row(t.monthlyFees, money(ref, context, due.fixedFee)),
              for (final (e, share) in due.expenseShares)
                row('${t.expenseCategory(e.category)}${e.vendor.isEmpty ? '' : ' · ${e.vendor}'}',
                    money(ref, context, share)),
              const Divider(height: 16),
              Row(children: [
                Expanded(child: Text(t.totalDue, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(money(ref, context, due.total), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────── Forms ───────────────────────────────

class PropertyForm extends ConsumerStatefulWidget {
  const PropertyForm({super.key, this.existing});
  final Property? existing;

  @override
  ConsumerState<PropertyForm> createState() => _PropertyFormState();
}

class _PropertyFormState extends ConsumerState<PropertyForm> {
  final _form = GlobalKey<FormState>();
  late final Property? _e = widget.existing;
  late final _name = TextEditingController(text: _e?.name);
  late final _address = TextEditingController(text: _e?.address);
  late final _notes = TextEditingController(text: _e?.notes);
  late final _floors = TextEditingController(
      text: (widget.existing?.floors ?? 0) == 0 ? '' : '${widget.existing!.floors}');
  late final _flats = TextEditingController();
  late final _feeOccupied = TextEditingController(text: numText(_e?.feeOccupied ?? 0));
  late final _feeClosed = TextEditingController(text: numText(_e?.feeClosed ?? 0));
  late final _fund = TextEditingController(text: numText(_e?.fundOpening ?? 0));
  late PropertyType _type = _e?.type ?? PropertyType.residential;
  late bool _hasGround = _e?.hasGroundFloor ?? true;
  late bool _hasRoof = _e?.hasRoof ?? false;

  @override
  void dispose() {
    for (final c in [_name, _address, _notes, _floors, _flats, _feeOccupied, _feeClosed, _fund]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final flats = (parseNumber(_flats.text) ?? 0).round();
    final property = Property(
      id: _e?.id ?? '',
      name: _name.text.trim(),
      address: _address.text.trim(),
      type: _type,
      notes: _notes.text.trim(),
      createdAt: _e?.createdAt,
      floors: (parseNumber(_floors.text) ?? 0).round(),
      hasGroundFloor: _hasGround,
      hasRoof: _hasRoof,
      flatCount: _e?.flatCount ?? flats,
      feeOccupied: parseNumber(_feeOccupied.text) ?? 0,
      feeClosed: parseNumber(_feeClosed.text) ?? 0,
      fundOpening: parseNumber(_fund.text) ?? 0,
    );
    final id = ref.read(propertyRepo).save(property);
    if (_e == null && flats > 0) {
      final saved = property.copyWith(id: id);
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FlatsSetupScreen(property: saved, count: flats, startNumber: 1),
      ));
    } else {
      Navigator.pop(context);
    }
  }

  String? _wholeNumber(String? v, {int max = 200}) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final n = parseNumber(s);
    if (n == null || n < 0 || n != n.roundToDouble() || n > max) return '0–$max';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final isNew = _e == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? t.addProperty : t.editProperty),
        actions: [TextButton(onPressed: _save, child: Text(t.save))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              autofocus: isNew,
              decoration: InputDecoration(labelText: t.name),
              validator: requiredValidator(context),
            ),
            gap12,
            TextFormField(controller: _address, decoration: InputDecoration(labelText: t.address)),
            gap16,
            Text(t.type, style: Theme.of(context).textTheme.labelLarge),
            gap8,
            SegmentedButton<PropertyType>(
              segments: [
                for (final v in PropertyType.values)
                  ButtonSegment(value: v, label: Text(t.propertyType(v))),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            SectionTitle(t.buildingStructure),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _floors,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: t.upperFloors),
                  validator: (v) => _wholeNumber(v, max: 200),
                ),
              ),
              if (isNew) ...[
                gap12,
                Expanded(
                  child: TextFormField(
                    controller: _flats,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: t.numberOfFlats),
                    validator: (v) => _wholeNumber(v, max: 200),
                  ),
                ),
              ],
            ]),
            gap8,
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.storefront_outlined),
              title: Text(t.hasGroundFloorLabel),
              subtitle: Text(t.hasGroundFloorHint),
              value: _hasGround,
              onChanged: (v) => setState(() => _hasGround = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.roofing_outlined),
              title: Text(t.hasRoofLabel),
              subtitle: Text(t.hasRoofHint),
              value: _hasRoof,
              onChanged: (v) => setState(() => _hasRoof = v),
            ),
            SectionTitle(t.monthlyFees),
            TextFormField(
              controller: _feeOccupied,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: t.feeOccupiedLabel),
              validator: numberValidator(context, isRequired: false),
            ),
            gap12,
            TextFormField(
              controller: _feeClosed,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: t.feeClosedLabel),
              validator: numberValidator(context, isRequired: false),
            ),
            gap8,
            Text(t.feesHint, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            SectionTitle(t.fundBalance),
            TextFormField(
              controller: _fund,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(labelText: t.fundOpeningLabel, helperText: t.fundOpeningHint, helperMaxLines: 3),
              validator: numberValidator(context, isRequired: false),
            ),
            gap16,
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(labelText: t.notes),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Flats setup ───────────────────────────

class _FlatDraft {
  _FlatDraft({required String name, required this.floor, required this.status, required double fee})
      : name = TextEditingController(text: name),
        fee = TextEditingController(text: numText(fee));
  final TextEditingController name;
  final TextEditingController fee;
  String floor;
  UnitStatus status;

  void dispose() {
    name.dispose();
    fee.dispose();
  }
}

/// Lets the user name each new flat and set its floor, status and fixed
/// monthly cost, then creates them all at once.
class FlatsSetupScreen extends ConsumerStatefulWidget {
  const FlatsSetupScreen({super.key, required this.property, required this.count, this.startNumber = 1});
  final Property property;
  final int count;

  /// Number used for the first default name ("Flat 5" when 4 already exist).
  final int startNumber;

  @override
  ConsumerState<FlatsSetupScreen> createState() => _FlatsSetupScreenState();
}

class _FlatsSetupScreenState extends ConsumerState<FlatsSetupScreen> {
  final _form = GlobalKey<FormState>();
  final List<_FlatDraft> _flats = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_flats.isNotEmpty) return;
    final t = context.t;
    final p = widget.property;
    // Spread flats evenly over every level (ground, 1..N, roof) from the
    // bottom up; any flat can be moved afterwards.
    final levels = p.levels;
    final perLevel = levels.isEmpty ? 0 : (widget.count / levels.length).ceil();
    for (var i = 0; i < widget.count; i++) {
      final floor = levels.isEmpty ? '' : levels[(i ~/ perLevel).clamp(0, levels.length - 1)];
      _flats.add(_FlatDraft(
        name: t.defaultFlatName(widget.startNumber + i),
        floor: floor,
        status: UnitStatus.ownerResident,
        fee: p.defaultFee(UnitStatus.ownerResident),
      ));
    }
  }

  @override
  void dispose() {
    for (final f in _flats) {
      f.dispose();
    }
    super.dispose();
  }

  void _setStatus(_FlatDraft f, UnitStatus s) {
    final p = widget.property;
    // Keep a fee the user typed; otherwise follow the status default.
    if ((parseNumber(f.fee.text) ?? 0) == p.defaultFee(f.status)) {
      f.fee.text = numText(p.defaultFee(s));
    }
    f.status = s;
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final repo = ref.read(unitRepo);
    for (final f in _flats) {
      repo.save(Unit(
        propertyId: widget.property.id,
        name: f.name.text.trim(),
        floor: f.floor,
        type: UnitType.apartment,
        status: f.status,
        monthlyFee: parseNumber(f.fee.text) ?? 0,
      ));
    }
    final messenger = ScaffoldMessenger.of(context);
    final msg = context.t.flatsSaved(_flats.length);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => PropertyDetailScreen(propertyId: widget.property.id)),
    );
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final options = floorOptions(widget.property);
    final total = _flats.fold<double>(0, (s, f) => s + (parseNumber(f.fee.text) ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: Text('${t.setUpFlats} · ${widget.property.name}'),
        actions: [TextButton(onPressed: _save, child: Text(t.save))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            Text(t.flatsSetupHint, style: TextStyle(color: cs.onSurfaceVariant)),
            gap12,
            // Apply one status to every flat at once.
            Row(children: [
              Text(t.applyToAll, style: Theme.of(context).textTheme.labelLarge),
              gap8,
              Expanded(
                child: Wrap(spacing: 6, children: [
                  for (final s in [UnitStatus.ownerResident, UnitStatus.closed])
                    ActionChip(
                      avatar: Icon(unitStatusIcon(s), size: 16, color: unitStatusColor(s)),
                      label: Text(t.unitStatus(s)),
                      onPressed: () => setState(() {
                        for (final f in _flats) {
                          _setStatus(f, s);
                        }
                      }),
                    ),
                ]),
              ),
            ]),
            gap12,
            for (var i = 0; i < _flats.length; i++)
              Padding(
                key: ObjectKey(_flats[i]),
                padding: const EdgeInsets.only(bottom: 12),
                child: _flatCard(context, i, options),
              ),
            Panel(
              child: Row(children: [
                Expanded(child: Text(t.monthlyTotal, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(money(ref, context, total),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
            gap16,
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }

  Widget _flatCard(BuildContext context, int i, List<String> options) {
    final t = context.t;
    final f = _flats[i];
    final cs = Theme.of(context).colorScheme;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: cs.primaryContainer,
            child: Text('${widget.startNumber + i}', style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer)),
          ),
          gap12,
          Expanded(
            child: TextFormField(
              controller: f.name,
              decoration: InputDecoration(labelText: t.flatName, hintText: t.flatNameHint, isDense: true),
              validator: requiredValidator(context),
            ),
          ),
        ]),
        gap12,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: options.isNotEmpty
                ? DropdownButtonFormField<String>(
                    initialValue: options.contains(f.floor) ? f.floor : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t.floor, isDense: true),
                    items: [
                      for (final o in options)
                        DropdownMenuItem(value: o, child: Text(t.floorLabel(o))),
                    ],
                    onChanged: (v) => f.floor = v ?? f.floor,
                  )
                : TextFormField(
                    initialValue: f.floor,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: t.floor, isDense: true),
                    onChanged: (v) => f.floor = v.trim(),
                  ),
          ),
          gap12,
          Expanded(
            child: TextFormField(
              controller: f.fee,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: t.flatMonthlyFee, isDense: true),
              validator: numberValidator(context, isRequired: false),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
        gap12,
        SegmentedButton<UnitStatus>(
          showSelectedIcon: false,
          segments: [
            for (final s in UnitStatus.values)
              ButtonSegment(value: s, label: Text(t.unitStatus(s), style: const TextStyle(fontSize: 12))),
          ],
          selected: {f.status},
          onSelectionChanged: (s) => setState(() => _setStatus(f, s.first)),
        ),
      ]),
    );
  }
}

// ─────────────────────────────── Unit form ───────────────────────────────

class UnitForm extends ConsumerStatefulWidget {
  const UnitForm({super.key, required this.propertyId, this.existing});
  final String propertyId;
  final Unit? existing;

  @override
  ConsumerState<UnitForm> createState() => _UnitFormState();
}

class _UnitFormState extends ConsumerState<UnitForm> {
  final _form = GlobalKey<FormState>();
  late final Unit? _e = widget.existing;
  late final _name = TextEditingController(text: _e?.name);
  late final _floor = TextEditingController(text: _e?.floor);
  late final _area = TextEditingController(text: numText(_e?.area ?? 0));
  late final _notes = TextEditingController(text: _e?.notes);
  late final _fee = TextEditingController(text: numText(_e?.monthlyFee ?? _defaultFee(UnitStatus.ownerResident)));
  late UnitType _type = _e?.type ?? UnitType.apartment;
  late UnitStatus _status = _e?.status ?? UnitStatus.ownerResident;

  Property? get _property => ref.read(propertyByIdProvider)[widget.propertyId];
  double _defaultFee(UnitStatus s) => _property?.defaultFee(s) ?? 0;

  @override
  void dispose() {
    for (final c in [_name, _floor, _area, _notes, _fee]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setStatus(UnitStatus s) {
    if ((parseNumber(_fee.text) ?? 0) == _defaultFee(_status)) {
      _fee.text = numText(_defaultFee(s));
    }
    _status = s;
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    ref.read(unitRepo).save(Unit(
          id: _e?.id ?? '',
          propertyId: widget.propertyId,
          name: _name.text.trim(),
          floor: _floor.text.trim(),
          type: _type,
          area: parseNumber(_area.text) ?? 0,
          defaultRent: _e?.defaultRent ?? 0,
          notes: _notes.text.trim(),
          status: _status,
          monthlyFee: parseNumber(_fee.text) ?? 0,
        ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final options = floorOptions(ref.watch(propertyByIdProvider)[widget.propertyId]);
    return Scaffold(
      appBar: AppBar(
        title: Text(_e == null ? t.addUnit : t.editUnit),
        actions: [TextButton(onPressed: _save, child: Text(t.save))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              autofocus: _e == null,
              decoration: InputDecoration(labelText: t.flatName, hintText: t.flatNameHint),
              validator: requiredValidator(context),
            ),
            gap16,
            Text(t.status, style: Theme.of(context).textTheme.labelLarge),
            gap8,
            SegmentedButton<UnitStatus>(
              showSelectedIcon: false,
              segments: [
                for (final s in UnitStatus.values)
                  ButtonSegment(value: s, label: Text(t.unitStatus(s)), icon: Icon(unitStatusIcon(s), size: 18)),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _setStatus(s.first)),
            ),
            gap16,
            TextFormField(
              controller: _fee,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: t.flatMonthlyFee),
              validator: numberValidator(context, isRequired: false),
            ),
            gap12,
            Row(children: [
              Expanded(
                child: options.isNotEmpty && (options.contains(_floor.text) || _floor.text.isEmpty)
                    ? DropdownButtonFormField<String>(
                        initialValue: options.contains(_floor.text) ? _floor.text : null,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: t.floor),
                        items: [
                          for (final o in options) DropdownMenuItem(value: o, child: Text(t.floorLabel(o))),
                        ],
                        onChanged: (v) => _floor.text = v ?? '',
                      )
                    : TextFormField(controller: _floor, decoration: InputDecoration(labelText: t.floor)),
              ),
              gap12,
              Expanded(
                child: DropdownButtonFormField<UnitType>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: t.type),
                  items: [
                    for (final v in UnitType.values) DropdownMenuItem(value: v, child: Text(t.unitType(v))),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
              ),
            ]),
            gap12,
            TextFormField(
              controller: _area,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: t.area),
              validator: numberValidator(context, isRequired: false),
            ),
            gap12,
            TextFormField(controller: _notes, maxLines: 3, decoration: InputDecoration(labelText: t.notes)),
          ],
        ),
      ),
    );
  }
}
