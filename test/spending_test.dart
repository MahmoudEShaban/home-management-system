import 'package:flutter_test/flutter_test.dart';
import 'package:homemanagement/data/flat_expenses.dart';
import 'package:homemanagement/data/models.dart';
import 'package:homemanagement/data/share_payments.dart';
import 'package:homemanagement/l10n/strings.dart';
import 'package:homemanagement/ui/spending_screen.dart';

void main() {
  test('flat spending adds dues, shares, net repairs and private expenses', () {
    final now = DateTime(2026, 9, 10);
    final repair = Expense(
        id: 'r', propertyId: 'p', category: ExpenseCategory.maintenance, amount: 500, date: now,
        split: SplitMethod.equal, payToUid: 'me', payToName: 'Me', payToUnitId: 'a');
    final items = flatSpending(
      t: const L10n(false),
      unitId: 'a',
      dues: [
        DuesPayment(propertyId: 'p', unitId: 'a', period: '2026-09', amount: 300, status: DuesPaymentStatus.confirmed, paidAt: now),
        DuesPayment(propertyId: 'p', unitId: 'a', period: '2026-10', amount: 100, paidAt: now), // claimed
        DuesPayment(propertyId: 'p', unitId: 'b', period: '2026-09', amount: 999, status: DuesPaymentStatus.confirmed, paidAt: now),
      ],
      shares: [
        SharePayment(expenseId: 'x', propertyId: 'p', unitId: 'a', amount: 50, status: DuesPaymentStatus.confirmed,
            paidByUid: 'me', payeeUid: 'other', paidAt: now),
        for (final u in ['b', 'c'])
          SharePayment(expenseId: 'r', propertyId: 'p', unitId: u, amount: 100, status: DuesPaymentStatus.confirmed,
              paidByUid: u, payeeUid: 'me', paidAt: now),
      ],
      flatExpenses: [
        FlatExpense(propertyId: 'p', unitId: 'a', amount: 80, date: now, addedByUid: 'me', createdAt: now),
      ],
      expenses: [repair],
      periodLabel: (p) => p,
    );
    final counted = items.where((i) => !i.pending).fold<double>(0, (s, i) => s + i.amount);
    expect(counted, 300 + 50 + (500 - 200) + 80);
    expect(items.where((i) => i.pending).single.amount, 100);
  });
}
