import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup_service.dart';
import '../data/community.dart';
import '../data/google_auth.dart';
import '../data/models.dart';
import '../data/local_alerts.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import 'common.dart';
import 'onboarding_screen.dart' show onboardingDoneProvider;

/// Globe icon that switches between System / English / العربية.
class LanguageMenuButton extends ConsumerWidget {
  const LanguageMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    return PopupMenuButton<String>(
      tooltip: t.language,
      icon: const Icon(Icons.language),
      onSelected: (code) =>
          ref.read(localeProvider.notifier).set(code == 'system' ? null : Locale(code)),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'system', child: Text(t.systemDefault)),
        const PopupMenuItem(value: 'en', child: Text('English')),
        const PopupMenuItem(value: 'ar', child: Text('العربية')),
      ],
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final locale = ref.watch(localeProvider);
    final user = ref.watch(authStateProvider).value;
    final profile = ref.watch(profileProvider).value ?? const BusinessProfile();

    return Scaffold(
      appBar: AppBar(title: Text(t.settings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          SectionTitle(t.language),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'system', label: Text(t.systemDefault)),
              const ButtonSegment(value: 'en', label: Text('English')),
              const ButtonSegment(value: 'ar', label: Text('العربية')),
            ],
            selected: {locale?.languageCode ?? 'system'},
            onSelectionChanged: (s) => ref
                .read(localeProvider.notifier)
                .set(s.first == 'system' ? null : Locale(s.first)),
          ),
          SectionTitle(t.businessProfile),
          Panel(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.business_outlined),
              title: Text(profile.name.isEmpty ? t.businessName : profile.name),
              subtitle: Text('${t.currency}: ${profile.currency} · ${t.invoicePrefix}: ${profile.invoicePrefix}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => pushForm(context, ProfileForm(profile: profile)),
            ),
          ),
          SectionTitle(t.backups),
          Panel(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: Text(t.googleDrive),
              subtitle: Text(ref.watch(backupProvider).driveAccount ?? t.connectDrive),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => push(context, const BackupScreen()),
            ),
          ),
          SectionTitle(t.about),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.slideshow_outlined),
                title: Text(t.showIntroAgain),
                onTap: () {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  ref.read(onboardingDoneProvider.notifier).replay();
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.code),
                title: Text(t.appName),
                subtitle: Text(t.developedBy),
              ),
            ]),
          ),
          SectionTitle(t.account),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(user?.displayName?.isNotEmpty == true ? user!.displayName! : (user?.email ?? '')),
                subtitle: user?.displayName?.isNotEmpty == true ? Text(user?.email ?? '') : null,
              ),
              if (ref.watch(hasBothRolesProvider)) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(t.switchToResident),
                  subtitle: Text(t.bothRolesHint),
                  onTap: () {
                    ref.read(activeViewProvider.notifier).set(kRoleResident);
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
                title: Text(t.signOut, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () async {
                  if (!await confirmDialog(context, '${t.signOut}?', confirmLabel: t.signOut)) return;
                  await ref.read(backupProvider.notifier).disconnect();
                  await stopBackgroundChecks();
                  try {
                    await GoogleAuth.signOut();
                  } catch (_) {
                    // Not signed in with Google; nothing to do.
                  }
                  await ref.read(firebaseAuthProvider).signOut();
                  if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                },
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class ProfileForm extends ConsumerStatefulWidget {
  const ProfileForm({super.key, required this.profile});
  final BusinessProfile profile;

  @override
  ConsumerState<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<ProfileForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.name);
  late final _phone = TextEditingController(text: widget.profile.phone);
  late final _email = TextEditingController(text: widget.profile.email);
  late final _address = TextEditingController(text: widget.profile.address);
  late final _currency = TextEditingController(text: widget.profile.currency);
  late final _prefix = TextEditingController(text: widget.profile.invoicePrefix);

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _address, _currency, _prefix]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    ref.read(userDocRepo).saveProfile(BusinessProfile(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          address: _address.text.trim(),
          currency: _currency.text.trim().toUpperCase(),
          invoicePrefix: _prefix.text.trim(),
        ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.businessProfile),
        actions: [TextButton(onPressed: _save, child: Text(t.save))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(controller: _name, decoration: InputDecoration(labelText: t.businessName)),
            gap12,
            TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: t.phone)),
            gap12,
            TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: t.email)),
            gap12,
            TextFormField(controller: _address, maxLines: 2, decoration: InputDecoration(labelText: t.address)),
            gap12,
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _currency,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(labelText: t.currency, hintText: 'EGP'),
                  validator: requiredValidator(context),
                ),
              ),
              gap12,
              Expanded(
                child: TextFormField(
                  controller: _prefix,
                  decoration: InputDecoration(labelText: t.invoicePrefix, hintText: 'INV-'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────── Backups ───────────────────────────────

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  Future<List<DriveBackupInfo>>? _backups;

  @override
  void initState() {
    super.initState();
    if (ref.read(backupProvider).connected) {
      _backups = ref.read(backupProvider.notifier).listBackups();
    }
  }

  void _refresh() {
    setState(() => _backups = ref.read(backupProvider.notifier).listBackups());
  }

  Future<void> _guard(Future<void> Function() action, {String? success}) async {
    try {
      await action();
      if (mounted && success != null) toast(context, success);
    } catch (e) {
      if (mounted) toast(context, '${context.t.somethingWrong}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final state = ref.watch(backupProvider);
    final ctrl = ref.read(backupProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(t.backups)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.add_to_drive, color: cs.primary),
                  gap12,
                  Expanded(
                    child: Text(t.googleDrive,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  if (state.connected)
                    TextButton(
                      onPressed: () => _guard(ctrl.disconnect),
                      child: Text(t.disconnect),
                    ),
                ]),
                gap8,
                if (!state.connected) ...[
                  Text(t.driveNotConnected, style: TextStyle(color: cs.onSurfaceVariant)),
                  gap12,
                  FilledButton.icon(
                    onPressed: () => _guard(() async {
                      await ctrl.connect();
                      if (ref.read(backupProvider).connected) _refresh();
                    }),
                    icon: const Icon(Icons.link),
                    label: Text(t.connectDrive),
                  ),
                ] else ...[
                  Text('${t.connectedAs} ${state.driveAccount}'),
                  const SizedBox(height: 4),
                  Text(
                    '${t.lastBackup}: ${state.lastBackup == null ? t.neverBackedUp : '${context.fmtDate(state.lastBackup!)} ${TimeOfDay.fromDateTime(state.lastBackup!).format(context)}'}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  if (state.lastError != null) ...[
                    const SizedBox(height: 4),
                    Text('${t.backupFailed}: ${state.lastError}',
                        style: TextStyle(color: cs.error, fontSize: 12)),
                  ],
                  gap12,
                  FilledButton.icon(
                    onPressed: state.busy
                        ? null
                        : () => _guard(() async {
                              await ctrl.backupNow();
                              _refresh();
                            }, success: t.backupDone),
                    icon: state.busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.backup_outlined),
                    label: Text(state.busy ? t.working : t.backupNow),
                  ),
                ],
              ],
            ),
          ),
          if (state.connected) ...[
            SectionTitle(t.autoBackup),
            SegmentedButton<BackupFrequency>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: BackupFrequency.off, label: Text(t.off)),
                ButtonSegment(value: BackupFrequency.daily, label: Text(t.daily)),
                ButtonSegment(value: BackupFrequency.weekly, label: Text(t.weekly)),
              ],
              selected: {state.frequency},
              onSelectionChanged: (s) => ctrl.setFrequency(s.first),
            ),
            gap8,
            Text(t.autoBackupHint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            SectionTitle(
              t.driveBackups,
              trailing: IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
            ),
            FutureBuilder<List<DriveBackupInfo>>(
              future: _backups,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return Panel(child: Text('${t.somethingWrong}: ${snap.error}'));
                }
                final list = snap.data ?? const <DriveBackupInfo>[];
                if (list.isEmpty) return Panel(child: Text(t.noBackups));
                return Panel(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (final b in list)
                      ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(b.createdTime == null
                            ? b.name
                            : '${context.fmtDate(b.createdTime!)} ${TimeOfDay.fromDateTime(b.createdTime!).format(context)}'),
                        subtitle: Text('${(b.sizeBytes / 1024).toStringAsFixed(1)} KB'),
                        trailing: TextButton(
                          onPressed: state.busy
                              ? null
                              : () async {
                                  if (!await confirmDialog(context, t.restoreConfirm, confirmLabel: t.restore)) {
                                    return;
                                  }
                                  await _guard(() => ctrl.restore(b.id), success: t.restoreDone);
                                },
                          child: Text(t.restore),
                        ),
                      ),
                  ]),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
