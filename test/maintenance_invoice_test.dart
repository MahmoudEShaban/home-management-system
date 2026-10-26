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
}
