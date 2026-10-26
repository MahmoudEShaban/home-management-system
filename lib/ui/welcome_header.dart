import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../data/community.dart';
import '../data/phone_account.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import 'common.dart';

/// "Good morning, Mahmoud 👋" with today's date, at the top of the home pages.
class WelcomeHeader extends ConsumerWidget {
  const WelcomeHeader({super.key});

  /// First name from the account details, Google / display name, the
  /// resident's link to the flat, or the email — whichever exists.
  static String firstNameOf(WidgetRef ref) {
    final account = ref.watch(accountDetailsProvider).value;
    if (account != null && account.firstName.isNotEmpty) return account.firstName;
    final user = ref.watch(authStateProvider).value;
    String first(String s) => s.trim().split(RegExp(r'\s+')).first;
    final display = user?.displayName ?? '';
    if (display.trim().isNotEmpty) return first(display);
    final linked = ref.watch(myRequestProvider).value?.name ?? '';
    if (linked.trim().isNotEmpty) return first(linked);
    if (phoneOfUser(user) == null) {
      final email = user?.email ?? '';
      if (email.contains('@')) return email.substring(0, email.indexOf('@'));
    }
    return '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final name = firstNameOf(ref);
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? t.goodMorning : (hour < 18 ? t.goodAfternoon : t.goodEvening);
    final today = DateFormat.yMMMMEEEEd(Localizations.localeOf(context).languageCode).format(DateTime.now());

    return Entrance(
      offset: 12,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 4, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            name.isEmpty ? '${t.welcome} 👋' : '${t.welcomeName(name)} 👋',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text('$greeting · $today', style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
