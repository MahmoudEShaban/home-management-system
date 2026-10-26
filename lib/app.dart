import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/backup_service.dart';
import 'data/community.dart';
import 'data/local_alerts.dart';
import 'data/providers.dart';
import 'l10n/strings.dart';
import 'ui/auth_screen.dart';
import 'ui/dashboard_screen.dart';
import 'ui/expenses_screen.dart';
import 'ui/invoices_screen.dart';
import 'ui/properties_screen.dart';
import 'ui/resident_screens.dart';
import 'ui/role_choice_screen.dart';
import 'ui/more_screen.dart';
import 'data/chat.dart' show chatCleanupProvider;
import 'ui/common.dart';
import 'ui/onboarding_screen.dart';

class RentManagerApp extends ConsumerWidget {
  const RentManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final introSeen = ref.watch(onboardingDoneProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (c) => c.t.appName,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: introSeen ? const AuthGate() : const OnboardingScreen(),
      // Developer note under every page (hidden while the keyboard is open).
      builder: (context, child) {
        final media = MediaQuery.of(context);
        if (child == null || media.viewInsets.bottom > 0) return child ?? const SizedBox.shrink();
        return Column(children: [
          Expanded(
            child: MediaQuery.removePadding(context: context, removeBottom: true, child: child),
          ),
          const DeveloperCredit(),
        ]);
      },
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    return auth.when(
      loading: () => const PatientLoader(step: 'auth'),
      error: (e, _) => ErrorScreen(error: e),
      data: (user) {
        if (user == null) return const AuthScreen();
        // Show new inbox items as phone notifications while signed in.
        ref.watch(localAlertsProvider);
        final role = ref.watch(roleProvider);
        return role.when(
          loading: () => PatientLoader(step: 'role', onRetry: () => ref.invalidate(roleProvider)),
          error: (e, _) => ErrorScreen(error: e, onRetry: () => ref.invalidate(roleProvider)),
          // Keyed by uid so all per-user state resets when the account changes.
          data: (r) {
            // New account with no role yet (e.g. first Google sign-in): ask once.
            if (r == kRoleUnset) return RoleChoiceScreen(key: ValueKey('role${user.uid}'));
            final view = r == kRoleBoth ? ref.watch(activeViewProvider) : r;
            return view == kRoleResident
                ? ResidentGate(key: ValueKey('r${user.uid}'))
                : HomeShell(key: ValueKey(user.uid));
          },
        );
      },
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Give Firestore a moment to load the cache before the first snapshot.
    Future.delayed(const Duration(seconds: 3), _autoBackup);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _autoBackup();
  }

  void _autoBackup() {
    if (!mounted) return;
    ref.read(backupProvider.notifier).runIfDue();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    // Keep resident building codes up to date with flats and members.
    ref.watch(buildingCodeSyncProvider);
    // Delete chat messages older than the retention period.
    ref.watch(chatCleanupProvider);
    final pages = [
      DashboardScreen(onNavigate: (i) => setState(() => _index = i)),
      const PropertiesScreen(),
      const ExpensesScreen(),
      const InvoicesScreen(),
      const MoreScreen(resident: false),
    ];
    return Scaffold(
      body: FadeIndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.space_dashboard_outlined),
              selectedIcon: const Icon(Icons.space_dashboard),
              label: t.dashboard),
          NavigationDestination(
              icon: const Icon(Icons.apartment_outlined),
              selectedIcon: const Icon(Icons.apartment),
              label: t.properties),
          NavigationDestination(
              icon: const Icon(Icons.bolt_outlined),
              selectedIcon: const Icon(Icons.bolt),
              label: t.expenses),
          NavigationDestination(
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: const Icon(Icons.receipt_long),
              label: t.invoices),
          NavigationDestination(
              icon: const Icon(Icons.more_horiz), selectedIcon: const Icon(Icons.more_horiz), label: t.more),
        ],
      ),
    );
  }
}
