import 'package:flutter_test/flutter_test.dart';
import 'package:homemanagement/data/maintenance_invoice.dart';
import 'package:homemanagement/data/models.dart';
import 'package:homemanagement/l10n/strings.dart';

void main() {
  final expense = Expense(
      propertyId: 'p', category: ExpenseCategory.elevator, amount: 1500, date: DateTime(2026, 10, 3),
      payToUid: 'u1', payToName: 'Mahmoud Essam', payToUnitId: 'flat3');

  test('maintenance invoice carries requester, category, total and date', () {
    final inv = buildMaintenanceInvoice(
        t: const L10n(false), expense: expense, expenseId: 'e1', title: 'Door motor', number: 'INV-0007');
    expect(inv.id, 'maint_e1');
    expect(inv.isMaintenance, isTrue);
    expect(inv.unitId, 'flat3');
    expect(inv.requestedByName, 'Mahmoud Essam');
    expect(inv.category, ExpenseCategory.elevator);
    expect(inv.workDate, DateTime(2026, 10, 3));
    expect(inv.total, 1500);
    expect(inv.status, InvoiceStatus.paid);
    // Round-trips through Firestore data.
    final back = Invoice.fromMap(inv.id, inv.toMap());
    expect(back.requestedByName, 'Mahmoud Essam');
    expect(back.category, ExpenseCategory.elevator);
    expect(back.workDate, DateTime(2026, 10, 3));
  });

  test('editing the expense keeps the invoice number', () {
    final first = buildMaintenanceInvoice(
        t: const L10n(false), expense: expense, expenseId: 'e1', title: '', number: 'INV-0007');
    final again = buildMaintenanceInvoice(
        t: const L10n(false), expense: expense, expenseId: 'e1', title: '', number: 'INV-0099', existing: first);
    expect(again.number, 'INV-0007');
  });

  test('missing invoices are found for approved requests, old and new', () {
    final old = Expense(
        id: 'old', propertyId: 'p', category: ExpenseCategory.maintenance, amount: 400, date: DateTime(2026, 9, 1));
    final paid = Expense(
        id: 'new', propertyId: 'p', category: ExpenseCategory.elevator, amount: 900, date: DateTime(2026, 10, 1),
        payToUid: 'u2', payToName: 'Sara', payToUnitId: 'flat2');
    final done = Expense(
        id: 'done', propertyId: 'p', category: ExpenseCategory.water, amount: 100, date: DateTime(2026, 10, 2),
        payToUid: 'u3', payToName: 'Ali', payToUnitId: 'flat4');
    final existing = buildMaintenanceInvoice(
        t: const L10n(false), expense: done, expenseId: 'done', title: '', number: 'INV-0005');
    final missing = missingMaintenanceInvoices(
      t: const L10n(false),
      approvedMaintenance: [
        (expenseId: 'old', title: 'Pump', residentName: 'Omar', unitId: 'flat1'),
        (expenseId: 'new', title: 'Door', residentName: 'Sara', unitId: 'flat2'),
        (expenseId: 'gone', title: 'x', residentName: 'y', unitId: 'z'), // expense deleted
      ],
      expenses: [old, paid, done],
      invoices: [existing],
      prefix: 'INV-',
      nextNumber: 6,
    );
    expect(missing.map((i) => i.expenseId), ['old', 'new']);
    expect(missing.map((i) => i.number), ['INV-0006', 'INV-0007']);
    // Older request: requester and flat come from the request.
    expect(missing.first.requestedByName, 'Omar');
    expect(missing.first.unitId, 'flat1');
    expect(missing.first.total, 400);
  });
}
