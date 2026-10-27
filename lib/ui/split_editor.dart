import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/dues_logic.dart';
import '../l10n/strings.dart';
import 'common.dart';
import 'properties_screen.dart' show compareFloors;

/// Split method + floor picker + live per-flat preview.
///
/// Stateless: the parent owns [method] and [excludedFloors] and rebuilds on
/// [onChanged].
class SplitEditor extends StatelessWidget {
  const SplitEditor({
    super.key,
    required this.units,
    required this.amount,
    required this.method,
    required this.excludedFloors,
    required this.onChanged,
    required this.formatMoney,
    this.allowNone = true,
    this.withTenant = const {},
  });

  final List<Unit> units;
  final double amount;
  final SplitMethod method;
  final Set<String> excludedFloors;
  final void Function(SplitMethod method, Set<String> excludedFloors) onChanged;
  final String Function(double) formatMoney;
  final bool allowNone;
  final Set<String> withTenant;

  static List<String> floorsOf(List<Unit> units) =>
      units.map((u) => u.floor.trim()).toSet().toList()..sort(compareFloors);

  /// Floors to store with the expense (empty = all).
  static List<String> includedFloors(List<Unit> units, Set<String> excluded) {
    if (excluded.isEmpty) return const [];
    return floorsOf(units).where((f) => !excluded.contains(f)).toList();
  }

  static List<ExpenseShare> compute({
    required List<Unit> units,
    required double amount,
    required SplitMethod method,
    required Set<String> excludedFloors,
    Set<String> withTenant = const {},
  }) {
    final included = includedFloors(units, excludedFloors);
    if (excludedFloors.isNotEmpty && included.isEmpty) return const [];
    return splitExpense(
      amount: amount,
      units: units,
      method: method,
      floors: included,
      withTenant: withTenant,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final floors = floorsOf(units);
    final shares = compute(
        units: units, amount: amount, method: method, excludedFloors: excludedFloors, withTenant: withTenant);
    final byId = {for (final u in units) u.id: u};
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
          if ((m != SplitMethod.none || allowNone) && (m != SplitMethod.area || hasAreas || method == SplitMethod.area))
            ChoiceChip(
              label: Text(t.splitMethod(m)),
              selected: method == m,
              onSelected: (_) => onChanged(m, excludedFloors),
            ),
      ]),
      if (method != SplitMethod.none) ...[
        if (floors.length > 1) ...[
          gap12,
          Text(t.floorsThatShare, style: Theme.of(context).textTheme.labelLarge),
          gap8,
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final f in floors)
              FilterChip(
                label: Text(t.floorLabel(f)),
                selected: !excludedFloors.contains(f),
                onSelected: (on) {
                  final next = {...excludedFloors};
                  on ? next.remove(f) : next.add(f);
                  onChanged(method, next);
                },
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
                    child: Text(t.splitSummary(shares.length, formatMoney(amount)),
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
                          Text(formatMoney(sh.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ],
                  gap8,
                ]),
        ),
      ],
    ]);
  }
}
