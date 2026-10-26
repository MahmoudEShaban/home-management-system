import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/community.dart';
import '../data/flat_expenses.dart';
import '../data/google_auth.dart';
import '../data/local_alerts.dart';
import '../data/phone_account.dart';
import '../data/providers.dart';
import '../data/share_payments.dart';
import '../l10n/strings.dart';
import 'attachments_widgets.dart';
import 'chat_screen.dart' show ChatButton;
import 'common.dart';
import 'community_screens.dart' show ExpenseApprovalsScreen;
import 'onboarding_screen.dart' show onboardingDoneProvider;
import 'resident_screens.dart' show FlatStatusPanel, proposalColor;
import 'settings_screen.dart' show LanguageMenuButton, SettingsScreen;
import 'share_payments_ui.dart' show MaintenanceSharesToPay;
import 'spending_screen.dart';

// "More" tab: profile, change name / phone, maintenance requests, settings,
// log out. Used by both the manager and the resident home screens.

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key, required this.resident});

  /// Resident view (their own requests) or manager view (all requests).
  final bool resident;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final user = ref.watch(authStateProvider).value;
    final account = ref.watch(accountDetailsProvider).value ?? const AccountDetails();
    final signInPhone = phoneOfUser(user);
    final name = account.fullName.isNotEmpty ? account.fullName : (user?.displayName ?? '');
    final phone = account.phone.isNotEmpty ? account.phone : (signInPhone ?? '');
    final email = account.email.isNotEmpty ? account.email : (signInPhone == null ? user?.email ?? '' : '');

    final requests = resident
        ? (ref.watch(myProposalsProvider).value ?? const <ExpenseProposal>[])
        : (ref.watch(managerProposalsProvider).value ?? const <ExpenseProposal>[]);
    final maintenance = requests.where((p) => p.isMaintenance).toList();
    final waiting = maintenance.where((p) => p.status == RequestStatus.pending).length;

    return Scaffold(
      // Residents' home already has a top bar (flat name, inbox, language).
      appBar: resident ? null : AppBar(title: Text(t.more), actions: const [LanguageMenuButton()]),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, resident ? 8 : 0, 16, 32),
        children: [
          // Profile card
          Entrance(
            scale: 0.96,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [cs.primaryContainer, cs.tertiaryContainer],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: cs.primary,
                  child: Text(_initials(name.isNotEmpty ? name : (email.isNotEmpty ? email : '?')),
                      style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700, fontSize: 18)),
                ),
                gap12,
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name.isNotEmpty ? name : t.noNameYet,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
                    if (phone.isNotEmpty)
                      Text(displayPhone(phone), style: TextStyle(color: cs.onPrimaryContainer)),
                    if (email.isNotEmpty)
                      Text(email, style: TextStyle(color: cs.onPrimaryContainer.withValues(alpha: 0.8), fontSize: 12)),
                    gap8,
                    StatusChip(label: resident ? t.roleResident : t.roleManager, color: cs.primary),
                  ]),
                ),
              ]),
            ),
          ),
          if (resident) const _MyFlatSection(),
          SectionTitle(t.account),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(t.changeName),
                subtitle: name.isEmpty ? null : Text(name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _changeName(context, ref, account, user?.displayName ?? ''),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.phone_iphone),
                title: Text(t.changePhone),
                subtitle: phone.isEmpty ? null : Text(displayPhone(phone)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _changePhone(context, ref, phone, signInPhone),
              ),
            ]),
          ),
          SectionTitle(t.building),
          Panel(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.handyman_outlined),
              title: Text(resident ? t.myMaintenanceRequests : t.maintenanceRequests),
              subtitle: Text(t.maintenanceRequestsCount(maintenance.length, waiting)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (waiting > 0)
                  Badge(label: Text('$waiting'), backgroundColor: cs.tertiary),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ]),
              onTap: () => push(context, MaintenanceRequestsScreen(resident: resident)),
            ),
          ),
          gap8,
          Panel(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: Text(t.buildingChat),
              subtitle: Text(t.chatRetentionHint),
              trailing: ChatButton(manager: !resident),
            ),
          ),
          SectionTitle(t.app),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              if (!resident) ...[
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(t.settings),
                  subtitle: Text(t.settingsHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => push(context, const SettingsScreen()),
                ),
                const Divider(height: 1),
              ],
              if (ref.watch(hasBothRolesProvider)) ...[
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(resident ? t.switchToManager : t.switchToResident),
                  onTap: () => ref.read(activeViewProvider.notifier).set(resident ? kRoleManager : kRoleResident),
                ),
                const Divider(height: 1),
              ],
              ListTile(
                leading: const Icon(Icons.slideshow_outlined),
                title: Text(t.showIntroAgain),
                onTap: () => ref.read(onboardingDoneProvider.notifier).replay(),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.code),
                title: Text(t.appName),
                subtitle: Text(t.developedBy),
              ),
            ]),
          ),
          gap16,
          OutlinedButton.icon(
            onPressed: () => _logout(context, ref),
            icon: Icon(Icons.logout, color: cs.error),
            label: Text(t.signOut, style: TextStyle(color: cs.error)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    final last = parts.length > 1 ? parts.last.characters.first : '';
    return (first + last).toUpperCase();
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final t = context.t;
    if (!await confirmDialog(context, t.signOutConfirm, confirmLabel: t.signOut)) return;
    await stopBackgroundChecks();
    try {
      await GoogleAuth.signOut();
    } catch (_) {
      // Not signed in with Google.
    }
    await ref.read(firebaseAuthProvider).signOut();
  }

  /// Saves on the account and, for residents, on their link to the flat so
  /// the building manager sees the new details too.
  Future<void> _saveDetails(WidgetRef ref, Map<String, dynamic> account, Map<String, dynamic> link) async {
    final db = ref.read(firestoreProvider);
    final uid = ref.read(uidProvider);
    if (uid == null) return;
    await db.collection('users').doc(uid).set({'account': account}, SetOptions(merge: true));
    final r = ref.read(myRequestProvider).value;
    if (r != null && link.isNotEmpty) {
      Future<void> quiet(Future<void> f) => f.catchError((Object e) => debugPrint('Profile sync: $e'));
      await quiet(db.collection('joinRequests').doc(uid).update(link));
      if (r.status == RequestStatus.approved) {
        await quiet(db.collection('users').doc(r.managerUid).collection('members').doc(uid).update(link));
      }
    }
  }

  Future<void> _changeName(BuildContext context, WidgetRef ref, AccountDetails a, String displayName) async {
    final t = context.t;
    var first = a.firstName;
    var last = a.lastName;
    if (first.isEmpty && last.isEmpty && displayName.isNotEmpty) {
      final i = displayName.indexOf(' ');
      first = i < 0 ? displayName : displayName.substring(0, i);
      last = i < 0 ? '' : displayName.substring(i + 1);
    }
    final firstCtrl = TextEditingController(text: first);
    final lastCtrl = TextEditingController(text: last);
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.changeName),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: firstCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: t.firstName),
              validator: requiredValidator(c),
            ),
            gap12,
            TextFormField(
              controller: lastCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: t.lastName),
              validator: requiredValidator(c),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t.cancel)),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, true);
            },
            child: Text(t.save),
          ),
        ],
      ),
    );
    final f = firstCtrl.text.trim();
    final l = lastCtrl.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      firstCtrl.dispose();
      lastCtrl.dispose();
    });
    if (ok != true) return;
    final full = [f, l].where((s) => s.isNotEmpty).join(' ');
    try {
      await ref.read(firebaseAuthProvider).currentUser?.updateDisplayName(full);
      await _saveDetails(ref, {'firstName': f, 'lastName': l}, {'name': full});
      if (context.mounted) toast(context, t.nameUpdated);
    } catch (e) {
      if (context.mounted) toast(context, '${t.somethingWrong}: $e');
    }
  }

  Future<void> _changePhone(BuildContext context, WidgetRef ref, String current, String? signInPhone) async {
    final t = context.t;
    final ctrl = TextEditingController(text: current.isEmpty ? '' : displayPhone(current));
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.changePhone),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextFormField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: t.phoneNumber, hintText: '01001234567', helperText: t.phoneFormatHint),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? t.requiredField
                  : normalizePhone(v!) == null
                      ? t.invalidPhone
                      : null,
            ),
            if (signInPhone != null) ...[
              gap12,
              Text(t.signInPhoneStays(displayPhone(signInPhone)),
                  style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, fontSize: 12)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t.cancel)),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, true);
            },
            child: Text(t.save),
          ),
        ],
      ),
    );
    final digits = normalizePhone(ctrl.text);
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (ok != true || digits == null) return;
    try {
      await _saveDetails(ref, {'phone': digits}, {'phone': displayPhone(digits)});
      if (context.mounted) toast(context, t.phoneUpdated);
    } catch (e) {
      if (context.mounted) toast(context, '${t.somethingWrong}: $e');
    }
  }
}

// ─────────────────────────── Maintenance requests ───────────────────────────

class MaintenanceRequestsScreen extends ConsumerStatefulWidget {
  const MaintenanceRequestsScreen({super.key, required this.resident});
  final bool resident;

  @override
  ConsumerState<MaintenanceRequestsScreen> createState() => _MaintenanceRequestsScreenState();
}

class _MaintenanceRequestsScreenState extends ConsumerState<MaintenanceRequestsScreen> {
  /// null = all
  RequestStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final async = widget.resident ? ref.watch(myProposalsProvider) : ref.watch(managerProposalsProvider);
    final all = (async.value ?? const <ExpenseProposal>[]).where((p) => p.isMaintenance).toList();
    final list = _filter == null ? all : all.where((p) => p.status == _filter).toList();
    final props = ref.watch(propertyByIdProvider);
    final currency = widget.resident
        ? (ref.watch(residentProfileProvider).value?.currency ?? 'EGP')
        : (ref.watch(profileProvider).value?.currency ?? 'EGP');
    String m(double v) => formatMoney(v, currency, Localizations.localeOf(context).languageCode);
    int count(RequestStatus s) => all.where((p) => p.status == s).length;

    final requestsList = ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              ChoiceChip(
                label: Text('${t.all} (${all.length})'),
                selected: _filter == null,
                onSelected: (_) => setState(() => _filter = null),
              ),
              for (final s in const [RequestStatus.pending, RequestStatus.approved, RequestStatus.rejected]) ...[
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text('${t.proposalStatus(s)} (${count(s)})'),
                  selected: _filter == s,
                  onSelected: (_) => setState(() => _filter = s),
                ),
              ],
            ]),
          ),
          gap12,
          if (async.isLoading && all.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (async.hasError)
            Text('${t.somethingWrong}: ${async.error}', style: TextStyle(color: cs.error))
          else if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: EmptyState(icon: Icons.handyman_outlined, message: t.noMaintenanceRequests),
            )
          else
            for (final p in list) ...[
              Panel(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: !widget.resident && p.status == RequestStatus.pending
                      ? () => push(context, const ExpenseApprovalsScreen())
                      : null,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Text(p.title.isEmpty ? t.maintenanceRequest : p.title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      gap8,
                      StatusChip(label: t.proposalStatus(p.status), color: proposalColor(p.status)),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (!widget.resident) ...[
                          p.unitName,
                          props[p.propertyId]?.name ?? '',
                          p.residentName,
                        ],
                        context.fmtDate(p.createdAt),
                        '${t.urgency}: ${t.urgencyLabel(p.urgency)}',
                        if (p.amount > 0) '${t.estimatedCostShort}: ${m(p.amount)}',
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                    if (p.notes.isNotEmpty) ...[gap8, Text(p.notes)],
                    if (p.decisionNote.isNotEmpty) ...[
                      gap8,
                      Text('${t.managerNote}: “${p.decisionNote}”',
                          style: TextStyle(color: proposalColor(p.status), fontSize: 13)),
                    ],
                    if (p.attachmentIds.isNotEmpty) ...[
                      gap8,
                      AttachmentStrip(managerUid: p.managerUid, ids: p.attachmentIds),
                    ],
                  ]),
                ),
              ),
              gap12,
            ],
        ],
    );
    final title = Text(widget.resident ? t.myMaintenanceRequests : t.maintenanceRequests);
    if (!widget.resident) return Scaffold(appBar: AppBar(title: title), body: requestsList);
    // Residents: what they owe on approved requests, and what they submitted.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: title,
          bottom: TabBar(tabs: [Tab(text: t.sharesToPayTab), Tab(text: t.submittedByMe)]),
        ),
        body: TabBarView(children: [const MaintenanceSharesToPay(), requestsList]),
      ),
    );
  }
}

// ─────────────────────────── My flat (residents) ───────────────────────────

/// The resident's flat: which flat and building, its fixed monthly cost,
/// and the occupancy switch (changes need the manager's approval).
class _MyFlatSection extends ConsumerWidget {
  const _MyFlatSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final m = ref.watch(membershipProvider);
    final unit = ref.watch(residentUnitProvider).value;
    final property = ref.watch(residentPropertyProvider).value;
    if (m == null) return const SizedBox.shrink();
    final currency = ref.watch(residentProfileProvider).value?.currency ?? 'EGP';
    final lang = Localizations.localeOf(context).languageCode;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(t.myFlatStatus),
      Panel(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: cs.primaryContainer,
            child: Icon(Icons.door_front_door_outlined, color: cs.onPrimaryContainer),
          ),
          title: Text(unit?.name ?? m.unitName, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text([
            if (unit != null && unit.floor.isNotEmpty) t.floorLabel(unit.floor),
            property?.name ?? m.propertyName,
            if (unit != null) '${t.fixedMonthly}: ${formatMoney(unit.monthlyFee, currency, lang)}',
          ].where((s) => s.isNotEmpty).join(' · ')),
        ),
      ),
      gap8,
      const _SpendingTile(),
      if (unit != null) ...[gap8, FlatStatusPanel(unit: unit, property: property)],
    ]);
  }
}

/// Opens "My payments & spending" and shows this year's total.
class _SpendingTile extends ConsumerWidget {
  const _SpendingTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final m = ref.watch(membershipProvider);
    if (m == null) return const SizedBox.shrink();
    final year = DateTime.now().year;
    final items = flatSpending(
      t: t,
      unitId: m.unitId,
      dues: ref.watch(residentDuesPaymentsProvider).value ?? const [],
      shares: ref.watch(residentSharePaymentsProvider).value ?? const [],
      flatExpenses: ref.watch(residentFlatExpensesProvider).value ?? const [],
      expenses: ref.watch(residentExpensesProvider).value ?? const [],
      periodLabel: context.fmtPeriod,
    );
    final total = items.where((i) => !i.pending && i.date.year == year).fold<double>(0, (s, i) => s + i.amount);
    final currency = ref.watch(residentProfileProvider).value?.currency ?? 'EGP';
    return Panel(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.tertiaryContainer,
          child: Icon(Icons.account_balance_wallet_outlined, color: cs.onTertiaryContainer),
        ),
        title: Text(t.mySpending, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${t.flatSpendingHint('$year')}: '
            '${formatMoney(total, currency, Localizations.localeOf(context).languageCode)}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => push(context, const SpendingScreen()),
      ),
    );
  }
}
