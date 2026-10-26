import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/community.dart';
import '../data/google_auth.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import 'common.dart';
import 'settings_screen.dart' show LanguageMenuButton;

/// Shown once for a new account that has no role yet — e.g. the first
/// "Continue with Google" from the sign-in page. The choice is saved on the
/// account and never asked again.
class RoleChoiceScreen extends ConsumerStatefulWidget {
  const RoleChoiceScreen({super.key});

  @override
  ConsumerState<RoleChoiceScreen> createState() => _RoleChoiceScreenState();
}

class _RoleChoiceScreenState extends ConsumerState<RoleChoiceScreen> {
  String? _role;
  bool _busy = false;

  Future<void> _continue() async {
    final role = _role;
    if (role == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(roleChoiceProvider)(role);
      // The role stream updates and the app opens the right home screen.
    } catch (e) {
      if (mounted) toast(context, '${context.t.somethingWrong}: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await GoogleAuth.signOut();
    } catch (_) {
      // Not signed in with Google.
    }
    await ref.read(firebaseAuthProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final user = ref.watch(authStateProvider).value;
    final name = (user?.displayName ?? '').trim().split(RegExp(r'\s+')).first;

    Widget option(String role, IconData icon, String title, String hint) {
      final selected = _role == role;
      return Entrance(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _busy ? null : () => setState(() => _role = role),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: selected ? cs.primary : cs.secondaryContainer,
                  child: Icon(icon, color: selected ? cs.onPrimary : cs.onSecondaryContainer),
                ),
                gap12,
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(hint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  ]),
                ),
                AnimatedOpacity(
                  opacity: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.check_circle, color: cs.primary),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(actions: [
        const LanguageMenuButton(),
        TextButton(onPressed: _busy ? null : _signOut, child: Text(t.signOut)),
      ]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(name.isEmpty ? t.welcome : t.welcomeName(name),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                gap8,
                Text(t.chooseRoleBody, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 24),
                option(kRoleManager, Icons.manage_accounts_outlined, t.roleManager, t.roleManagerHint),
                gap12,
                option(kRoleResident, Icons.home_outlined, t.roleResident, t.roleResidentHint),
                gap16,
                Text(t.chooseRoleOnce,
                    textAlign: TextAlign.center, style: TextStyle(color: cs.outline, fontSize: 12)),
                gap16,
                FilledButton(
                  onPressed: _role == null || _busy ? null : _continue,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t.next),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
