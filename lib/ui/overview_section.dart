import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../data/rent_logic.dart';
import '../l10n/strings.dart';
import 'common.dart';

/// Monthly or annual totals in the overview (remembered while the app runs).
final overviewAnnualProvider = StateProvider<bool>((ref) => false);

/// Four boxes: Expenses, Income, Late flats, Fund balance.
///
/// Used on the manager home page (all buildings) and on the resident home
/// page (their building). [showLateNames] lists the late flats; residents only
/// see the count.
class OverviewSection extends ConsumerWidget {
  const OverviewSection({
    super.key,
    required this.properties,
    required this.units,
    required this.expenses,
    required this.payments,
    required this.formatMoney,
    this.showLateNames = true,
    this.onLateTap,
  });

  final List<Property> properties;
  final List<Unit> units;
  final List<Expense> expenses;
  final List<DuesPayment> payments;
  final String Function(double) formatMoney;
  final bool showLateNames;
  final void Function(List<LateFlat> late)? onLateTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final annual = ref.watch(overviewAnnualProvider);
    final month = ref.watch(selectedMonthProvider);
    final o = properties.fold<Overview>(
      Overview.zero,
      (acc, p) =>
          acc +
          buildingOverview(
            property: p,
            units: units,
            expenses: expenses,
            payments: payments,
            month: month,
            annual: annual,
          ),
    );
    final periodLabel = annual ? '${month.year}' : context.fmtMonth(month);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(
        t.overview,
        trailing: SegmentedButton<bool>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            ButtonSegment(value: false, label: Text(t.monthly)),
            ButtonSegment(value: true, label: Text(t.annually)),
          ],
          selected: {annual},
          onSelectionChanged: (v) => ref.read(overviewAnnualProvider.notifier).state = v.first,
        ),
      ),
      Row(children: [
        Expanded(
          child: _Box(
            icon: Icons.trending_down,
            color: const Color(0xFFC62828),
            label: t.expenses,
            number: o.expenses,
            format: formatMoney,
            caption: periodLabel,
          ),
        ),
        gap12,
        Expanded(
          child: _Box(
            icon: Icons.trending_up,
            color: const Color(0xFF2E7D32),
            label: t.income,
            number: o.income,
            format: formatMoney,
            caption: periodLabel,
          ),
        ),
      ]),
      gap12,
      Row(children: [
        Expanded(
          child: _Box(
            icon: Icons.warning_amber_rounded,
            color: o.late.isEmpty ? cs.primary : const Color(0xFFB26A00),
            label: t.lateFlats,
            number: o.late.length.toDouble(),
            format: (v) => '${v.round()}',
            caption: o.late.isEmpty
                ? t.noLateFlats
                : formatMoney(o.late.fold<double>(0, (s, l) => s + l.outstanding)),
            onTap: o.late.isEmpty || onLateTap == null ? null : () => onLateTap!(o.late),
          ),
        ),
        gap12,
        Expanded(
          child: _Box(
            icon: Icons.savings_outlined,
            color: o.fund < 0 ? cs.error : cs.primary,
            label: t.fundBalance,
            number: o.fund,
            format: formatMoney,
            caption: t.fundCaption,
          ),
        ),
      ]),
      if (showLateNames && o.late.isNotEmpty) ...[
        gap12,
        Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final l in o.late.take(5))
              ListTile(
                dense: true,
                leading: const Icon(Icons.door_front_door_outlined, color: Color(0xFFB26A00)),
                title: Text(l.unit.name),
                subtitle: Text(t.lateMonths(l.periods.length)),
                trailing: Text(formatMoney(l.outstanding),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFB26A00))),
                onTap: onLateTap == null ? null : () => onLateTap!(o.late),
              ),
            if (o.late.length > 5)
              TextButton(
                onPressed: onLateTap == null ? null : () => onLateTap!(o.late),
                child: Text(t.viewAllFlats(o.late.length)),
              ),
          ]),
        ),
      ],
    ]);
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.icon,
    required this.color,
    required this.label,
    required this.number,
    required this.format,
    required this.caption,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final String label;
  final double number;
  final String Function(double) format;
  final String caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: color),
            ),
            gap8,
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ),
          ]),
          gap8,
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: AnimatedNumber(
                value: number,
                format: format,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(height: 2),
          Text(caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
        ]),
      ),
    );
  }
}
