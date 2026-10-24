// Domain models. Dates are stored in Firestore as millisecondsSinceEpoch (int)
// so every document is plain JSON and backups need no conversion.

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int _i(dynamic v, [int fallback = 0]) =>
    v is num ? v.toInt() : int.tryParse('$v') ?? fallback;
String _s(dynamic v) => v == null ? '' : '$v';
DateTime _dt(dynamic v) =>
    v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : DateTime.now();
DateTime? _dtn(dynamic v) =>
    v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

/// Every stored document has an id and can be serialised.
abstract class Entity {
  String get id;
  Map<String, dynamic> toMap();
}

/// "2026-10" style key for a calendar month.
String periodKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

DateTime periodStart(String key) {
  final parts = key.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]));
}

// ───────────────────────────── Property ─────────────────────────────

enum PropertyType { residential, commercial, mixed }

/// Floor value used for flats on the roof.
const kRoofFloor = 'roof';

class Property implements Entity {
  @override
  final String id;
  final String name;
  final String address;
  final PropertyType type;
  final String notes;
  final DateTime createdAt;

  /// Number of upper floors (Floor 1 … N), not counting ground or roof.
  final int floors;

  /// Building has a ground floor with flats/units on it.
  final bool hasGroundFloor;

  /// Building has a roof level with flats/units on it.
  final bool hasRoof;

  /// Number of flats planned when the building was set up.
  final int flatCount;

  /// Default fixed monthly cost for flats where the owner/occupant lives.
  final double feeOccupied;

  /// Default fixed monthly cost for closed flats.
  final double feeClosed;

  /// Money already in the building's maintenance fund when tracking started.
  final double fundOpening;

  Property({
    this.id = '',
    required this.name,
    this.address = '',
    this.type = PropertyType.residential,
    this.notes = '',
    DateTime? createdAt,
    this.floors = 0,
    this.hasGroundFloor = true,
    this.hasRoof = false,
    this.flatCount = 0,
    this.feeOccupied = 0,
    this.feeClosed = 0,
    this.fundOpening = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Floor values flats can be placed on, bottom to top:
  /// "0" (ground), "1" … "N", "roof".
  List<String> get levels => [
        if (hasGroundFloor) '0',
        for (var i = 1; i <= floors; i++) '$i',
        if (hasRoof) kRoofFloor,
      ];

  Property copyWith({String? id}) => Property(
        id: id ?? this.id,
        name: name,
        address: address,
        type: type,
        notes: notes,
        createdAt: createdAt,
        floors: floors,
        hasGroundFloor: hasGroundFloor,
        hasRoof: hasRoof,
        flatCount: flatCount,
        feeOccupied: feeOccupied,
        feeClosed: feeClosed,
        fundOpening: fundOpening,
      );

  /// Default monthly fee for a flat with [status].
  double defaultFee(UnitStatus status) =>
      status == UnitStatus.closed ? feeClosed : feeOccupied;

  factory Property.fromMap(String id, Map<String, dynamic> m) => Property(
        id: id,
        name: _s(m['name']),
        address: _s(m['address']),
        type: PropertyType.values.asNameMap()[m['type']] ??
            PropertyType.residential,
        notes: _s(m['notes']),
        createdAt: _dt(m['createdAt']),
        floors: _i(m['floors']),
        hasGroundFloor: m['hasGroundFloor'] != false,
        hasRoof: m['hasRoof'] == true,
        flatCount: _i(m['flatCount']),
        feeOccupied: _d(m['feeOccupied']),
        feeClosed: _d(m['feeClosed']),
        fundOpening: _d(m['fundOpening']),
      );

  @override
  Map<String, dynamic> toMap() => {
        'name': name,
        'address': address,
        'type': type.name,
        'notes': notes,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'floors': floors,
        'hasGroundFloor': hasGroundFloor,
        'hasRoof': hasRoof,
        'flatCount': flatCount,
        'feeOccupied': feeOccupied,
        'feeClosed': feeClosed,
        'fundOpening': fundOpening,
      };
}

// ─────────────────────────────── Unit ───────────────────────────────

enum UnitType { apartment, shop, office, warehouse, other }

/// Who is in the flat right now.
enum UnitStatus {
  /// The owner (or their family) lives in the flat.
  ownerResident,

  /// The flat is closed / unoccupied.
  closed,

  /// The flat is let to a tenant.
  rented,
}

class Unit implements Entity {
  @override
  final String id;
  final String propertyId;
  final String name;

  /// Floor as text: "0" is ground floor, "1", "2", …, "roof" is the roof.
  /// Free text is also accepted for older records (e.g. "Basement").
  final String floor;
  final UnitType type;
  final double area;
  final double defaultRent;
  final String notes;
  final UnitStatus status;

  /// Fixed monthly cost for this flat (service / maintenance fee).
  final double monthlyFee;

  Unit({
    this.id = '',
    required this.propertyId,
    required this.name,
    this.floor = '',
    this.type = UnitType.apartment,
    this.area = 0,
    this.defaultRent = 0,
    this.notes = '',
    this.status = UnitStatus.ownerResident,
    this.monthlyFee = 0,
  });

  int? get floorNumber => int.tryParse(floor.trim());

  factory Unit.fromMap(String id, Map<String, dynamic> m) => Unit(
        id: id,
        propertyId: _s(m['propertyId']),
        name: _s(m['name']),
        floor: _s(m['floor']),
        type: UnitType.values.asNameMap()[m['type']] ?? UnitType.apartment,
        area: _d(m['area']),
        defaultRent: _d(m['defaultRent']),
        notes: _s(m['notes']),
        // Records created before statuses existed were vacant or rented.
        status: UnitStatus.values.asNameMap()[m['status']] ?? UnitStatus.closed,
        monthlyFee: _d(m['monthlyFee']),
      );

  @override
  Map<String, dynamic> toMap() => {
        'propertyId': propertyId,
        'name': name,
        'floor': floor,
        'type': type.name,
        'area': area,
        'defaultRent': defaultRent,
        'notes': notes,
        'status': status.name,
        'monthlyFee': monthlyFee,
      };

  Unit copyWith({UnitStatus? status, double? monthlyFee}) => Unit(
        id: id,
        propertyId: propertyId,
        name: name,
        floor: floor,
        type: type,
        area: area,
        defaultRent: defaultRent,
        notes: notes,
        status: status ?? this.status,
        monthlyFee: monthlyFee ?? this.monthlyFee,
      );
}

// ────────────────────────────── Tenant ──────────────────────────────

class Tenant implements Entity {
  @override
  final String id;
  final String name;
  final String phone;
  final String email;
  final String propertyId;
  final String unitId;
  final double rentAmount;

  /// Day of month rent is due (1–28).
  final int dueDay;
  final DateTime leaseStart;
  final DateTime? leaseEnd;
  final double deposit;

  /// 'active' or 'ended'.
  final bool active;
  final String notes;

  Tenant({
    this.id = '',
    required this.name,
    this.phone = '',
    this.email = '',
    required this.propertyId,
    required this.unitId,
    required this.rentAmount,
    this.dueDay = 1,
    required this.leaseStart,
    this.leaseEnd,
    this.deposit = 0,
    this.active = true,
    this.notes = '',
  });

  /// Whether this tenant owes rent for the month starting at [month].
  bool isBillableIn(DateTime month) {
    if (!active) return false;
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1)
        .subtract(const Duration(milliseconds: 1));
    if (leaseStart.isAfter(end)) return false;
    if (leaseEnd != null && leaseEnd!.isBefore(start)) return false;
    return true;
  }

  factory Tenant.fromMap(String id, Map<String, dynamic> m) => Tenant(
        id: id,
        name: _s(m['name']),
        phone: _s(m['phone']),
        email: _s(m['email']),
        propertyId: _s(m['propertyId']),
        unitId: _s(m['unitId']),
        rentAmount: _d(m['rentAmount']),
        dueDay: _i(m['dueDay'], 1).clamp(1, 28),
        leaseStart: _dt(m['leaseStart']),
        leaseEnd: _dtn(m['leaseEnd']),
        deposit: _d(m['deposit']),
        active: m['status'] != 'ended',
        notes: _s(m['notes']),
      );

  @override
  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'email': email,
        'propertyId': propertyId,
        'unitId': unitId,
        'rentAmount': rentAmount,
        'dueDay': dueDay,
        'leaseStart': leaseStart.millisecondsSinceEpoch,
        'leaseEnd': leaseEnd?.millisecondsSinceEpoch,
        'deposit': deposit,
        'status': active ? 'active' : 'ended',
        'notes': notes,
      };

  Tenant copyWith({bool? active, DateTime? leaseEnd}) => Tenant(
        id: id,
        name: name,
        phone: phone,
        email: email,
        propertyId: propertyId,
        unitId: unitId,
        rentAmount: rentAmount,
        dueDay: dueDay,
        leaseStart: leaseStart,
        leaseEnd: leaseEnd ?? this.leaseEnd,
        deposit: deposit,
        active: active ?? this.active,
        notes: notes,
      );
}

// ────────────────────────────── Payment ─────────────────────────────

enum PaymentMethod { cash, bankTransfer, cheque, wallet, other }

class Payment implements Entity {
  @override
  final String id;
  final String tenantId;
  final String unitId;
  final String propertyId;

  /// Month this payment counts toward, e.g. "2026-10".
  final String period;
  final double amount;
  final DateTime date;
  final PaymentMethod method;
  final String notes;

  Payment({
    this.id = '',
    required this.tenantId,
    required this.unitId,
    required this.propertyId,
    required this.period,
    required this.amount,
    required this.date,
    this.method = PaymentMethod.cash,
    this.notes = '',
  });

  factory Payment.fromMap(String id, Map<String, dynamic> m) => Payment(
        id: id,
        tenantId: _s(m['tenantId']),
        unitId: _s(m['unitId']),
        propertyId: _s(m['propertyId']),
        period: _s(m['period']),
        amount: _d(m['amount']),
        date: _dt(m['date']),
        method:
            PaymentMethod.values.asNameMap()[m['method']] ?? PaymentMethod.cash,
        notes: _s(m['notes']),
      );

  @override
  Map<String, dynamic> toMap() => {
        'tenantId': tenantId,
        'unitId': unitId,
        'propertyId': propertyId,
        'period': period,
        'amount': amount,
        'date': date.millisecondsSinceEpoch,
        'method': method.name,
        'notes': notes,
      };
}

// ────────────────────────────── Expense ─────────────────────────────

enum ExpenseCategory {
  electricity,
  water,
  gas,
  internet,
  maintenance,
  cleaning,
  security,
  elevator,
  taxes,
  other,
}

/// How a building-wide expense is divided between flats.
enum SplitMethod {
  /// Not divided (owner/landlord pays it).
  none,

  /// Same amount for every included flat.
  equal,

  /// Same amount for every included flat that is occupied (not closed).
  occupied,

  /// In proportion to each included flat's area.
  area,
}

/// One flat's part of a split expense.
class ExpenseShare {
  final String unitId;
  final double amount;
  const ExpenseShare(this.unitId, this.amount);

  factory ExpenseShare.fromMap(Map<String, dynamic> m) =>
      ExpenseShare(_s(m['unitId']), _d(m['amount']));

  Map<String, dynamic> toMap() => {'unitId': unitId, 'amount': amount};
}

class Expense implements Entity {
  @override
  final String id;
  final String propertyId;

  /// Empty when the expense belongs to the whole building.
  final String unitId;
  final ExpenseCategory category;
  final double amount;
  final DateTime date;
  final String vendor;

  /// Recharge this expense to the unit's tenant on their next invoice.
  final bool billToTenant;
  final String notes;

  /// How the amount was divided between flats (building-wide expenses).
  final SplitMethod split;

  /// Floors that share the cost; empty means every floor.
  final List<String> splitFloors;

  /// Each flat's share, fixed when the expense was saved.
  final List<ExpenseShare> shares;

  /// Set when the expense came from a resident's approved submission.
  final String proposedByName;
  final String proposalId;

  Expense({
    this.id = '',
    required this.propertyId,
    this.unitId = '',
    required this.category,
    required this.amount,
    required this.date,
    this.vendor = '',
    this.billToTenant = false,
    this.notes = '',
    this.split = SplitMethod.none,
    this.splitFloors = const [],
    this.shares = const [],
    this.proposedByName = '',
    this.proposalId = '',
  });

  bool get isSplit => split != SplitMethod.none && shares.isNotEmpty;

  double shareFor(String unitId) =>
      shares.where((s) => s.unitId == unitId).fold(0.0, (a, s) => a + s.amount);

  factory Expense.fromMap(String id, Map<String, dynamic> m) => Expense(
        id: id,
        propertyId: _s(m['propertyId']),
        unitId: _s(m['unitId']),
        category: ExpenseCategory.values.asNameMap()[m['category']] ??
            ExpenseCategory.other,
        amount: _d(m['amount']),
        date: _dt(m['date']),
        vendor: _s(m['vendor']),
        billToTenant: m['billToTenant'] == true,
        notes: _s(m['notes']),
        split: SplitMethod.values.asNameMap()[m['split']] ?? SplitMethod.none,
        splitFloors: (m['splitFloors'] as List? ?? const []).map((e) => '$e').toList(),
        shares: (m['shares'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => ExpenseShare.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        proposedByName: _s(m['proposedByName']),
        proposalId: _s(m['proposalId']),
      );

  @override
  Map<String, dynamic> toMap() => {
        'propertyId': propertyId,
        'unitId': unitId,
        'category': category.name,
        'amount': amount,
        'date': date.millisecondsSinceEpoch,
        'vendor': vendor,
        'billToTenant': billToTenant,
        'notes': notes,
        'split': split.name,
        'splitFloors': splitFloors,
        'shares': shares.map((e) => e.toMap()).toList(),
        if (proposedByName.isNotEmpty) 'proposedByName': proposedByName,
        if (proposalId.isNotEmpty) 'proposalId': proposalId,
      };
}

// ────────────────────────────── Invoice ─────────────────────────────

enum InvoiceStatus { unpaid, paid, cancelled }

class InvoiceItem {
  final String description;
  final double amount;

  /// 'rent', 'utility' or 'other'. Rent items can be recorded as payments.
  final String kind;

  const InvoiceItem(this.description, this.amount, {this.kind = 'other'});

  bool get isRent => kind == 'rent';

  factory InvoiceItem.fromMap(Map<String, dynamic> m) => InvoiceItem(
      _s(m['description']), _d(m['amount']),
      kind: _s(m['kind']).isEmpty ? 'other' : _s(m['kind']));

  Map<String, dynamic> toMap() =>
      {'description': description, 'amount': amount, 'kind': kind};
}

class Invoice implements Entity {
  @override
  final String id;
  final String number;
  final String tenantId;
  final String unitId;
  final String propertyId;
  final String period;
  final DateTime issueDate;
  final DateTime dueDate;
  final List<InvoiceItem> items;
  final InvoiceStatus status;
  final String notes;

  Invoice({
    this.id = '',
    required this.number,
    required this.tenantId,
    required this.unitId,
    required this.propertyId,
    required this.period,
    required this.issueDate,
    required this.dueDate,
    required this.items,
    this.status = InvoiceStatus.unpaid,
    this.notes = '',
  });

  double get total => items.fold(0, (sum, i) => sum + i.amount);

  factory Invoice.fromMap(String id, Map<String, dynamic> m) => Invoice(
        id: id,
        number: _s(m['number']),
        tenantId: _s(m['tenantId']),
        unitId: _s(m['unitId']),
        propertyId: _s(m['propertyId']),
        period: _s(m['period']),
        issueDate: _dt(m['issueDate']),
        dueDate: _dt(m['dueDate']),
        items: (m['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => InvoiceItem.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        status: InvoiceStatus.values.asNameMap()[m['status']] ??
            InvoiceStatus.unpaid,
        notes: _s(m['notes']),
      );

  @override
  Map<String, dynamic> toMap() => {
        'number': number,
        'tenantId': tenantId,
        'unitId': unitId,
        'propertyId': propertyId,
        'period': period,
        'issueDate': issueDate.millisecondsSinceEpoch,
        'dueDate': dueDate.millisecondsSinceEpoch,
        'items': items.map((e) => e.toMap()).toList(),
        'status': status.name,
        'total': total,
        'notes': notes,
      };

  Invoice withStatus(InvoiceStatus s) => Invoice(
        id: id,
        number: number,
        tenantId: tenantId,
        unitId: unitId,
        propertyId: propertyId,
        period: period,
        issueDate: issueDate,
        dueDate: dueDate,
        items: items,
        status: s,
        notes: notes,
      );
}

// ───────────────────────── Business profile ─────────────────────────

/// Landlord / company details printed on invoices. Stored on users/{uid}.
class BusinessProfile {
  final String name;
  final String phone;
  final String email;
  final String address;
  final String currency;
  final String invoicePrefix;

  const BusinessProfile({
    this.name = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.currency = 'EGP',
    this.invoicePrefix = 'INV-',
  });

  factory BusinessProfile.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const BusinessProfile();
    return BusinessProfile(
      name: _s(m['name']),
      phone: _s(m['phone']),
      email: _s(m['email']),
      address: _s(m['address']),
      currency: _s(m['currency']).isEmpty ? 'EGP' : _s(m['currency']),
      invoicePrefix:
          m['invoicePrefix'] == null ? 'INV-' : _s(m['invoicePrefix']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'currency': currency,
        'invoicePrefix': invoicePrefix,
      };
}

// ────────────────────────────── Dues payment ─────────────────────────────

enum DuesPaymentStatus {
  /// The resident says they paid; waiting for the manager.
  claimed,

  /// The manager confirmed the money was received.
  confirmed,

  /// The manager could not confirm it.
  rejected,
}

/// One flat's payment of its dues for one month. Stored at
/// users/{managerUid}/duesPayments/{unitId}_{period}.
class DuesPayment implements Entity {
  @override
  final String id;
  final String propertyId;
  final String unitId;
  final String period;
  final double amount;
  final PaymentMethod method;
  final DuesPaymentStatus status;
  final String note;
  final String paidByName;
  final String paidByUid;
  final DateTime paidAt;
  final DateTime? confirmedAt;

  DuesPayment({
    String? id,
    required this.propertyId,
    required this.unitId,
    required this.period,
    required this.amount,
    this.method = PaymentMethod.cash,
    this.status = DuesPaymentStatus.claimed,
    this.note = '',
    this.paidByName = '',
    this.paidByUid = '',
    DateTime? paidAt,
    this.confirmedAt,
  })  : id = id ?? docId(unitId, period),
        paidAt = paidAt ?? DateTime.now();

  static String docId(String unitId, String period) => '${unitId}_$period';

  bool get isConfirmed => status == DuesPaymentStatus.confirmed;

  factory DuesPayment.fromMap(String id, Map<String, dynamic> m) => DuesPayment(
        id: id,
        propertyId: _s(m['propertyId']),
        unitId: _s(m['unitId']),
        period: _s(m['period']),
        amount: _d(m['amount']),
        method: PaymentMethod.values.asNameMap()[m['method']] ?? PaymentMethod.cash,
        status: DuesPaymentStatus.values.asNameMap()[m['status']] ?? DuesPaymentStatus.claimed,
        note: _s(m['note']),
        paidByName: _s(m['paidByName']),
        paidByUid: _s(m['paidByUid']),
        paidAt: _dt(m['paidAt']),
        confirmedAt: _dtn(m['confirmedAt']),
      );

  @override
  Map<String, dynamic> toMap() => {
        'propertyId': propertyId,
        'unitId': unitId,
        'period': period,
        'amount': amount,
        'method': method.name,
        'status': status.name,
        'note': note,
        'paidByName': paidByName,
        'paidByUid': paidByUid,
        'paidAt': paidAt.millisecondsSinceEpoch,
        'confirmedAt': confirmedAt?.millisecondsSinceEpoch,
      };

  DuesPayment copyWith({DuesPaymentStatus? status, DateTime? confirmedAt, String? note}) => DuesPayment(
        id: id,
        propertyId: propertyId,
        unitId: unitId,
        period: period,
        amount: amount,
        method: method,
        status: status ?? this.status,
        note: note ?? this.note,
        paidByName: paidByName,
        paidByUid: paidByUid,
        paidAt: paidAt,
        confirmedAt: confirmedAt ?? this.confirmedAt,
      );
}
