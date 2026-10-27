// The invoice created automatically when a resident's maintenance request is
// approved: one line with the request's total cost, addressed to the flat of
// the resident who submitted it (and paid for the work).

import '../l10n/strings.dart';
import 'models.dart';

/// Fixed id so re-saving the expense updates the same invoice.
String maintenanceInvoiceId(String expenseId) => 'maint_$expenseId';

Invoice buildMaintenanceInvoice({
  required L10n t,
  required Expense expense,
  required String expenseId,
  required String title,
  required String number,
  Invoice? existing,
  // For requests approved before expenses recorded who paid: taken from the
  // request itself.
  String? requesterName,
  String? requesterUnitId,
}) {
  final now = DateTime.now();
  final category = t.expenseCategory(expense.category);
  final name = expense.payToName.isNotEmpty ? expense.payToName : (requesterName ?? '');
  final unitId = expense.payToUnitId.isNotEmpty ? expense.payToUnitId : (requesterUnitId ?? expense.unitId);
  return Invoice(
    id: maintenanceInvoiceId(expenseId),
    number: existing?.number ?? number,
    tenantId: '',
    unitId: unitId,
    propertyId: expense.propertyId,
    period: periodKey(expense.date),
    issueDate: existing?.issueDate ?? now,
    dueDate: existing?.dueDate ?? now,
    items: [
      InvoiceItem(title.isEmpty ? category : '$category — $title', expense.amount, kind: 'maintenance'),
    ],
    // The requester already paid for the work; other flats repay their
    // shares to them separately.
    status: existing?.status ?? InvoiceStatus.paid,
    notes: expense.paidByResident ? t.maintenanceInvoiceNote(name) : t.maintenanceInvoiceFundNote(name),
    kind: 'maintenance',
    expenseId: expenseId,
    requestedByName: name,
    category: expense.category,
    workDate: expense.date,
  );
}

/// Invoices still missing for approved maintenance requests (e.g. approved
/// before automatic invoices existed). Numbers continue from [invoices].
List<Invoice> missingMaintenanceInvoices({
  required L10n t,
  required List<ExpenseProposalLike> approvedMaintenance,
  required List<Expense> expenses,
  required List<Invoice> invoices,
  required String prefix,
  required int nextNumber,
}) {
  final have = {for (final i in invoices) i.id};
  final haveExpense = {for (final i in invoices) if (i.expenseId.isNotEmpty) i.expenseId};
  final byId = {for (final e in expenses) e.id: e};
  final seen = <String>{};
  var n = nextNumber;
  final out = <Invoice>[];
  void add(Expense e, String title, String name, String unitId) {
    if (!seen.add(e.id) || have.contains(maintenanceInvoiceId(e.id)) || haveExpense.contains(e.id)) return;
    out.add(buildMaintenanceInvoice(
      t: t,
      expense: e,
      expenseId: e.id,
      title: title,
      number: '$prefix${(n++).toString().padLeft(4, '0')}',
      requesterName: name,
      requesterUnitId: unitId,
    ));
  }

  for (final p in approvedMaintenance) {
    final e = byId[p.expenseId];
    if (e != null) add(e, p.title, p.residentName, p.unitId);
  }
  // Resident-paid maintenance whose request record is gone.
  for (final e in expenses.where((e) => e.paidByResident)) {
    add(e, e.notes.split('\n').first.trim(), e.payToName, e.payToUnitId);
  }
  return out;
}

/// What [missingMaintenanceInvoices] needs from an approved request.
typedef ExpenseProposalLike = ({String expenseId, String title, String residentName, String unitId});
