import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenity/core/theme/app_theme.dart';
import 'package:serenity/models/app_models.dart';
import 'package:serenity/shared/widgets/web_widgets.dart';
import 'package:serenity/state/providers.dart';

class TherapistDashboardPage extends ConsumerWidget {
  const TherapistDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patients = ref.watch(therapistPatientsProvider);
    final t        = Theme.of(context).textTheme;

    return PageScroll(children: [
      // Header
      Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Therapist Dashboard', style: t.displaySmall),
          const SizedBox(height: 4),
          Text('Your linked patients — read only.',
              style: t.bodyMedium?.copyWith(color: AppColors.inkMid)),
        ]),
      ]),
      const SizedBox(height: 28),

      patients.when(
        loading: () => Column(children: List.generate(3, (_) =>
            Padding(padding: const EdgeInsets.only(bottom: 12),
                child: WShimmer(h: 100)))),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('⚠️', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 12),
            Text('Could not load patients.',
                style: t.headlineSmall?.copyWith(color: AppColors.inkMid)),
            const SizedBox(height: 6),
            Text(e.toString(),
                style: t.bodySmall?.copyWith(color: AppColors.inkLt)),
          ]),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('🌱', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 16),
              Text('No linked patients yet.',
                  style: t.headlineSmall?.copyWith(color: AppColors.inkMid)),
              const SizedBox(height: 8),
              Text(
                'Ask your patients to enter your email\n'
                'in Settings → Therapist Access.',
                style: t.bodySmall?.copyWith(
                    color: AppColors.inkLt, height: 1.6),
                textAlign: TextAlign.center,
              ),
            ]));
          }

          // Red-flag patients first
          final sorted = [...list]
            ..sort((a, b) {
              final aRisk = a.latestRiskLevel == 'high' ? 0
                  : a.latestRiskLevel == 'moderate' ? 1 : 2;
              final bRisk = b.latestRiskLevel == 'high' ? 0
                  : b.latestRiskLevel == 'moderate' ? 1 : 2;
              return aRisk.compareTo(bRisk);
            });

          return Column(children: sorted
              .map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PatientCard(patient: p),
                  ))
              .toList());
        },
      ),
    ]);
  }
}

// ── Patient card ──────────────────────────────────────────────────────────────

class _PatientCard extends ConsumerWidget {
  final TherapistPatient patient;
  const _PatientCard({required this.patient});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;

    final (riskColor, riskLabel) = switch (patient.latestRiskLevel) {
      'high'     => (AppColors.rose,  'High Risk'),
      'moderate' => (AppColors.amber, 'Moderate'),
      _          => (AppColors.sage,  'Low Risk'),
    };

    return WCard(
      onTap: () => _showPatientDetail(context, ref, patient),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Top row — name + risk badge
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.sageSurf,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.sageLt),
            ),
            child: Center(child: Text(
              patient.displayName.isNotEmpty
                  ? patient.displayName[0].toUpperCase() : '?',
              style: t.titleLarge?.copyWith(color: AppColors.sage),
            )),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(patient.displayName, style: t.titleMedium),
            Text(patient.recoveryType,
                style: t.bodySmall?.copyWith(color: AppColors.inkMid)),
          ])),

          // High risk alert badge
          if (patient.highRiskFlag)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.rose.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppColors.rose.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 12, color: AppColors.rose),
                const SizedBox(width: 4),
                Text('Alert',
                    style: t.labelSmall?.copyWith(color: AppColors.rose)),
              ]),
            ),

          RiskBadge(level: patient.latestRiskLevel),
        ]),

        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 14),

        // Stats row
        Row(children: [
          _Stat('🔥', '${patient.currentStreak}d', 'streak'),
          const SizedBox(width: 20),
          _Stat('📓', '${patient.totalEntries}', 'entries'),
          const SizedBox(width: 20),
          _Stat('📅', patient.lastEntryDate ?? '—', 'last entry'),
          const Spacer(),
          Text('Tap to view insights →',
              style: t.labelSmall?.copyWith(color: AppColors.inkLt)),
        ]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String emoji, value, label;
  const _Stat(this.emoji, this.value, this.label);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 5),
        Text(value, style: t.titleSmall),
      ]),
      Text(label,
          style: t.labelSmall?.copyWith(color: AppColors.inkLt)),
    ]);
  }
}

// ── Patient detail bottom sheet ───────────────────────────────────────────────

void _showPatientDetail(
    BuildContext context, WidgetRef ref, TherapistPatient patient) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => ProviderScope(
      parent: ProviderScope.containerOf(context),
      child: _PatientDetailSheet(patient: patient),
    ),
  );
}

class _PatientDetailSheet extends ConsumerWidget {
  final TherapistPatient patient;
  const _PatientDetailSheet({required this.patient});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(patientInsightsProvider(patient.patientId));
    final t        = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize:     0.95,
      minChildSize:     0.4,
      expand:           false,
      builder: (ctx, scroll) => SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.all(28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Handle
          Center(child: Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2)),
          )),

          // Patient header
          Row(children: [
            Text(patient.displayName, style: t.headlineLarge),
            const Spacer(),
            RiskBadge(level: patient.latestRiskLevel),
          ]),
          Text(patient.recoveryType,
              style: t.bodySmall?.copyWith(color: AppColors.inkMid)),
          const SizedBox(height: 6),

          // Stats
          Row(children: [
            _Chip('🔥 ${patient.currentStreak}d streak'),
            const SizedBox(width: 8),
            _Chip('📓 ${patient.totalEntries} entries'),
            if (patient.lastEntryDate != null) ...[
              const SizedBox(width: 8),
              _Chip('📅 ${patient.lastEntryDate}'),
            ],
          ]),
          const SizedBox(height: 24),

          // Check-in button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _sendCheckin(context, ref, patient.patientId),
              icon: const Icon(Icons.send_rounded, size: 15),
              label: const Text('Send Check-in Message'),
            ),
          ),
          const SizedBox(height: 24),

          // Insight history
          Text('Recent Insights', style: t.titleLarge),
          const SizedBox(height: 14),

          insights.when(
            loading: () => Column(children: List.generate(3, (_) =>
                Padding(padding: const EdgeInsets.only(bottom: 10),
                    child: WShimmer(h: 80)))),
            error:   (e, _) => Text('Could not load insights.',
                style: t.bodySmall?.copyWith(color: AppColors.rose)),
            data: (list) {
              if (list.isEmpty) {
                return Text('No insights yet.',
                    style: t.bodyMedium
                        ?.copyWith(color: AppColors.inkMid));
              }
              return Column(children: list.map((i) =>
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _InsightRow(insight: i),
                  )).toList());
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _sendCheckin(
      BuildContext context, WidgetRef ref, String patientId) async {
    try {
      await ref.read(apiProvider).post(
          '/therapist/patients/$patientId/checkin');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Check-in message sent.'),
          backgroundColor: AppColors.sageDk,
        ));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not send check-in.'),
          backgroundColor: AppColors.rose,
        ));
      }
    }
  }
}

class _InsightRow extends StatelessWidget {
  final PatientInsight insight;
  const _InsightRow({required this.insight});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return WCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          RiskBadge(level: insight.relapseRiskLevel),
          const Spacer(),
          Text(
            '${insight.createdAt.day}/${insight.createdAt.month}/'
            '${insight.createdAt.year}',
            style: t.labelSmall,
          ),
        ]),
        const SizedBox(height: 10),
        Text(insight.detectedEmotion,
            style: t.titleSmall
                ?.copyWith(color: AppColors.mist)),
        const SizedBox(height: 4),
        Text(insight.patternInsight,
            style: t.bodySmall?.copyWith(height: 1.5)),
        if (insight.recommendations.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('💡 ${insight.recommendations.first}',
              style: t.bodySmall?.copyWith(
                  color: AppColors.sageDk, height: 1.4)),
        ],
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(label,
        style: Theme.of(context).textTheme.labelSmall),
  );
}