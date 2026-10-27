import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup_service.dart';
import '../data/community.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/dues_logic.dart';
import '../l10n/strings.dart';
import 'status_requests_screen.dart' show StatusRequestsBanner;
import 'welcome_header.dart';
import 'chat_screen.dart' show ChatButton;
import 'common.dart';
import 'community_screens.dart';
import 'dues_screen.dart';
import 'inbox_screens.dart';
import 'overview_section.dart';
import 'expenses_screen.dart';
import 'invoices_screen.dart';
import 'properties_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, required this.onNavigate});

  /// Switches the bottom-navigation tab.
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final month = ref.watch(selectedMonthProvider);
    final expenses = ref.watch(expensesProvider).value ?? const <Expense>[];
    final units = ref.watch(unitsProvider).value ?? const <Unit>[];
    final properties = ref.watch(propertiesProvider);
    final backup = ref.watch(backupProvider);
    final profileName = ref.watch(profileProvider).value?.name ?? '';
    String m(double v) => money(ref, context, v);

    // This month across all buildings.
    final dues = [
      for (final p in properties.value ?? const <Property>[])
        ...monthlyDues(propertyId: p.id, month: month, units: units, expenses: expenses),
    ];
    final fixedTotal = dues.fold<double>(0, (s, d) => s + d.fixedFee);
    final sharedTotal = dues.fold<double>(0, (s, d) => s + d.expensesTotal);
    final fees = FeeSummary.of(units, const {});
    final occupancy = units.isEmpty ? 0.0 : fees.occupied / units.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(profileName.isEmpty ? t.appName : profileName),
        actions: [
          const ChatButton(manager: true),
          const InboxBell(),
          if (ref.watch(hasBothRolesProvider))
            IconButton(
              tooltip: t.switchToResident,
              icon: const Icon(Icons.home_outlined),
              onPressed: () => ref.read(activeViewProvider.notifier).set(kRoleResident),
            ),
          IconButton(
            tooltip: t.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => push(context, const SettingsScreen()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const WelcomeHeader(),
          const MonthSwitcher(),
          if (properties.hasValue && properties.value!.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                child: Row(children: [
                  Icon(Icons.lightbulb_outline, color: cs.primary),
                  gap12,
                  Expanded(child: Text(t.getStarted)),
                  TextButton(
                    onPressed: () => pushForm(context, const PropertyForm()),
                    child: Text(t.addProperty),
                  ),
                ]),
              ),
            ),
          const JoinRequestsBanner(),
          const ProposalsBanner(),
          const StatusRequestsBanner(),
          _HeroCard(
            total: fixedTotal + sharedTotal,
            fixed: fixedTotal,
            shared: sharedTotal,
            flats: units.length,
            money: m,
          ),
          const PaymentsToConfirmBanner(),
          OverviewSection(
            properties: properties.value ?? const <Property>[],
            units: units,
            expenses: expenses,
            payments: ref.watch(duesPaymentsProvider).value ?? const <DuesPayment>[],
            formatMoney: m,
            onLateTap: (late) => push(context, LateFlatsScreen(late: late)),
          ),
          gap12,
          _StatTile(
            icon: Icons.door_front_door_outlined,
            label: t.occupancy,
            value: '${(occupancy * 100).round()}%',
            subtitle: t.flatsSummary(fees.occupied, fees.closed),
            progress: occupancy,
            onTap: () => onNavigate(1),
          ),
          _DuesSection(month: month),
          SectionTitle(t.quickActions),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.add_card_outlined, size: 18),
                label: Text(t.addExpense),
                onPressed: () => pushForm(context, const ExpenseForm()),
              ),
              ActionChip(
                avatar: const Icon(Icons.handyman_outlined, size: 18),
                label: Text(t.maintenanceRequest),
                onPressed: () => pushForm(context, const ExpenseForm(presetCategory: ExpenseCategory.maintenance)),
              ),
              ActionChip(
                avatar: const Icon(Icons.price_check, size: 18),
                label: Text(t.confirmPayments),
                onPressed: () => push(context, const PaymentsToConfirmScreen()),
              ),
              ActionChip(
                avatar: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(t.newInvoice),
                onPressed: () => pushForm(context, const InvoiceForm()),
              ),
              ActionChip(
                avatar: const Icon(Icons.campaign_outlined, size: 18),
                label: Text(t.sendMessage),
                onPressed: () => pushForm(context, const ComposeMessageScreen()),
              ),
            ],
          ),
          SectionTitle(t.backups),
          Panel(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(
                backup.lastError != null ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
                color: backup.lastError != null ? cs.error : cs.primary,
              ),
              title: Text(t.lastBackup),
              subtitle: Text(
                  backup.lastError != null
                      ? '${t.backupFailed}: ${backup.lastError}'
                      : backup.lastBackup == null
                          ? (backup.connected ? t.neverBackedUp : t.connectDrive)
                          : context.fmtDate(backup.lastBackup!),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => push(context, const BackupScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

/// This month's dues across all buildings.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.total,
    required this.fixed,
    required this.shared,
    required this.flats,
    required this.money,
  });
  final double total;
  final double fixed;
  final double shared;
  final int flats;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final onHero = cs.onPrimary;
    return Entrance(
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
        boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.duesThisMonth, style: TextStyle(color: onHero.withValues(alpha: 0.8))),
          const SizedBox(height: 4),
          AnimatedNumber(
              value: total,
              format: money,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: onHero, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(t.acrossFlats(flats), style: TextStyle(color: onHero.withValues(alpha: 0.75), fontSize: 12)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _heroFigure(t.monthlyFees, fixed, onHero)),
            Expanded(child: _heroFigure(t.sharedExpenses, shared, onHero)),
          ]),
        ],
      ),
      ),
    );
  }

  Widget _heroFigure(String label, double value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color.withValues(alpha: 0.75), fontSize: 12)),
          AnimatedNumber(
              value: value, format: money, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 16)),
        ],
      );
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.progress,
    this.valueColor,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final double? progress;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              ),
            ]),
            gap8,
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700, color: valueColor)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
            if (progress != null) ...[
              gap8,
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: progress, minHeight: 6),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Home-page summary of what every flat owes for [month], per building.
class _DuesSection extends ConsumerWidget {
  const _DuesSection({required this.month});
  final DateTime month;

  /// Flats shown per building before "View all".
  static const _preview = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final properties = ref.watch(propertiesProvider).value ?? const <Property>[];
    final units = ref.watch(unitsProvider).value ?? const <Unit>[];
    final expenses = ref.watch(expensesProvider).value ?? const <Expense>[];
    String m(double v) => money(ref, context, v);

    final buildings = [
      for (final p in properties)
        (
          p,
          monthlyDues(propertyId: p.id, month: month, units: units, expenses: expenses)
            ..sort((a, b) {
              final f = compareFloors(a.unit.floor, b.unit.floor);
              return f != 0 ? f : a.unit.name.compareTo(b.unit.name);
            }),
        ),
    ].where((b) => b.$2.isNotEmpty).toList();
    if (buildings.isEmpty) return const SizedBox.shrink();

    final grandTotal = buildings.fold<double>(
        0, (s, b) => s + b.$2.fold<double>(0, (s2, d) => s2 + d.total));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(
        t.duesPerFlat,
        trailing: Text(m(grandTotal),
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
      ),
      for (final (property, dues) in buildings) ...[
        Panel(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ListTile(
              leading: Icon(Icons.apartment, color: cs.primary),
              title: Text(property.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(t.unitsCount(dues.length)),
              trailing: Text(m(dues.fold<double>(0, (s, d) => s + d.total)),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              onTap: () => push(context, MonthlyDuesScreen(propertyId: property.id)),
            ),
            const Divider(height: 1),
            for (final d in dues.take(_preview))
              InkWell(
                onTap: () => push(context, MonthlyDuesScreen(propertyId: property.id)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    Icon(unitStatusIcon(d.unit.status), size: 18, color: unitStatusColor(d.unit.status)),
                    gap12,
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d.unit.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          [
                            t.floorLabel(d.unit.floor),
                            if (d.expensesTotal > 0) '${t.sharedExpenses} ${m(d.expensesTotal)}',
                          ].join(' · '),
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                        ),
                      ]),
                    ),
                    Text(m(d.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            if (dues.length > _preview)
              TextButton(
                onPressed: () => push(context, MonthlyDuesScreen(propertyId: property.id)),
                child: Text(t.viewAllFlats(dues.length)),
              )
            else
              gap8,
          ]),
        ),
        gap12,
      ],
    ]);
  }
}
