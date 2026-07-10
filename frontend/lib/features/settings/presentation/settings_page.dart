import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenity/core/theme/app_theme.dart';
import 'package:serenity/shared/widgets/web_widgets.dart';
import 'package:serenity/state/providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _State();
}

class _State extends ConsumerState<SettingsPage> {
  // Therapist consent fields
  final _therapistEmailCtrl = TextEditingController();
  bool _journalAccess = false;

  @override
  void dispose() {
    _therapistEmailCtrl.dispose();
    super.dispose();
  }

  // ── Save notification/privacy consent ───────────────────────────────────────
  Future<void> _saveConsent() async {
    final ok = await ref.read(consentProvider.notifier).save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Preferences saved.' : 'Could not save. Please try again.'),
      backgroundColor: ok ? AppColors.sageDk : AppColors.rose,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  // ── Grant/revoke therapist access ───────────────────────────────────────────
  Future<void> _setTherapistConsent(bool grant) async {
    final email = _therapistEmailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter a valid therapist email.'),
        backgroundColor: AppColors.rose,
      ));
      return;
    }
    final ok = await ref.read(consentProvider.notifier).setTherapistConsent(
      therapistEmail: email,
      consentGiven:   grant,
      journalAccess:  _journalAccess,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? grant
              ? 'Therapist access granted.'
              : 'Therapist access revoked.'
          : ref.read(consentProvider).error ?? 'Could not update consent.'),
      backgroundColor: ok ? AppColors.sageDk : AppColors.rose,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
    if (ok) _therapistEmailCtrl.clear();
  }

  // ── Delete account ───────────────────────────────────────────────────────────
  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account, all journal entries, '
          'AI insights, and progress data.\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.rose),
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ok = await ref
        .read(authProvider.notifier)
        .deleteAccount(ref.read(apiProvider));

    if (mounted) {
      if (ok) {
        context.go('/login');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not delete account. Please try again.'),
          backgroundColor: AppColors.rose,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t       = Theme.of(context).textTheme;
    final consent = ref.watch(consentProvider);

    return PageScroll(maxW: 700, children: [
      Text('Settings', style: t.displaySmall),
      const SizedBox(height: 4),
      Text('Manage your account and privacy preferences.',
          style: t.bodyMedium?.copyWith(color: AppColors.inkMid)),
      const SizedBox(height: 28),

      // ── Privacy & Notifications ─────────────────────────────────────────────
      WCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Privacy & Notifications', style: t.titleLarge),
        const SizedBox(height: 4),
        Text('All communication is opt-in only.',
            style: t.bodySmall?.copyWith(color: AppColors.inkMid)),
        const SizedBox(height: 20),

        _Toggle(
          'Email reminders',
          'Receive check-in reminders when you have not journaled.',
          consent.emailReminders,
          (v) => ref.read(consentProvider.notifier)
              .toggle(emailReminders: v),
        ),
        const Divider(height: 24),
        _Toggle(
          'Therapist escalation',
          'Allow Serenity to notify your therapist on high-risk patterns.',
          consent.therapistEscalation,
          (v) => ref.read(consentProvider.notifier)
              .toggle(therapistEscalation: v),
        ),
        const Divider(height: 24),
        _Toggle(
          'Rehab escalation',
          'Allow Serenity to notify your rehab contact if you are inactive.',
          consent.rehabEscalation,
          (v) => ref.read(consentProvider.notifier)
              .toggle(rehabEscalation: v),
        ),
        const Divider(height: 24),
        _Toggle(
          'Anonymous analytics',
          'Help improve Serenity. No journal content is ever shared.',
          consent.dataAnalytics,
          (v) => ref.read(consentProvider.notifier)
              .toggle(dataAnalytics: v),
        ),
        const SizedBox(height: 20),

        if (consent.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(consent.error!,
                style: t.bodySmall?.copyWith(color: AppColors.rose)),
          ),

        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 160,
            child: ElevatedButton(
              onPressed: consent.isSaving ? null : _saveConsent,
              child: consent.isSaving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ),
        ),
      ])),
      const SizedBox(height: 16),

      // ── Therapist Access (NEW) ──────────────────────────────────────────────
      WCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Therapist Access', style: t.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Grant your therapist read access to your AI insights and progress. '
          'Your therapist must be registered on Serenity first.',
          style: t.bodySmall?.copyWith(color: AppColors.inkMid, height: 1.5),
        ),
        const SizedBox(height: 20),

        TextField(
          controller: _therapistEmailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Therapist Email',
            hintText: 'therapist@example.com',
            prefixIcon: Icon(Icons.medical_services_outlined),
          ),
        ),
        const SizedBox(height: 14),

        // Journal access toggle
        Row(children: [
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Allow full journal access',
                style: t.titleSmall),
            Text(
              'Off: therapist sees only AI summaries.\n'
              'On: therapist can also read your raw journal entries.',
              style: t.bodySmall
                  ?.copyWith(color: AppColors.inkMid, height: 1.4),
            ),
          ])),
          const SizedBox(width: 16),
          Switch(
            value: _journalAccess,
            onChanged: (v) => setState(() => _journalAccess = v),
            activeColor: AppColors.sage,
          ),
        ]),
        const SizedBox(height: 18),

        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: consent.isSaving
                ? null : () => _setTherapistConsent(false),
            style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.rose,
                side: BorderSide(
                    color: AppColors.rose.withOpacity(0.5))),
            child: const Text('Revoke Access'),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(
            onPressed: consent.isSaving
                ? null : () => _setTherapistConsent(true),
            child: const Text('Grant Access'),
          )),
        ]),
      ])),
      const SizedBox(height: 16),

      // ── About ───────────────────────────────────────────────────────────────
      WCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('About', style: t.titleLarge),
        const SizedBox(height: 14),
        const _Info('Version', '2.0.0'),
        const SizedBox(height: 6),
        const _Info('Backend', 'FastAPI + LangGraph + Supabase'),
        const SizedBox(height: 6),
        const _Info('AI', 'GPT-4o via OpenAI'),
        const SizedBox(height: 14),
        Text(
          'Serenity is not a medical device and does not replace '
          'professional treatment.',
          style: t.bodySmall?.copyWith(color: AppColors.inkLt, height: 1.5),
        ),
      ])),
      const SizedBox(height: 16),

      // ── Sign out ─────────────────────────────────────────────────────────────
      WCard(child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('Sign out', style: t.titleMedium),
          Text('You will be returned to the login page.',
              style: t.bodySmall?.copyWith(color: AppColors.inkMid)),
        ])),
        OutlinedButton.icon(
          onPressed: () async {
            await ref.read(authProvider.notifier).logout();
            if (context.mounted) context.go('/login');
          },
          icon: const Icon(Icons.logout_rounded, size: 15),
          label: const Text('Sign Out'),
          style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.rose,
              side: BorderSide(color: AppColors.rose.withOpacity(0.4))),
        ),
      ])),
      const SizedBox(height: 16),

      // ── Delete account (GDPR) ───────────────────────────────────────────────
      WCard(
        color: AppColors.rose.withOpacity(0.04),
        child: Row(children: [
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Delete Account', style: t.titleMedium),
            Text(
              'Permanently deletes your account, all journal entries, '
              'insights, and progress. This cannot be undone.',
              style: t.bodySmall?.copyWith(
                  color: AppColors.inkMid, height: 1.5),
            ),
          ])),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: _deleteAccount,
            icon: const Icon(Icons.delete_forever_rounded, size: 15),
            label: const Text('Delete Account'),
            style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.rose,
                side: const BorderSide(color: AppColors.rose)),
          ),
        ]),
      ),
      const SizedBox(height: 32),
    ]);
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _Toggle extends StatelessWidget {
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChange;
  const _Toggle(this.title, this.subtitle, this.value, this.onChange);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text(title, style: t.titleSmall),
        const SizedBox(height: 3),
        Text(subtitle,
            style: t.bodySmall?.copyWith(
                color: AppColors.inkMid, height: 1.5)),
      ])),
      const SizedBox(width: 20),
      Switch(value: value, onChanged: onChange, activeColor: AppColors.sage),
    ]);
  }
}

class _Info extends StatelessWidget {
  final String label, value;
  const _Info(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(children: [
      SizedBox(width: 140,
          child: Text(label,
              style: t.bodySmall?.copyWith(color: AppColors.inkLt))),
      Text(value, style: t.bodySmall),
    ]);
  }
}