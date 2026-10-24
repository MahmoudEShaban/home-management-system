import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'repository.dart';

// ─────────────────────────── Platform services ───────────────────────────

/// Overridden in main() with the loaded instance.
final prefsProvider = Provider<SharedPreferences>(
    (ref) => throw UnimplementedError('prefsProvider not overridden'));

final firestoreProvider = Provider((ref) => FirebaseFirestore.instance);
final firebaseAuthProvider = Provider((ref) => FirebaseAuth.instance);

final authStateProvider = StreamProvider<User?>(
    (ref) => ref.watch(firebaseAuthProvider).authStateChanges());

final uidProvider =
    Provider<String?>((ref) => ref.watch(authStateProvider).value?.uid);

// ─────────────────────────────── Locale ───────────────────────────────

/// null = follow the device language.
class LocaleController extends StateNotifier<Locale?> {
  LocaleController(this._prefs) : super(_read(_prefs));
  final SharedPreferences _prefs;

  static Locale? _read(SharedPreferences p) {
    final code = p.getString('locale');
    return code == null ? null : Locale(code);
  }

  void set(Locale? locale) {
    state = locale;
    if (locale == null) {
      _prefs.remove('locale');
    } else {
      _prefs.setString('locale', locale.languageCode);
    }
  }
}

final localeProvider = StateNotifierProvider<LocaleController, Locale?>(
    (ref) => LocaleController(ref.watch(prefsProvider)));

// ───────────────────────────── Repositories ─────────────────────────────

Repo<T> _repo<T extends Entity>(Ref ref, String name,
    T Function(String, Map<String, dynamic>) fromMap) {
  final uid = ref.watch(uidProvider);
  if (uid == null) throw StateError('Not signed in');
  return Repo<T>(ref.watch(firestoreProvider), uid, name, fromMap);
}

final propertyRepo =
    Provider((ref) => _repo<Property>(ref, 'properties', Property.fromMap));
final unitRepo = Provider((ref) => _repo<Unit>(ref, 'units', Unit.fromMap));
final tenantRepo =
    Provider((ref) => _repo<Tenant>(ref, 'tenants', Tenant.fromMap));
final paymentRepo =
    Provider((ref) => _repo<Payment>(ref, 'payments', Payment.fromMap));
final expenseRepo =
    Provider((ref) => _repo<Expense>(ref, 'expenses', Expense.fromMap));
final duesPaymentRepo =
    Provider((ref) => _repo<DuesPayment>(ref, 'duesPayments', DuesPayment.fromMap));
final invoiceRepo =
    Provider((ref) => _repo<Invoice>(ref, 'invoices', Invoice.fromMap));

final userDocRepo = Provider((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) throw StateError('Not signed in');
  return UserDocRepo(ref.watch(firestoreProvider), uid);
});

// ─────────────────────────────── Streams ───────────────────────────────

final propertiesProvider = StreamProvider<List<Property>>((ref) => ref
    .watch(propertyRepo)
    .watch()
    .map((l) => l..sort((a, b) => a.name.compareTo(b.name))));

final unitsProvider = StreamProvider<List<Unit>>((ref) => ref
    .watch(unitRepo)
    .watch()
    .map((l) => l..sort((a, b) => _natural(a.name, b.name))));

final tenantsProvider = StreamProvider<List<Tenant>>((ref) => ref
    .watch(tenantRepo)
    .watch()
    .map((l) => l..sort((a, b) => a.name.compareTo(b.name))));

final paymentsProvider = StreamProvider<List<Payment>>((ref) => ref
    .watch(paymentRepo)
    .watch()
    .map((l) => l..sort((a, b) => b.date.compareTo(a.date))));

final expensesProvider = StreamProvider<List<Expense>>((ref) => ref
    .watch(expenseRepo)
    .watch()
    .map((l) => l..sort((a, b) => b.date.compareTo(a.date))));

final invoicesProvider = StreamProvider<List<Invoice>>((ref) => ref
    .watch(invoiceRepo)
    .watch()
    .map((l) => l..sort((a, b) => b.issueDate.compareTo(a.issueDate))));

final duesPaymentsProvider = StreamProvider<List<DuesPayment>>((ref) => ref.watch(duesPaymentRepo).watch());

final profileProvider = StreamProvider<BusinessProfile>(
    (ref) => ref.watch(userDocRepo).watchProfile());

/// Lookup maps for showing names next to ids.
final propertyByIdProvider = Provider<Map<String, Property>>((ref) => {
      for (final p in ref.watch(propertiesProvider).value ?? <Property>[])
        p.id: p
    });
final unitByIdProvider = Provider<Map<String, Unit>>((ref) => {
      for (final u in ref.watch(unitsProvider).value ?? <Unit>[]) u.id: u
    });
final tenantByIdProvider = Provider<Map<String, Tenant>>((ref) => {
      for (final t in ref.watch(tenantsProvider).value ?? <Tenant>[])
        t.id: t
    });

/// Month selected on the dashboard and rent screen.
final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

/// "Unit 2" < "Unit 10".
int _natural(String a, String b) {
  final na = int.tryParse(a.replaceAll(RegExp(r'\D'), ''));
  final nb = int.tryParse(b.replaceAll(RegExp(r'\D'), ''));
  final pa = a.replaceAll(RegExp(r'\d'), '');
  final pb = b.replaceAll(RegExp(r'\d'), '');
  if (na != null && nb != null && pa == pb) return na.compareTo(nb);
  return a.compareTo(b);
}
