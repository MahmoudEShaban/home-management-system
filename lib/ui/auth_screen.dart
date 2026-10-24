import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/community.dart';
import '../data/google_auth.dart';
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
  bool _register = false;
  String _role = kRoleManager;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    // Applied only if this account has no role yet (i.e. a new account).
    setPendingRole(ref.read(prefsProvider), _role);
    setState(() => _busy = true);
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      if (mounted) toast(context, e.message ?? e.code);
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitEmail() async {
    if (!_form.currentState!.validate()) return;
    final auth = ref.read(firebaseAuthProvider);
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
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(Icons.apartment, size: 40, color: cs.onPrimaryContainer),
                    ),
                    gap16,
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
                        child: Text(t.email, style: TextStyle(color: cs.outline)),
                      ),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(labelText: t.email),
                      validator: requiredValidator(context),
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
                      child: _busy
                          ? const SizedBox(
                              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_register ? t.signUp : t.signIn),
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
