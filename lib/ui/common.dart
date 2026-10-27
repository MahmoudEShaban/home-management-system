import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../data/google_auth.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';

// ─────────────────────────────── Formatting ───────────────────────────────

extension Formatting on BuildContext {
  String get _locale => Localizations.localeOf(this).languageCode;

  String fmtDate(DateTime d) => DateFormat.yMMMd(_locale).format(d);
  String fmtMonth(DateTime d) => DateFormat.yMMMM(_locale).format(d);
  String fmtPeriod(String key) =>
      key.isEmpty ? '' : fmtMonth(periodStart(key));
}

/// Formats an amount with the account currency, e.g. "EGP 12,500.00".
String money(WidgetRef ref, BuildContext context, double v) {
  final currency = ref.watch(profileProvider).value?.currency ?? 'EGP';
  return formatMoney(v, currency, Localizations.localeOf(context).languageCode);
}

String formatMoney(double v, String currency, String locale) {
  final f = NumberFormat.currency(
    locale: locale == 'ar' ? 'ar_EG' : 'en',
    symbol: '$currency ',
    decimalDigits: v == v.roundToDouble() ? 0 : 2,
  );
  return f.format(v);
}

// ─────────────────────────────── Theme ───────────────────────────────

const _seed = Color(0xFF1F6F5C);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFF6F7F5)
        : scheme.surface,
    // Smoother page changes: fade-forward on Android, slide on iOS.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsetsDirectional.only(start: 16, end: 8),
    ),
  );
}

// ─────────────────────────────── Widgets ───────────────────────────────

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Entrance(
              offset: 0,
              scale: 0.4,
              curve: Curves.elasticOut,
              duration: const Duration(milliseconds: 900),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.5), shape: BoxShape.circle),
                child: Icon(icon, size: 44, color: cs.primary),
              ),
            ),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// White rounded panel used to group content.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Slides and fades in when it first appears (e.g. scrolling into view).
    return Entrance(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        padding: padding,
        child: child,
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Entrance(
      offset: 8,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          ?trailing,
        ]),
      ));
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  factory StatusChip.invoice(BuildContext context, InvoiceStatus s) =>
      StatusChip(
        label: context.t.invoiceStatus(s),
        color: switch (s) {
          InvoiceStatus.paid => const Color(0xFF2E7D32),
          InvoiceStatus.unpaid => const Color(0xFFB26A00),
          InvoiceStatus.cancelled => Colors.grey,
        },
      );

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      );
}

IconData expenseIcon(ExpenseCategory c) => switch (c) {
      ExpenseCategory.electricity => Icons.bolt,
      ExpenseCategory.water => Icons.water_drop_outlined,
      ExpenseCategory.gas => Icons.local_fire_department_outlined,
      ExpenseCategory.internet => Icons.wifi,
      ExpenseCategory.maintenance => Icons.build_outlined,
      ExpenseCategory.cleaning => Icons.cleaning_services_outlined,
      ExpenseCategory.security => Icons.shield_outlined,
      ExpenseCategory.elevator => Icons.elevator_outlined,
      ExpenseCategory.taxes => Icons.receipt_long_outlined,
      ExpenseCategory.other => Icons.more_horiz,
    };

/// "‹ October 2026 ›" bar bound to [selectedMonthProvider].
class MonthSwitcher extends ConsumerWidget {
  const MonthSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    void shift(int delta) => ref.read(selectedMonthProvider.notifier).state =
        DateTime(month.year, month.month + delta);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () => shift(-1),
          icon: Icon(isRtl ? Icons.chevron_right : Icons.chevron_left),
        ),
        TextButton(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: month,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              initialDatePickerMode: DatePickerMode.year,
            );
            if (picked != null) {
              ref.read(selectedMonthProvider.notifier).state =
                  DateTime(picked.year, picked.month);
            }
          },
          child: Text(context.fmtMonth(month),
              style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          onPressed: () => shift(1),
          icon: Icon(isRtl ? Icons.chevron_left : Icons.chevron_right),
        ),
      ],
    );
  }
}

Future<bool> confirmDialog(BuildContext context, String message,
    {String? confirmLabel, bool destructive = true}) async {
  final t = context.t;
  final result = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirmLabel ?? t.confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

// ─────────────────────────────── Form helpers ───────────────────────────────

String? Function(String?) requiredValidator(BuildContext context) =>
    (v) => (v == null || v.trim().isEmpty) ? context.t.requiredField : null;

String? Function(String?) numberValidator(BuildContext context,
        {bool isRequired = true}) =>
    (v) {
      final s = (v ?? '').trim();
      if (s.isEmpty) return isRequired ? context.t.requiredField : null;
      return parseNumber(s) == null ? context.t.invalidNumber : null;
    };

/// Accepts Latin and Arabic-Indic digits, commas as thousands separators.
double? parseNumber(String s) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final buf = StringBuffer();
  for (final ch in s.trim().split('')) {
    final i = arabic.indexOf(ch);
    if (i >= 0) {
      buf.write(i);
    } else if (ch == '٫') {
      buf.write('.');
    } else if (ch != ',' && ch != '٬') {
      buf.write(ch);
    }
  }
  return double.tryParse(buf.toString());
}

String numText(double v) =>
    v == 0 ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

/// Read-only field that opens a date picker.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowClear = false,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool allowClear;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: allowClear && value != null
                ? IconButton(icon: const Icon(Icons.clear), onPressed: () => onChanged(null))
                : const Icon(Icons.calendar_today_outlined, size: 20),
          ),
          child: Text(value == null ? '—' : context.fmtDate(value!)),
        ),
      );
}

/// Shows a form screen as a full-screen route.
Future<T?> pushForm<T>(BuildContext context, Widget form) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => form, fullscreenDialog: true));

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

const gap8 = SizedBox(height: 8, width: 8);
const gap12 = SizedBox(height: 12, width: 12);
const gap16 = SizedBox(height: 16, width: 16);

// ─────────────────────────────── Loading ───────────────────────────────

/// Spinner that, if loading takes too long, explains what to do and offers
/// Try again / Sign out instead of spinning forever. [step] names what is
/// loading, which helps when reporting a problem.
class PatientLoader extends StatefulWidget {
  const PatientLoader({super.key, required this.step, this.onRetry, this.fullScreen = true});
  final String step;
  final VoidCallback? onRetry;
  final bool fullScreen;

  @override
  State<PatientLoader> createState() => _PatientLoaderState();
}

class _PatientLoaderState extends State<PatientLoader> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _signOut() async {
    try {
      await GoogleAuth.signOut();
    } catch (_) {
      // Not signed in with Google.
    }
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final body = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          if (_slow) ...[
            const SizedBox(height: 24),
            Text(t.stillLoading,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(t.stillLoadingHint, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('(${widget.step})', style: TextStyle(color: cs.outline, fontSize: 11)),
            const SizedBox(height: 16),
            Wrap(spacing: 12, alignment: WrapAlignment.center, children: [
              if (widget.onRetry != null)
                FilledButton.icon(
                  onPressed: () {
                    setState(() => _slow = false);
                    _timer?.cancel();
                    _timer = Timer(const Duration(seconds: 12), () {
                      if (mounted) setState(() => _slow = true);
                    });
                    widget.onRetry!();
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(t.retry),
                ),
              OutlinedButton.icon(onPressed: _signOut, icon: const Icon(Icons.logout), label: Text(t.signOut)),
            ]),
          ],
        ]),
      ),
    );
    return widget.fullScreen ? Scaffold(body: SafeArea(child: body)) : body;
  }
}

/// Full-page error with Sign out, used instead of a bare error string.
class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Wrap(spacing: 12, alignment: WrapAlignment.center, children: [
                if (onRetry != null)
                  FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(t.retry)),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await GoogleAuth.signOut();
                    } catch (_) {}
                    await FirebaseAuth.instance.signOut();
                  },
                  icon: const Icon(Icons.logout),
                  label: Text(t.signOut),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────── Animation ───────────────────────────────

/// True when the phone asks for reduced motion (accessibility setting).
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Fades, slides up and optionally grows [child] in the first time it is
/// built. Rebuilds don't replay it.
class Entrance extends StatelessWidget {
  const Entrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    this.offset = 18,
    this.scale = 1,
    this.curve = Curves.easeOutCubic,
  });
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;
  final double scale;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    final total = delay + duration;
    final start = total.inMicroseconds == 0 ? 0.0 : delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: curve),
      child: child,
      builder: (context, v, child) {
        final o = v.clamp(0.0, 1.0);
        Widget w = Transform.translate(offset: Offset(0, (1 - v) * offset), child: child);
        if (scale != 1) w = Transform.scale(scale: scale + (1 - scale) * v, child: w);
        return Opacity(opacity: o, child: w);
      },
    );
  }
}

/// Number text that counts up to [value] and animates when it changes.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({super.key, required this.value, required this.format, this.style});
  final double value;
  final String Function(double) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return Text(format(value), style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}

/// IndexedStack (keeps each tab's state) that fades and slightly slides the
/// newly selected tab in.
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 280), value: 1);
  late final _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void didUpdateWidget(FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !reduceMotion(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(_curve),
          child: IndexedStack(index: widget.index, children: widget.children),
        ),
      );
}
