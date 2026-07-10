import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:serenity/core/theme/app_theme.dart';
import 'package:serenity/shared/widgets/web_widgets.dart';
import 'package:serenity/state/providers.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats    = ref.watch(statsProvider);
    final daily    = ref.watch(dailyMessageProvider);
    final insights = ref.watch(insightsProvider);
    final t        = Theme.of(context).textTheme;
    final today    = DateFormat('EEEE, MMMM d').format(DateTime.now());

    return PageScroll(children: [
      // ── Header ────────────────────────────────────────────────────────────
      Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(today, style: t.labelMedium?.copyWith(color: AppColors.inkMid)),
          const SizedBox(height: 4),
          Text('Good to see you.', style: t.displaySmall),
        ]),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: () => context.go('/journal'),
          icon: const Icon(Icons.edit_note_rounded, size: 16),
          label: const Text("Write Today's Entry"),
        ),
      ]),
      const SizedBox(height: 24),

      // ── Daily message ──────────────────────────────────────────────────────
      daily.when(
        loading: () => const WShimmer(h: 110),
        error: (_, __) => const SizedBox.shrink(),
        data: (msg) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.sidebar, Color(0xFF2E5030)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppSpacing.rLg),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('✨  Your daily message',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
              const SizedBox(height: 12),
              Text(msg.message,
                  style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.65)),
            ])),
            if (msg.streak > 0) ...[
              const SizedBox(width: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(children: [
                  const Text('🔥', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 6),
                  Text('${msg.streak}',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                  const Text('days', style: TextStyle(color: Colors.white60, fontSize: 11)),
                ]),
              ),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 22),

      // ── Stats ──────────────────────────────────────────────────────────────
      stats.when(
        loading: () => Row(children: List.generate(4, (i) => Expanded(
            child: Padding(padding: EdgeInsets.only(right: i < 3 ? 12 : 0),
                child: const WShimmer(h: 100))))),
        error: (_, __) => const SizedBox.shrink(),
        data: (s) {
          final (rL, rC) = switch (s.latestRiskLevel.toLowerCase()) {
            'high'     => ('High ⚠️', AppColors.rose),
            'moderate' => ('Moderate', AppColors.amber),
            _          => ('Low ✓', AppColors.sage),
          };
          return Row(children: [
            Expanded(child: StatCard(emoji: '🔥', value: '${s.currentStreak}',
                label: 'day streak', accent: AppColors.amber)),
            const SizedBox(width: 12),
            Expanded(child: StatCard(emoji: '📓', value: '${s.totalEntries}',
                label: 'total entries', accent: AppColors.sage)),
            const SizedBox(width: 12),
            Expanded(child: StatCard(
                emoji: '📊',
                value: s.weeklySummary.averageMood != null
                    ? '${s.weeklySummary.averageMood!.toStringAsFixed(1)}/10' : '—',
                label: 'avg mood', accent: AppColors.mist)),
            const SizedBox(width: 12),
            Expanded(child: StatCard(emoji: '🎯', value: rL, label: 'risk level', accent: rC)),
          ]);
        },
      ),
      const SizedBox(height: 24),

      // ── Bottom two columns ─────────────────────────────────────────────────
      LayoutBuilder(builder: (ctx, box) {
        final wide = box.maxWidth > 680;
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _InsightPanel(insights: insights)),
            const SizedBox(width: 16),
            Expanded(child: _QuickJournalPanel()),
          ]);
        }
        return Column(children: [
          _InsightPanel(insights: insights),
          const SizedBox(height: 16),
          _QuickJournalPanel(),
        ]);
      }),
    ]);
  }
}

class _InsightPanel extends StatelessWidget {
  final AsyncValue<dynamic> insights;
  const _InsightPanel({required this.insights});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return WCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Latest Insight', style: t.headlineSmall),
          const Spacer(),
          WTextBtn(label: 'View all →', onTap: () => GoRouter.of(context).go('/insights')),
        ]),
        const SizedBox(height: 16),
        insights.when(
          loading: () => const WShimmer(h: 100),
          error: (_, __) => Text('No insights yet.',
              style: t.bodyMedium?.copyWith(color: AppColors.inkMid)),
          data: (list) {
            if (list.isEmpty) return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Column(children: [
                const Text('🌱', style: TextStyle(fontSize: 32)),
                const SizedBox(height: 10),
                Text('Write your first journal entryto get AI insights.',
                    style: t.bodySmall?.copyWith(color: AppColors.inkMid),
                    textAlign: TextAlign.center),
              ])),
            );
            final i = list.first;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                RiskBadge(level: i.relapseRiskLevel),
                const Spacer(),
                Text(i.createdAt.toString().substring(0, 10),
                    style: t.labelSmall),
              ]),
              const SizedBox(height: 12),
              _IR(Icons.mood_rounded, AppColors.mist, 'Emotion', i.detectedEmotion),
              const SizedBox(height: 8),
              _IR(Icons.timeline_rounded, AppColors.peach, 'Pattern', i.patternInsight),
              if (i.recommendations.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppColors.sageSurf, borderRadius: BorderRadius.circular(8)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('💡', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(i.recommendations.first,
                        style: t.bodySmall?.copyWith(color: AppColors.sageDk, height: 1.5))),
                  ]),
                ),
              ],
            ]);
          },
        ),
      ]),
    );
  }
}

class _IR extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value;
  const _IR(this.icon, this.color, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 7),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.labelSmall?.copyWith(color: color)),
        Text(value, style: t.bodySmall?.copyWith(height: 1.4)),
      ])),
    ]);
  }
}

class _QuickJournalPanel extends StatelessWidget {
  const _QuickJournalPanel();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final prompts = ['How am I feeling right now?', 'What challenged me today?', 'What am I grateful for?'];
    return WCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Today's Entry", style: t.headlineSmall),
        const SizedBox(height: 8),
        Text("Writing daily supports your recovery journey.",
            style: t.bodySmall?.copyWith(color: AppColors.inkMid, height: 1.55)),
        const SizedBox(height: 16),
        ...prompts.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: WTile(
            onTap: () => GoRouter.of(context).go('/journal'),
            child: Row(children: [
              const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.sage),
              const SizedBox(width: 8),
              Text(p, style: t.bodySmall?.copyWith(color: AppColors.inkMid)),
            ]),
          ),
        )),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => GoRouter.of(context).go('/journal'),
            icon: const Icon(Icons.edit_note_rounded, size: 16),
            label: const Text('Open Journal'),
          ),
        ),
      ]),
    );
  }
}
