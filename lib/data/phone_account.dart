// Phone-number accounts on the free Firebase plan.
//
// Firebase only sends SMS codes on the paid Blaze plan, so phone accounts use
// email/password sign-in behind the scenes: the normalised phone number is
// turned into a private sign-in address (p201001234567@phone.homemanagement.app)
// that is never shown or emailed. Firebase keeps sign-in addresses unique,
// so each phone number can register once.
//
// The person's details (first name, last name, real email, phone) are saved
// in users/{uid}.account and used to pre-fill forms.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

const _kPhoneDomain = 'phone.homemanagement.app';

/// Digits with country code (e.g. "201001234567"), or null if it doesn't
/// look like a phone number. Accepts Arabic-Indic digits, spaces, dashes,
/// "+" or "00" prefixes. A local Egyptian number (01xxxxxxxxx) gets +20.
String? normalizePhone(String input) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in input.trim().split('')) {
    final a = arabic.indexOf(ch);
    final p = persian.indexOf(ch);
    if (a >= 0) {
      b.write(a);
    } else if (p >= 0) {
      b.write(p);
    } else if (RegExp(r'[0-9]').hasMatch(ch)) {
      b.write(ch);
    } else if (ch == '+' && b.isEmpty) {
      // country code follows
    } else if (!RegExp(r'[\s\-().]').hasMatch(ch)) {
      return null; // letters or other symbols
    }
  }
  var d = b.toString();
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 11 && d.startsWith('01')) d = '2$d'; // Egypt: 01x… → 201x…
  if (d.length < 8 || d.length > 15) return null;
  return d;
}

/// Shows "+201001234567".
String displayPhone(String digits) => digits.isEmpty ? '' : '+$digits';

String phoneSignInAddress(String digits) => 'p$digits@$_kPhoneDomain';

/// The phone number behind a phone account's sign-in address, or null.
String? phoneOfUser(User? u) {
  final e = u?.email ?? '';
  if (!e.endsWith('@$_kPhoneDomain') || !e.startsWith('p')) return null;
  return e.substring(1, e.indexOf('@'));
}

class AccountDetails {
  final String firstName;
  final String lastName;
  final String email;
  final String phone; // digits with country code

  const AccountDetails({this.firstName = '', this.lastName = '', this.email = '', this.phone = ''});

  String get fullName => [firstName, lastName].where((s) => s.isNotEmpty).join(' ');

  factory AccountDetails.fromMap(Map<String, dynamic>? m) => AccountDetails(
        firstName: '${m?['firstName'] ?? ''}',
        lastName: '${m?['lastName'] ?? ''}',
        email: '${m?['email'] ?? ''}',
        phone: '${m?['phone'] ?? ''}',
      );

  Map<String, dynamic> toMap() => {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
      };
}

/// Creates a phone account and saves the person's details.
Future<void> registerWithPhone(
  FirebaseAuth auth,
  FirebaseFirestore db, {
  required String phoneDigits,
  required String password,
  required AccountDetails details,
}) async {
  final cred = await auth.createUserWithEmailAndPassword(
      email: phoneSignInAddress(phoneDigits), password: password);
  final user = cred.user!;
  await user.updateDisplayName(details.fullName);
  await db.collection('users').doc(user.uid).set({'account': details.toMap()}, SetOptions(merge: true));
}

Future<void> signInWithPhone(FirebaseAuth auth, {required String phoneDigits, required String password}) =>
    auth.signInWithEmailAndPassword(email: phoneSignInAddress(phoneDigits), password: password);

/// The signed-in person's saved details (empty for older accounts).
final accountDetailsProvider = StreamProvider<AccountDetails>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const AccountDetails());
  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((s) => AccountDetails.fromMap((s.data()?['account'] as Map?)?.cast<String, dynamic>()));
});
