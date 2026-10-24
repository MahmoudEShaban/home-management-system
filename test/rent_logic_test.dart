import 'package:flutter_test/flutter_test.dart';
import 'package:homemanagement/data/models.dart';
import 'package:homemanagement/data/rent_logic.dart';

void main() {
  test('models round-trip through maps', () {
    final inv = Invoice(
      number: 'INV-0001',
      tenantId: 't',
      unitId: 'u',
      propertyId: 'p',
      period: '2026-10',
      issueDate: DateTime(2026, 10, 1),
      dueDate: DateTime(2026, 10, 5),
      items: const [InvoiceItem('Rent', 1000, kind: 'rent'), InvoiceItem('Water', 75.5)],
    );
    final back = Invoice.fromMap('x', inv.toMap());
    expect(back.total, 1075.5);
    expect(back.items.first.isRent, isTrue);
    expect(back.dueDate, DateTime(2026, 10, 5));
    expect(periodKey(DateTime(2026, 3, 31)), '2026-03');
  });

  test('owner-resident flats count as occupied and fees are totalled', () {
    final units = [
      Unit(id: 'a', propertyId: 'p', name: 'A', status: UnitStatus.ownerResident, monthlyFee: 300),
      Unit(id: 'b', propertyId: 'p', name: 'B', status: UnitStatus.closed, monthlyFee: 150),
      Unit(id: 'c', propertyId: 'p', name: 'C', status: UnitStatus.closed, monthlyFee: 150),
    ];
    final f = FeeSummary.of(units, {'c'}); // C has an active tenant
    expect(f.total, 600);
    expect(f.occupied, 2);
    expect(f.closed, 1);
  });

  test('property default fee follows status and round-trips', () {
    final p = Property(name: 'B', floors: 5, flatCount: 10, feeOccupied: 300, feeClosed: 150);
    expect(p.defaultFee(UnitStatus.ownerResident), 300);
    expect(p.defaultFee(UnitStatus.closed), 150);
    final back = Property.fromMap('x', p.toMap());
    expect(back.floors, 5);
    expect(back.feeClosed, 150);
    final u = Unit.fromMap('u', Unit(propertyId: 'x', name: "Mr. Mahmoud Essam's Flat", floor: '3', status: UnitStatus.closed, monthlyFee: 150).toMap());
    expect(u.status, UnitStatus.closed);
    expect(u.floorNumber, 3);
  });

  test('building levels include ground and roof when enabled', () {
    expect(Property(name: 'A', floors: 3).levels, ['0', '1', '2', '3']);
    expect(Property(name: 'B', floors: 2, hasGroundFloor: false, hasRoof: true).levels, ['1', '2', 'roof']);
    final back = Property.fromMap('x', Property(name: 'C', floors: 1, hasRoof: true).toMap());
    expect(back.hasRoof, isTrue);
    expect(back.hasGroundFloor, isTrue);
  });

  group('expense splitting', () {
    final units = [
      Unit(id: 'g', propertyId: 'p', name: 'G', floor: '0', status: UnitStatus.ownerResident, area: 100),
      Unit(id: 'a', propertyId: 'p', name: 'A', floor: '1', status: UnitStatus.ownerResident, area: 150),
      Unit(id: 'b', propertyId: 'p', name: 'B', floor: '1', status: UnitStatus.closed, area: 150),
      Unit(id: 'r', propertyId: 'p', name: 'R', floor: 'roof', status: UnitStatus.closed, area: 100),
    ];
    double sum(List<ExpenseShare> s) => s.fold(0.0, (a, e) => a + e.amount);

    test('equal split adds up exactly with rounding', () {
      final s = splitExpense(amount: 1000, units: units.take(3).toList(), method: SplitMethod.equal);
      expect(s.length, 3);
      expect(s.map((e) => e.amount), [333.34, 333.33, 333.33]);
      expect(sum(s), closeTo(1000, 1e-9));
    });

    test('floors filter and occupied-only', () {
      final s = splitExpense(amount: 600, units: units, method: SplitMethod.equal, floors: ['1', 'roof']);
      expect(s.map((e) => e.unitId), ['a', 'b', 'r']);
      final occ = splitExpense(amount: 600, units: units, method: SplitMethod.occupied, withTenant: {'r'});
      expect(occ.map((e) => e.unitId), ['g', 'a', 'r']);
      expect(occ.first.amount, 200);
    });

    test('area split is proportional', () {
      final s = splitExpense(amount: 500, units: units, method: SplitMethod.area);
      expect(s.map((e) => e.amount), [100, 150, 150, 100]);
    });

    test('monthly dues combine fixed fee and shares for the month only', () {
      final flats = [
        Unit(id: 'a', propertyId: 'p', name: 'A', monthlyFee: 300),
        Unit(id: 'b', propertyId: 'p', name: 'B', monthlyFee: 150),
      ];
      Expense exp(DateTime d, double amt) => Expense(
            propertyId: 'p', category: ExpenseCategory.elevator, amount: amt, date: d,
            split: SplitMethod.equal,
            shares: splitExpense(amount: amt, units: flats, method: SplitMethod.equal));
      final dues = monthlyDues(
        propertyId: 'p',
        month: DateTime(2026, 10),
        units: flats,
        expenses: [exp(DateTime(2026, 10, 5), 400), exp(DateTime(2026, 9, 5), 1000)],
      );
      expect(dues.map((d) => d.total), [500, 350]);
      final back = Expense.fromMap('x', exp(DateTime(2026, 10, 5), 400).toMap());
      expect(back.shareFor('b'), 200);
      expect(back.isSplit, isTrue);
    });
  });

  group('overview', () {
    final p = Property(id: 'p', name: 'B', createdAt: DateTime(2026, 8, 1), fundOpening: 1000);
    final units = [
      Unit(id: 'a', propertyId: 'p', name: 'A', monthlyFee: 300),
      Unit(id: 'b', propertyId: 'p', name: 'B', monthlyFee: 300),
    ];
    final expenses = [
      Expense(propertyId: 'p', category: ExpenseCategory.elevator, amount: 200, date: DateTime(2026, 9, 10),
          split: SplitMethod.equal,
          shares: splitExpense(amount: 200, units: units, method: SplitMethod.equal)),
    ];
    final payments = [
      DuesPayment(propertyId: 'p', unitId: 'a', period: '2026-08', amount: 300, status: DuesPaymentStatus.confirmed),
      DuesPayment(propertyId: 'p', unitId: 'a', period: '2026-09', amount: 400, status: DuesPaymentStatus.confirmed),
      DuesPayment(propertyId: 'p', unitId: 'b', period: '2026-09', amount: 400, status: DuesPaymentStatus.claimed),
    ];

    test('late flats, income and fund', () {
      final o = buildingOverview(
          property: p, units: units, expenses: expenses, payments: payments,
          month: DateTime(2026, 9), annual: false, today: DateTime(2026, 10, 20));
      expect(o.expenses, 200);
      expect(o.income, 400); // b's September payment is not confirmed yet
      expect(o.fund, 1000 + 700 - 200);
      // b never paid August; September is waiting for confirmation, not late.
      expect(o.late.map((l) => l.unit.id), ['b']);
      expect(o.late.single.outstanding, 300);
      expect(o.late.single.periods, ['2026-08']);
    });

    test('annual totals cover the whole year', () {
      final o = buildingOverview(
          property: p, units: units, expenses: expenses, payments: payments,
          month: DateTime(2026, 3), annual: true, today: DateTime(2026, 10, 20));
      expect(o.income, 700);
      expect(o.expenses, 200);
    });

    test('month status', () {
      final st = monthStatuses(propertyId: 'p', month: DateTime(2026, 9), units: units, expenses: expenses, payments: payments);
      expect(st.map((s) => s.state), [DueState.paid, DueState.claimed]);
    });
  });
}
