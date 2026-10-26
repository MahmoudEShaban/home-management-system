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
}) {
  final now = DateTime.now();
  final category = t.expenseCategory(expense.category);
  return Invoice(
    id: maintenanceInvoiceId(expenseId),
    number: existing?.number ?? number,
    tenantId: '',
    unitId: expense.payToUnitId,
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
    notes: t.maintenanceInvoiceNote(expense.payToName),
    kind: 'maintenance',
    expenseId: expenseId,
    requestedByName: expense.payToName,
    category: expense.category,
    workDate: expense.date,
  );
}
