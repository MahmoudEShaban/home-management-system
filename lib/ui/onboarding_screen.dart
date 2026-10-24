import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:lottie/lottie.dart';

import '../data/providers.dart';
import '../l10n/strings.dart';
import 'settings_screen.dart' show LanguageMenuButton;

const _kOnboardingDone = 'onboarding.done';

/// Whether the first-run introduction has been seen on this phone.
class OnboardingController extends StateNotifier<bool> {
  OnboardingController(this._ref) : super(_ref.read(prefsProvider).getBool(_kOnboardingDone) ?? false);
  final Ref _ref;

  void finish() {
    state = true;
    _ref.read(prefsProvider).setBool(_kOnboardingDone, true);
  }

  void replay() {
    state = false;
    _ref.read(prefsProvider).setBool(_kOnboardingDone, false);
  }
}

final onboardingDoneProvider =
    StateNotifierProvider<OnboardingController, bool>((ref) => OnboardingController(ref));

class _Page {
  final String animation;
  final String title;
  final String body;
  const _Page(this.animation, this.title, this.body);
}

/// Short first-run tour. Animations live in assets/animations/ and can be
/// replaced with any LottieFiles JSON of the same name.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() => ref.read(onboardingDoneProvider.notifier).finish();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final pages = [
      _Page('assets/animations/onboarding_buildings.json', t.introTitle1, t.introBody1),
      _Page('assets/animations/onboarding_split.json', t.introTitle2, t.introBody2),
      _Page('assets/animations/onboarding_approve.json', t.introTitle3, t.introBody3),
      _Page('assets/animations/onboarding_bell.json', t.introTitle4, t.introBody4),
    ];
    final last = _page == pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              const LanguageMenuButton(),
              const Spacer(),
              AnimatedOpacity(
                opacity: last ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(onPressed: last ? null : _done, child: Text(t.skip)),
              ),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) {
                final p = pages[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Center(
                          child: Lottie.asset(
                            p.animation,
                            fit: BoxFit.contain,
                            repeat: true,
                            // Keep the tour usable even if an animation file is replaced badly.
                            errorBuilder: (_, _, _) =>
                                Icon(Icons.apartment, size: 120, color: cs.primary),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Column(children: [
                          Text(p.title,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          Text(p.body,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(color: cs.onSurfaceVariant, height: 1.4)),
                        ]),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < pages.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == _page ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _page ? cs.primary : cs.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: FilledButton(
              onPressed: () => last
                  ? _done()
                  : _controller.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(last ? t.getStartedButton : t.next),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Small "Developed by Mahmoud Essam" line shown at the bottom of every page.
class DeveloperCredit extends StatelessWidget {
  const DeveloperCredit({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.code, size: 12, color: cs.outline),
            const SizedBox(width: 4),
            Text(
              context.t.developedBy,
              style: TextStyle(fontSize: 11, color: cs.outline, letterSpacing: 0.2),
            ),
          ]),
        ),
      ),
    );
  }
}
