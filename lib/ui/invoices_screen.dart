import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import 'common.dart';
import '../data/community.dart';
import 'invoice_pdf.dart';
import 'properties_screen.dart' show compareFloors;

// ─────────────────────────────── List ───────────────────────────────

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  InvoiceStatus? _status; // null = all

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final invoices = ref.watch(invoicesProvider);
    final unitById = ref.watch(unitByIdProvider);
    final propById = ref.watch(propertyByIdProvider);
    final memberByUnit = ref.watch(memberByUnitProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.invoices)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => pushForm(context, const InvoiceForm()),
        icon: const Icon(Icons.add),
        label: Text(t.newInvoice),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<InvoiceStatus?>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: null, label: Text(t.all)),
              ButtonSegment(value: InvoiceStatus.unpaid, label: Text(t.unpaid)),
              ButtonSegment(value: InvoiceStatus.paid, label: Text(t.paid)),
            ],
            selected: {_status},
            onSelectionChanged: (s) => setState(() => _status = s.first),
          ),
        ),
        Expanded(
          child: invoices.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyState(icon: Icons.error_outline, message: '$e'),
            data: (all) {
              final list = all.where((i) => _status == null || i.status == _status).toList();
              if (list.isEmpty) {
                return EmptyState(icon: Icons.receipt_long_outlined, message: t.noInvoices);
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final inv = list[i];
                  final overdue = inv.status == InvoiceStatus.unpaid &&
                      inv.dueDate.isBefore(DateTime.now().subtract(const Duration(days: 1)));
                  return ListTile(
                    leading: CircleAvatar(
                      child: Icon(Icons.receipt_long_outlined,
                          color: overdue ? Theme.of(context).colorScheme.error : null),
                    ),
                    title: Text('${inv.number} · ${memberByUnit[inv.unitId]?.name ?? unitById[inv.unitId]?.name ?? ''}'),
                    subtitle: Text([
                      unitById[inv.unitId]?.name,
                      propById[inv.propertyId]?.name,
                      context.fmtDate(inv.issueDate),
                    ].whereType<String>().join(' · ')),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(money(ref, context, inv.total),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        overdue
                            ? StatusChip(label: t.overdue, color: const Color(0xFFC62828))
                            : StatusChip.invoice(context, inv.status),
                      ],
                    ),
                    onTap: () => push(context, InvoiceDetailScreen(invoiceId: inv.id)),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────── Detail ───────────────────────────────

class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});
  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final inv = (ref.watch(invoicesProvider).value ?? const <Invoice>[])
        .where((i) => i.id == invoiceId)
        .firstOrNull;
    if (inv == null) {
      return Scaffold(appBar: AppBar(), body: EmptyState(icon: Icons.receipt_long, message: t.nothingYet));
    }
    final unit = ref.watch(unitByIdProvider)[inv.unitId];
    final billTo = ref.watch(memberByUnitProvider)[inv.unitId]?.name ?? unit?.name ?? '';
    final property = ref.watch(propertyByIdProvider)[inv.propertyId];
    final profile = ref.watch(profileProvider).value ?? const BusinessProfile();
    final arabic = t.ar;

    Future<void> buildAndShare() async {
      final bytes = await buildInvoicePdf(
          invoice: inv, profile: profile, arabic: arabic, unit: unit, property: property, billToName: billTo);
      await Printing.sharePdf(bytes: bytes, filename: '${inv.number}.pdf');
    }

    void markPaid() => ref.read(invoiceRepo).save(inv.withStatus(InvoiceStatus.paid));

    return Scaffold(
      appBar: AppBar(
        title: Text(inv.number),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  pushForm(context, InvoiceForm(existing: inv));
                case 'unpaid':
                  ref.read(invoiceRepo).save(inv.withStatus(InvoiceStatus.unpaid));
                case 'cancel':
                  ref.read(invoiceRepo).save(inv.withStatus(InvoiceStatus.cancelled));
                case 'delete':
                  if (await confirmDialog(context, t.deleteConfirm, confirmLabel: t.delete)) {
                    ref.read(invoiceRepo).delete(inv.id);
                    if (context.mounted) Navigator.pop(context);
                  }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(t.edit)),
              if (inv.status != InvoiceStatus.unpaid)
                PopupMenuItem(value: 'unpaid', child: Text(t.markUnpaid)),
              if (inv.status != InvoiceStatus.cancelled)
                PopupMenuItem(value: 'cancel', child: Text(t.cancelInvoice)),
              PopupMenuItem(value: 'delete', child: Text(t.delete)),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(billTo,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  StatusChip.invoice(context, inv.status),
                ]),
                Text([unit?.name, property?.name].whereType<String>().join(' · ')),
                const Divider(height: 24),
                _kv(context, t.issueDate, context.fmtDate(inv.issueDate)),
                _kv(context, t.dueDate, context.fmtDate(inv.dueDate)),
                if (inv.period.isNotEmpty) _kv(context, t.forMonth, context.fmtPeriod(inv.period)),
                const Divider(height: 24),
                for (final item in inv.items)
                  _kv(context, item.description, money(ref, context, item.amount)),
                const Divider(height: 24),
                Row(children: [
                  Expanded(child: Text(t.total, style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text(money(ref, context, inv.total),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ]),
                if (inv.notes.isNotEmpty) ...[const Divider(height: 24), Text(inv.notes)],
              ],
            ),
          ),
          gap16,
          Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => push(
                  context,
                  PdfPreviewScreen(
                    title: inv.number,
                    generate: () => buildInvoicePdf(
                        invoice: inv,
                        profile: profile,
                        arabic: arabic,
                        billToName: billTo,
                        unit: unit,
                        property: property),
                  ),
                ),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(t.preview),
              ),
            ),
            gap12,
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: buildAndShare,
                icon: const Icon(Icons.share_outlined),
                label: Text(t.share),
              ),
            ),
          ]),
          if (inv.status == InvoiceStatus.unpaid) ...[
            gap12,
            FilledButton.icon(
              onPressed: markPaid,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.check),
              label: Text(t.markPaid),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w500)),
        ]),
      );
}

class PdfPreviewScreen extends StatelessWidget {
  const PdfPreviewScreen({super.key, required this.title, required this.generate});
  final String title;
  final Future<Uint8List> Function() generate;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: PdfPreview(
          build: (_) => generate(),
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          pdfFileName: '$title.pdf',
        ),
      );
}

// ─────────────────────────────── Form ───────────────────────────────

class _ItemRow {
  _ItemRow(String description, double amount, {this.kind = 'other'})
      : description = TextEditingController(text: description),
        amount = TextEditingController(text: numText(amount));
  final TextEditingController description;
  final TextEditingController amount;
  final String kind;

  void dispose() {
    description.dispose();
    amount.dispose();
  }
}

/// Invoice for one flat: its fixed monthly cost plus its share of the
/// month's expenses, filled in automatically and editable.
class InvoiceForm extends ConsumerStatefulWidget {
  const InvoiceForm({super.key, this.existing, this.presetUnitId});
  final Invoice? existing;
  final String? presetUnitId;

  @override
  ConsumerState<InvoiceForm> createState() => _InvoiceFormState();
}

class _InvoiceFormState extends ConsumerState<InvoiceForm> {
  final _form = GlobalKey<FormState>();
  late final Invoice? _e = widget.existing;
  late final _notes = TextEditingController(text: _e?.notes);
  late String? _unitId = _e?.unitId ?? widget.presetUnitId;
  late DateTime _month = _initialMonth();
  late DateTime _issue = _e?.issueDate ?? DateTime.now();
  late DateTime _due = _e?.dueDate ?? DateTime.now().add(const Duration(days: 7));
  final List<_ItemRow> _items = [];
  bool _seeded = false;

  DateTime _initialMonth() {
    final e = widget.existing;
    if (e == null) return ref.read(selectedMonthProvider);
    return periodStart(e.period.isEmpty ? periodKey(e.issueDate) : e.period);
  }

  @override
  void initState() {
    super.initState();
    final e = _e;
    if (e != null) {
      _items.addAll(e.items.map((i) => _ItemRow(i.description, i.amount, kind: i.kind)));
      _seeded = true;
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  /// Controllers may still be attached to fields until the next frame.
  void _disposeLater(List<_ItemRow> rows) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in rows) {
        r.dispose();
      }
    });
  }

  /// Fills the flat's fixed monthly cost and its expense shares for the month.
  void _autofill() {
    final t = context.t;
    final unit = ref.read(unitByIdProvider)[_unitId];
    if (unit == null) return;
    _disposeLater(List.of(_items));
    _items.clear();
    final monthName = context.fmtMonth(_month);
    if (unit.monthlyFee > 0) {
      _items.add(_ItemRow('${t.monthlyFees} – $monthName', unit.monthlyFee, kind: 'fee'));
    }
    final key = periodKey(_month);
    final expenses = ref.read(expensesProvider).value ?? const <Expense>[];
    for (final e in expenses) {
      if (e.propertyId != unit.propertyId || periodKey(e.date) != key) continue;
      final label = '${t.expenseCategory(e.category)}${e.vendor.isEmpty ? '' : ' (${e.vendor})'} – $monthName';
      if (e.isSplit && e.shareFor(unit.id) > 0) {
        _items.add(_ItemRow(label, e.shareFor(unit.id), kind: 'share'));
      } else if (e.unitId == unit.id) {
        _items.add(_ItemRow(label, e.amount, kind: 'flat'));
      }
    }
    if (_items.isEmpty) _items.add(_ItemRow('', 0));
  }

  void _save() {
    final t = context.t;
    if (!_form.currentState!.validate()) return;
    final unit = ref.read(unitByIdProvider)[_unitId];
    if (unit == null) return;
    final items = _items
        .where((i) => i.description.text.trim().isNotEmpty)
        .map((i) => InvoiceItem(i.description.text.trim(), parseNumber(i.amount.text) ?? 0, kind: i.kind))
        .toList();
    if (items.isEmpty) {
      toast(context, t.atLeastOneItem);
      return;
    }
    final profile = ref.read(profileProvider).value ?? const BusinessProfile();
    final all = ref.read(invoicesProvider).value ?? const <Invoice>[];
    final number = _e?.number ??
        '${profile.invoicePrefix}${ref.read(userDocRepo).nextInvoiceNumber(all).toString().padLeft(4, '0')}';
    final id = ref.read(invoiceRepo).save(Invoice(
          id: _e?.id ?? '',
          number: number,
          tenantId: '',
          unitId: unit.id,
          propertyId: unit.propertyId,
          period: periodKey(_month),
          issueDate: _issue,
          dueDate: _due,
          items: items,
          status: _e?.status ?? InvoiceStatus.unpaid,
          notes: _notes.text.trim(),
        ));
    if (_e == null) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id)));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final propById = ref.watch(propertyByIdProvider);
    final memberByUnit = ref.watch(memberByUnitProvider);
    ref.watch(expensesProvider);
    final units = (ref.watch(unitsProvider).value ?? const <Unit>[]).toList()
      ..sort((a, b) {
        final p = (propById[a.propertyId]?.name ?? '').compareTo(propById[b.propertyId]?.name ?? '');
        if (p != 0) return p;
        final f = compareFloors(a.floor, b.floor);
        return f != 0 ? f : a.name.compareTo(b.name);
      });
    if (!_seeded && _unitId != null && ref.read(unitByIdProvider).containsKey(_unitId)) {
      _seeded = true;
      _autofill();
    }
    final total = _items.fold<double>(0, (s, i) => s + (parseNumber(i.amount.text) ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: Text(_e == null ? t.newInvoice : '${t.edit} ${_e!.number}'),
        actions: [TextButton(onPressed: _save, child: Text(t.save))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (units.isEmpty)
              Text(t.noUnits, style: TextStyle(color: cs.error))
            else
              DropdownButtonFormField<String>(
                initialValue: units.any((u) => u.id == _unitId) ? _unitId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: t.unit),
                items: [
                  for (final u in units)
                    DropdownMenuItem(
                      value: u.id,
                      child: Text(
                        [
                          u.name,
                          if (memberByUnit[u.id] != null) memberByUnit[u.id]!.name,
                          propById[u.propertyId]?.name ?? '',
                        ].join(' · '),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                validator: (v) => v == null ? t.selectUnitForInvoice : null,
                onChanged: (v) => setState(() {
                  _unitId = v;
                  _autofill();
                }),
              ),
            gap12,
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _month,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  initialDatePickerMode: DatePickerMode.year,
                );
                if (picked != null) {
                  setState(() {
                    _month = DateTime(picked.year, picked.month);
                    _autofill();
                  });
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: t.forMonth,
                  suffixIcon: const Icon(Icons.calendar_month_outlined, size: 20),
                ),
                child: Text(context.fmtMonth(_month)),
              ),
            ),
            gap12,
            Row(children: [
              Expanded(
                child: DateField(
                  label: t.issueDate,
                  value: _issue,
                  onChanged: (d) => setState(() => _issue = d ?? _issue),
                ),
              ),
              gap12,
              Expanded(
                child: DateField(
                  label: t.dueDate,
                  value: _due,
                  onChanged: (d) => setState(() => _due = d ?? _due),
                ),
              ),
            ]),
            SectionTitle(
              t.items,
              trailing: TextButton.icon(
                onPressed: () => setState(() => _items.add(_ItemRow('', 0))),
                icon: const Icon(Icons.add, size: 18),
                label: Text(t.addItem),
              ),
            ),
            if (_unitId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(t.invoiceAutofillHint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ),
            for (final item in _items)
              Padding(
                key: ObjectKey(item),
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: item.description,
                      decoration: InputDecoration(labelText: t.description, isDense: true),
                    ),
                  ),
                  gap8,
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: item.amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: t.amount, isDense: true),
                      validator: numberValidator(context),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() {
                      _items.remove(item);
                      _disposeLater([item]);
                    }),
                  ),
                ]),
              ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 48, top: 4),
              child: Row(children: [
                Expanded(child: Text(t.total, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(money(ref, context, total),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
            gap16,
            TextFormField(controller: _notes, maxLines: 3, decoration: InputDecoration(labelText: t.notes)),
          ],
        ),
      ),
    );
  }
}
