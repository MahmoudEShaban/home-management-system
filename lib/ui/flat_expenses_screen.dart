import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/community.dart';
import '../data/flat_expenses.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import 'common.dart';

// Private flat expenses: residents of a flat record costs for their own flat.
// Only residents linked to that flat, and the building manager, can see them.

String _residentMoney(WidgetRef ref, BuildContext context, double v) => formatMoney(
    v,
    ref.watch(residentProfileProvider).value?.currency ?? 'EGP',
    Localizations.localeOf(context).languageCode);

String _label(BuildContext context, FlatExpense e) {
  final t = context.t;
  return e.title.isEmpty ? t.expenseCategory(e.category) : '${t.expenseCategory(e.category)} · ${e.title}';
}

// ─────────────────────────── Resident tab ───────────────────────────

class FlatExpensesTab extends ConsumerWidget {
  const FlatExpensesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final month = ref.watch(selectedMonthProvider);
    final async = ref.watch(residentFlatExpensesProvider);
    final all = async.value ?? const <FlatExpense>[];
    final list = all.where((e) => e.date.year == month.year && e.date.month == month.month).toList();
    final monthTotal = list.fold<double>(0, (s, e) => s + e.amount);
    final yearTotal = all.where((e) => e.date.year == month.year).fold<double>(0, (s, e) => s + e.amount);
    String m(double v) => _residentMoney(ref, context, v);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        const MonthSwitcher(),
        FilledButton.tonalIcon(
          onPressed: () => pushForm(context, const FlatExpenseForm()),
          icon: const Icon(Icons.add),
          label: Text(t.addFlatExpense),
        ),
        gap8,
        Row(children: [
          Icon(Icons.lock_outline, size: 14, color: cs.outline),
          const SizedBox(width: 6),
          Expanded(child: Text(t.flatExpensesPrivacy, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
        ]),
        gap12,
        _Totals(monthLabel: context.fmtMonth(month), month: m(monthTotal), yearLabel: '${month.year}', year: m(yearTotal)),
        gap12,
        if (async.isLoading && all.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (async.hasError)
          Text('${t.somethingWrong}: ${async.error}', style: TextStyle(color: cs.error))
        else if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: EmptyState(icon: Icons.home_repair_service_outlined, message: t.noFlatExpenses),
          )
        else
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final e in list)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.tertiaryContainer,
                    child: Icon(expenseIcon(e.category), size: 20, color: cs.onTertiaryContainer),
                  ),
                  title: Text(_label(context, e)),
                  subtitle: Text([
                    context.fmtDate(e.date),
                    if (e.addedByName.isNotEmpty) e.addedByName,
                    if (e.notes.isNotEmpty) e.notes,
                  ].join(' · ')),
                  trailing: Text(m(e.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () => pushForm(context, FlatExpenseForm(existing: e)),
                ),
            ]),
          ),
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.monthLabel, required this.month, required this.yearLabel, required this.year});
  final String monthLabel;
  final String month;
  final String yearLabel;
  final String year;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget cell(String label, String value, {bool strong = false}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            Text(value,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: strong ? cs.primary : null)),
          ]),
        );
    return Panel(
      child: Row(children: [
        cell(monthLabel, month, strong: true),
        cell(yearLabel, year),
      ]),
    );
  }
}

// ─────────────────────────── Add / edit ───────────────────────────

class FlatExpenseForm extends ConsumerStatefulWidget {
  const FlatExpenseForm({super.key, this.existing});
  final FlatExpense? existing;

  @override
  ConsumerState<FlatExpenseForm> createState() => _FlatExpenseFormState();
}

class _FlatExpenseFormState extends ConsumerState<FlatExpenseForm> {
  final _form = GlobalKey<FormState>();
  late ExpenseCategory _category = widget.existing?.category ?? ExpenseCategory.maintenance;
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _amount = TextEditingController(text: numText(widget.existing?.amount ?? 0));
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = context.t;
    if (!_form.currentState!.validate()) return;
    final service = ref.read(flatExpenseServiceProvider);
    final m = ref.read(membershipProvider);
    if (service == null || m == null) return;
    final old = widget.existing;
    final e = FlatExpense(
      id: old?.id ?? '',
      propertyId: m.propertyId,
      unitId: m.unitId,
      category: _category,
      title: _title.text.trim(),
      amount: parseNumber(_amount.text) ?? 0,
      date: _date,
      notes: _notes.text.trim(),
      // Keep who first recorded it.
      addedByUid: old?.addedByUid ?? m.residentUid,
      addedByName: old?.addedByName ?? m.name,
      createdAt: old?.createdAt ?? DateTime.now(),
    );
    setState(() => _busy = true);
    // Like other writes in the app, don't wait for the server: Firestore
    // keeps it locally and syncs when online.
    service.save(e).catchError((Object err) {
      debugPrint('Flat expense save failed: $err');
    });
    if (!mounted) return;
    toast(context, t.flatExpenseSaved);
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final t = context.t;
    final e = widget.existing;
    final service = ref.read(flatExpenseServiceProvider);
    if (e == null || service == null) return;
    if (!await confirmDialog(context, t.deleteConfirm, confirmLabel: t.delete)) return;
    service.delete(e.id).catchError((Object err) {
      debugPrint('Flat expense delete failed: $err');
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? t.editFlatExpense : t.addFlatExpense),
        actions: [
          if (editing) IconButton(tooltip: t.delete, icon: const Icon(Icons.delete_outline), onPressed: _delete),
          TextButton(onPressed: _busy ? null : _save, child: Text(t.save)),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Row(children: [
              Icon(Icons.lock_outline, size: 14, color: cs.outline),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(t.flatExpensesPrivacy, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
            ]),
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
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: t.flatExpenseTitle, hintText: t.flatExpenseTitleHint),
            ),
            gap12,
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: t.amount),
                  validator: numberValidator(context),
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
            TextFormField(
              controller: _notes,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(labelText: t.notes),
            ),
            if (editing && widget.existing!.addedByName.isNotEmpty) ...[
              gap16,
              Text(t.addedByLine(widget.existing!.addedByName),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Manager: flat page ───────────────────────────

/// Read-only list of a flat's private expenses for the building manager.
class FlatExpensesPanel extends ConsumerWidget {
  const FlatExpensesPanel({super.key, required this.unitId});
  final String unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final month = ref.watch(selectedMonthProvider);
    final all = (ref.watch(managerFlatExpensesProvider).value ?? const <FlatExpense>[])
        .where((e) => e.unitId == unitId)
        .toList();
    final list = all.where((e) => e.date.year == month.year && e.date.month == month.month).toList();
    final monthTotal = list.fold<double>(0, (s, e) => s + e.amount);
    final yearTotal = all.where((e) => e.date.year == month.year).fold<double>(0, (s, e) => s + e.amount);
    String m(double v) => money(ref, context, v);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(t.flatExpenses,
          trailing: Text(context.fmtMonth(month), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
      Text(t.flatExpensesManagerHint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      gap8,
      _Totals(monthLabel: context.fmtMonth(month), month: m(monthTotal), yearLabel: '${month.year}', year: m(yearTotal)),
      if (list.isNotEmpty) ...[
        gap8,
        Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final e in list)
              ListTile(
                dense: true,
                leading: Icon(expenseIcon(e.category), color: cs.tertiary),
                title: Text(_label(context, e)),
                subtitle: Text([
                  context.fmtDate(e.date),
                  if (e.addedByName.isNotEmpty) e.addedByName,
                  if (e.notes.isNotEmpty) e.notes,
                ].join(' · ')),
                trailing: Text(m(e.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ],
    ]);
  }
}
