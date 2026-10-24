import 'models.dart';

/// A flat is occupied when it has an active tenant or its status says
/// someone lives there.
bool isUnitOccupied(Unit unit, Set<String> unitIdsWithActiveTenant) =>
    unitIdsWithActiveTenant.contains(unit.id) || unit.status != UnitStatus.closed;

/// Monthly fixed-cost totals for a set of flats.
class FeeSummary {
  final double total;
  final int occupied;
  final int closed;
  const FeeSummary(this.total, this.occupied, this.closed);

  factory FeeSummary.of(Iterable<Unit> units, Set<String> withTenant) {
    var total = 0.0;
    var occ = 0;
    var closed = 0;
    for (final u in units) {
      total += u.monthlyFee;
      if (isUnitOccupied(u, withTenant)) {
        occ++;
      } else {
        closed++;
      }
    }
    return FeeSummary(total, occ, closed);
  }
}

// ─────────────────────────── Expense splitting ───────────────────────────

/// Divides [amount] between the flats of a building.
///
/// Only flats on [floors] take part (empty = all floors). With
/// [SplitMethod.occupied], closed flats are skipped unless [withTenant]
/// contains them. With [SplitMethod.area], shares follow flat area (falls back
/// to equal when no areas are set). Shares are rounded to 2 decimals and the
/// rounding difference goes to the first flat, so they always add up exactly.
List<ExpenseShare> splitExpense({
  required double amount,
  required List<Unit> units,
  required SplitMethod method,
  List<String> floors = const [],
  Set<String> withTenant = const {},
}) {
  if (method == SplitMethod.none || amount <= 0) return const [];
  var included = units.where((u) => floors.isEmpty || floors.contains(u.floor.trim())).toList();
  if (method == SplitMethod.occupied) {
    included = included.where((u) => isUnitOccupied(u, withTenant)).toList();
  }
  if (included.isEmpty) return const [];

  final totalArea = included.fold<double>(0, (s, u) => s + u.area);
  final useArea = method == SplitMethod.area && totalArea > 0;
  double round2(double v) => (v * 100).roundToDouble() / 100;

  final shares = [
    for (final u in included)
      ExpenseShare(u.id, round2(useArea ? amount * u.area / totalArea : amount / included.length)),
  ];
  final diff = round2(amount - shares.fold<double>(0, (s, e) => s + e.amount));
  if (diff != 0) {
    shares[0] = ExpenseShare(shares[0].unitId, round2(shares[0].amount + diff));
  }
  return shares;
}

/// What one flat owes for a month.
class FlatDue {
  final Unit unit;
  final double fixedFee;
  final List<(Expense, double)> expenseShares;
  const FlatDue(this.unit, this.fixedFee, this.expenseShares);

  double get expensesTotal => expenseShares.fold(0.0, (s, e) => s + e.$2);
  double get total => fixedFee + expensesTotal;
}

/// Dues for every flat of [propertyId] in the month of [month]: the flat's
/// fixed monthly cost plus its share of that month's split expenses.
List<FlatDue> monthlyDues({
  required String propertyId,
  required DateTime month,
  required List<Unit> units,
  required List<Expense> expenses,
}) {
  final key = periodKey(month);
  final monthExpenses = expenses
      .where((e) => e.propertyId == propertyId && e.isSplit && periodKey(e.date) == key)
      .toList();
  return [
    for (final u in units.where((u) => u.propertyId == propertyId))
      FlatDue(u, u.monthlyFee, [
        for (final e in monthExpenses)
          if (e.shareFor(u.id) != 0) (e, e.shareFor(u.id)),
      ]),
  ];
}

// ─────────────────────────── Payments & overview ───────────────────────────

/// Payment status of one flat for one month.
enum DueState { paid, claimed, unpaid, nothingDue }

class FlatMonthStatus {
  final FlatDue due;
  final DuesPayment? payment;
  const FlatMonthStatus(this.due, this.payment);

  DueState get state {
    if (due.total <= 0.005) return DueState.nothingDue;
    if (payment == null || payment!.status == DuesPaymentStatus.rejected) return DueState.unpaid;
    if (payment!.isConfirmed && payment!.amount + 0.005 >= due.total) return DueState.paid;
    if (payment!.isConfirmed) return DueState.unpaid; // paid less than owed
    return DueState.claimed;
  }

  double get outstanding {
    final paid = payment?.isConfirmed == true ? payment!.amount : 0.0;
    return due.total - paid > 0.005 ? due.total - paid : 0.0;
  }
}

/// Every flat's status for [month] in [propertyId].
List<FlatMonthStatus> monthStatuses({
  required String propertyId,
  required DateTime month,
  required List<Unit> units,
  required List<Expense> expenses,
  required List<DuesPayment> payments,
}) {
  final key = periodKey(month);
  final byId = {for (final p in payments) p.id: p};
  return [
    for (final d in monthlyDues(propertyId: propertyId, month: month, units: units, expenses: expenses))
      FlatMonthStatus(d, byId[DuesPayment.docId(d.unit.id, key)]),
  ];
}

/// A flat with dues left unpaid from earlier months.
class LateFlat {
  final Unit unit;
  final double outstanding;
  final List<String> periods;
  const LateFlat(this.unit, this.outstanding, this.periods);
}

class Overview {
  final double expenses;
  final double income;
  final double fund;
  final List<LateFlat> late;
  const Overview({required this.expenses, required this.income, required this.fund, required this.late});

  Overview operator +(Overview o) => Overview(
        expenses: expenses + o.expenses,
        income: income + o.income,
        fund: fund + o.fund,
        late: [...late, ...o.late],
      );

  static const zero = Overview(expenses: 0, income: 0, fund: 0, late: []);
}

/// Overview for one building.
///
/// * expenses / income: for the month of [month], or its whole year when
///   [annual]. Income is confirmed dues payments for those months.
/// * fund: opening balance + all confirmed payments − all expenses.
/// * late: flats with unpaid dues in any month before the current one
///   (looking back at most 24 months, from when the building was added).
Overview buildingOverview({
  required Property property,
  required List<Unit> units,
  required List<Expense> expenses,
  required List<DuesPayment> payments,
  required DateTime month,
  required bool annual,
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final pExpenses = expenses.where((e) => e.propertyId == property.id).toList();
  final pPayments = payments.where((p) => p.propertyId == property.id).toList();
  final pUnits = units.where((u) => u.propertyId == property.id).toList();

  bool inRange(String period) =>
      annual ? period.startsWith('${month.year.toString().padLeft(4, '0')}-') : period == periodKey(month);

  final expTotal = pExpenses.where((e) => inRange(periodKey(e.date))).fold<double>(0, (s, e) => s + e.amount);
  final income = pPayments.where((p) => p.isConfirmed && inRange(p.period)).fold<double>(0, (s, p) => s + p.amount);
  final fund = property.fundOpening +
      pPayments.where((p) => p.isConfirmed).fold<double>(0, (s, p) => s + p.amount) -
      pExpenses.fold<double>(0, (s, e) => s + e.amount);

  // Months to check: from the building's creation (max 24 back) to last month.
  final start = DateTime(property.createdAt.year, property.createdAt.month);
  final current = DateTime(now.year, now.month);
  final months = <DateTime>[];
  for (var m = DateTime(current.year, current.month - 1);
      !m.isBefore(start) && months.length < 24;
      m = DateTime(m.year, m.month - 1)) {
    months.add(m);
  }
  final outstanding = <String, double>{};
  final latePeriods = <String, List<String>>{};
  for (final m in months) {
    for (final s in monthStatuses(
        propertyId: property.id, month: m, units: pUnits, expenses: pExpenses, payments: pPayments)) {
      // A payment waiting for confirmation is not late.
      if (s.state == DueState.unpaid) {
        outstanding[s.due.unit.id] = (outstanding[s.due.unit.id] ?? 0) + s.outstanding;
        latePeriods.putIfAbsent(s.due.unit.id, () => []).add(periodKey(m));
      }
    }
  }
  final byId = {for (final u in pUnits) u.id: u};
  final late = [
    for (final e in outstanding.entries)
      if (byId[e.key] != null) LateFlat(byId[e.key]!, e.value, latePeriods[e.key]!),
  ]..sort((a, b) => b.outstanding.compareTo(a.outstanding));

  return Overview(expenses: expTotal, income: income, fund: fund, late: late);
}
