import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

import '../data/community.dart';
import '../data/google_auth.dart';
import '../data/phone_account.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import 'common.dart';
import 'settings_screen.dart' show LanguageMenuButton;

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _contactEmail = TextEditingController();
  bool _register = false;
  bool _usePhone = false;
  String _role = kRoleManager;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _contactEmail.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    // Applied only if this account has no role yet (i.e. a new account).
    setPendingRole(ref.read(prefsProvider), _role);
    setState(() => _busy = true);
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      if (mounted) toast(context, _authMessage(e));
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Friendlier messages for the common sign-in errors, phone accounts
  /// included (they use a hidden sign-in address).
  String _authMessage(FirebaseAuthException e) {
    final t = context.t;
    return switch (e.code) {
      'email-already-in-use' => _usePhone ? t.phoneAlreadyRegistered : t.emailAlreadyRegistered,
      'invalid-credential' || 'wrong-password' || 'user-not-found' || 'invalid-email' =>
        _usePhone ? t.phoneOrPasswordWrong : t.emailOrPasswordWrong,
      'weak-password' => t.passwordTooShort,
      'too-many-requests' => t.tooManyAttempts,
      'network-request-failed' => t.noInternet,
      _ => e.message ?? e.code,
    };
  }

  Future<void> _submitEmail() async {
    if (!_form.currentState!.validate()) return;
    final auth = ref.read(firebaseAuthProvider);
    if (_usePhone) {
      final digits = normalizePhone(_phone.text)!;
      final db = ref.read(firestoreProvider);
      await _run(() async {
        if (_register) {
          await registerWithPhone(auth, db,
              phoneDigits: digits,
              password: _password.text,
              details: AccountDetails(
                firstName: _firstName.text.trim(),
                lastName: _lastName.text.trim(),
                email: _contactEmail.text.trim(),
                phone: digits,
              ));
        } else {
          await signInWithPhone(auth, phoneDigits: digits, password: _password.text);
        }
      });
      return;
    }
    await _run(() async {
      if (_register) {
        await auth.createUserWithEmailAndPassword(
            email: _email.text.trim(), password: _password.text);
      } else {
        await auth.signInWithEmailAndPassword(
            email: _email.text.trim(), password: _password.text);
      }
    });
  }

  Future<void> _google() => _run(() async {
        final account = await GoogleAuth.signIn();
        if (account == null) return; // cancelled
        final credential =
            GoogleAuthProvider.credential(idToken: GoogleAuth.idToken(account));
        await ref.read(firebaseAuthProvider).signInWithCredential(credential);
      });

  Future<void> _reset() async {
    if (_usePhone) {
      // Phone accounts have no mailbox behind their sign-in address.
      toast(context, context.t.phoneResetHint);
      return;
    }
    final email = _email.text.trim();
    if (email.isEmpty) {
      toast(context, '${context.t.email}: ${context.t.requiredField}');
      return;
    }
    final message = context.t.resetSent;
    await _run(() async {
      await ref.read(firebaseAuthProvider).sendPasswordResetEmail(email: email);
      if (mounted) toast(context, message);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(actions: const [LanguageMenuButton()]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Entrance(
                      offset: 0,
                      scale: 0.6,
                      child: SizedBox(
                        height: 120,
                        child: Lottie.asset(
                          'assets/animations/onboarding_buildings.json',
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Icon(Icons.apartment, size: 64, color: cs.primary),
                        ),
                      ),
                    ),
                    gap8,
                    Text(t.appName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    gap8,
                    Text(t.authTagline,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 24),
                    Text(t.iAmA, style: Theme.of(context).textTheme.labelLarge),
                    gap8,
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                            value: kRoleManager,
                            icon: const Icon(Icons.manage_accounts_outlined),
                            label: Text(t.roleManager)),
                        ButtonSegment(
                            value: kRoleResident,
                            icon: const Icon(Icons.home_outlined),
                            label: Text(t.roleResident)),
                      ],
                      selected: {_role},
                      onSelectionChanged: (v) => setState(() => _role = v.first),
                    ),
                    gap8,
                    Text(_role == kRoleResident ? t.roleResidentHint : t.roleManagerHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _google,
                      icon: const Icon(Icons.g_mobiledata, size: 28),
                      label: Text(t.continueWithGoogle),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    ),
                    const SizedBox(height: 24),
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(t.orSignInWith, style: TextStyle(color: cs.outline)),
                      ),
                      const Expanded(child: Divider()),
                    ]),
                    gap16,
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: false, icon: const Icon(Icons.alternate_email), label: Text(t.email)),
                        ButtonSegment(value: true, icon: const Icon(Icons.phone_iphone), label: Text(t.phoneNumber)),
                      ],
                      selected: {_usePhone},
                      onSelectionChanged: (v) => setState(() => _usePhone = v.first),
                    ),
                    gap16,
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SizeTransition(sizeFactor: a, axisAlignment: -1, child: child),
                      ),
                      child: _usePhone
                          ? TextFormField(
                              key: const ValueKey('phone'),
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              autofillHints: const [AutofillHints.telephoneNumber],
                              decoration: InputDecoration(
                                labelText: t.phoneNumber,
                                hintText: '01001234567',
                                helperText: t.phoneFormatHint,
                                prefixIcon: const Icon(Icons.phone_iphone),
                              ),
                              validator: (v) => (v ?? '').trim().isEmpty
                                  ? t.requiredField
                                  : normalizePhone(v!) == null
                                      ? t.invalidPhone
                                      : null,
                            )
                          : TextFormField(
                              key: const ValueKey('email'),
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: InputDecoration(labelText: t.email, prefixIcon: const Icon(Icons.alternate_email)),
                              validator: requiredValidator(context),
                            ),
                    ),
                    // Phone sign-up also asks for the person's details.
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _usePhone && _register
                          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              gap12,
                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _firstName,
                                    textCapitalization: TextCapitalization.words,
                                    autofillHints: const [AutofillHints.givenName],
                                    decoration: InputDecoration(labelText: t.firstName),
                                    validator: requiredValidator(context),
                                  ),
                                ),
                                gap12,
                                Expanded(
                                  child: TextFormField(
                                    controller: _lastName,
                                    textCapitalization: TextCapitalization.words,
                                    autofillHints: const [AutofillHints.familyName],
                                    decoration: InputDecoration(labelText: t.lastName),
                                    validator: requiredValidator(context),
                                  ),
                                ),
                              ]),
                              gap12,
                              TextFormField(
                                controller: _contactEmail,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                decoration: InputDecoration(labelText: t.email, prefixIcon: const Icon(Icons.alternate_email)),
                                validator: (v) {
                                  final s = (v ?? '').trim();
                                  if (s.isEmpty) return t.requiredField;
                                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s) ? null : t.invalidEmail;
                                },
                              ),
                            ])
                          : const SizedBox(width: double.infinity),
                    ),
                    gap12,
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(labelText: t.password),
                      validator: (v) => (v ?? '').length < 6 ? t.passwordTooShort : null,
                      onFieldSubmitted: (_) => _submitEmail(),
                    ),
                    if (!_register)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(onPressed: _busy ? null : _reset, child: Text(t.forgotPassword)),
                      )
                    else
                      gap16,
                    FilledButton(
                      onPressed: _busy ? null : _submitEmail,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _busy
                            ? const SizedBox(
                                key: ValueKey('busy'),
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_register ? t.signUp : t.signIn, key: ValueKey(_register)),
                      ),
                    ),
                    gap8,
                    TextButton(
                      onPressed: _busy ? null : () => setState(() => _register = !_register),
                      child: Text(_register ? t.haveAccount : t.noAccount),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
