import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenity/core/theme/app_theme.dart';
import 'package:serenity/models/app_models.dart';
import 'package:serenity/shared/widgets/web_widgets.dart';
import 'package:serenity/state/providers.dart';

class ProgressPage extends ConsumerWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use a refreshable provider
    final statsAsync = ref.watch(statsProvider);
    final chartAsync = ref.watch(chartProvider);
    final t = Theme.of(context).textTheme;

    return statsAsync.when(
      loading: () => PageScroll(children: [
        const WShimmer(h: 150),
        const SizedBox(height: 20),
        Row(children: List.generate(4, (i) => Expanded(
            child: Padding(padding: EdgeInsets.only(right: i < 3 ? 12 : 0),
                child: const WShimmer(h: 100))))),
        const SizedBox(height: 20),
        const WShimmer(h: 260),
      ]),
      error: (err, stack) {
        print('❌ [PROGRESS] Error loading stats: $err');
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load progress.', style: t.bodyMedium),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  print('🔄 [PROGRESS] Retry loading');
                  ref.invalidate(statsProvider);
                  ref.invalidate(chartProvider);
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      },
      data: (s) {
        print('📊 [PROGRESS] Stats loaded: streak=${s.currentStreak}, entries=${s.totalEntries}');

        return PageScroll(children: [
          _StreakHero(stats: s),
          const SizedBox(height: 22),
          _StatRow(stats: s),
          const SizedBox(height: 22),

          // Charts row
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: chartAsync.when(
              loading: () => const WShimmer(h: 260),
              error: (err, stack) {
                print('❌ [PROGRESS] Error loading chart: $err');
                return const WShimmer(h: 260);
              },
              data: (points) {
                print('📊 [PROGRESS] Chart data points: ${points.length}');
                return _MoodChart(dataPoints: points);
              },
            )),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: chartAsync.when(
              loading: () => const WShimmer(h: 260),
              error: (err, stack) => const WShimmer(h: 260),
              data: (points) => _WeeklyBar(
                  dataPoints: points, stats: s),
            )),
          ]),

          if (s.badges.isNotEmpty) ...[
            const SizedBox(height: 22),
            _Badges(badges: s.badges),
          ],
        ]);
      },
    );
  }
}

// ── Streak hero ───────────────────────────────────────────────────────────────

class _StreakHero extends StatelessWidget {
  final ProgressStats stats;
  const _StreakHero({required this.stats});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [AppColors.sidebar, Color(0xFF2E5030)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(AppSpacing.rLg),
      ),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Current Streak',
              style: t.labelMedium?.copyWith(color: Colors.white60)),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${stats.currentStreak}',
                style: t.displayLarge?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 6),
              child: Text('days',
                  style: t.headlineMedium?.copyWith(color: Colors.white70)),
            ),
          ]),
          Text('Longest: ${stats.longestStreak} days',
              style: t.bodySmall?.copyWith(color: Colors.white54)),
        ]),
        const Spacer(),
        Column(children: [
          const Text('🔥', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text('${stats.weeklySummary.entriesThisWeek}',
                  style: t.headlineMedium?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              Text('this week',
                  style: t.labelSmall?.copyWith(color: Colors.white60)),
            ]),
          ),
        ]),
      ]),
    );
  }
}

// ── Stat row ──────────────────────────────────────────────────────────────────

class _StatRow extends StatelessWidget {
  final ProgressStats stats;
  const _StatRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final (rL, rC) = switch (stats.latestRiskLevel.toLowerCase()) {
      'high'     => ('High ⚠️', AppColors.rose),
      'moderate' => ('Moderate', AppColors.amber),
      _          => ('Low ✓', AppColors.sage),
    };
    return Row(children: [
      Expanded(child: StatCard(
          emoji: '📓', value: '${stats.totalEntries}', label: 'journal entries')),
      const SizedBox(width: 12),
      Expanded(child: StatCard(
          emoji: '🏆', value: '${stats.longestStreak}d', label: 'best streak')),
      const SizedBox(width: 12),
      Expanded(child: StatCard(
          emoji: '📊',
          value: stats.weeklySummary.averageMood != null
              ? '${stats.weeklySummary.averageMood!.toStringAsFixed(1)}/10' : '—',
          label: 'avg mood', accent: AppColors.mist)),
      const SizedBox(width: 12),
      Expanded(child: StatCard(
          emoji: '🎯', value: rL, label: 'risk level', accent: rC)),
    ]);
  }
}

// ── Mood line chart ───────────────────────────────────────────────────────────────

class _MoodChart extends StatelessWidget {
  final List<ChartDataPoint> dataPoints;
  const _MoodChart({required this.dataPoints});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final moodPoints = dataPoints
        .where((p) => p.avgMood != null)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final last7 = moodPoints.length > 7
        ? moodPoints.sublist(moodPoints.length - 7)
        : moodPoints;

    if (last7.isEmpty) {
      return WCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WSectionHead(title: 'Mood This Week', sub: 'Scale 1–10'),
          const SizedBox(height: 60),
          Center(child: Text('No mood data yet.\nWrite entries with a mood score.',
              style: t.bodySmall?.copyWith(
                  color: AppColors.inkMid, height: 1.6),
              textAlign: TextAlign.center)),
          const SizedBox(height: 60),
        ],
      ));
    }

    final spots = last7.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.avgMood!))
        .toList();

    final dayLabels = last7
        .map((p) => DateFormat('E').format(p.date))
        .toList();

    return WCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WSectionHead(title: 'Mood This Week', sub: 'Scale 1–10'),
        const SizedBox(height: 24),
        SizedBox(height: 200, child: LineChart(LineChartData(
          gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 2,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AppColors.border, strokeWidth: 1)),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, interval: 2, reservedSize: 28,
                getTitlesWidget: (v, _) =>
                    Text('${v.toInt()}', style: t.labelSmall))),
            rightTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= dayLabels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(dayLabels[idx], style: t.labelSmall));
                })),
          ),
          borderData: FlBorderData(show: false),
          minY: 0, maxY: 10,
          lineBarsData: [LineChartBarData(
            spots: spots, isCurved: true, curveSmoothness: 0.4,
            color: AppColors.sage, barWidth: 2.5, isStrokeCapRound: true,
            dotData: FlDotData(getDotPainter: (_, __, ___, ____) =>
                FlDotCirclePainter(radius: 4, color: AppColors.sage,
                    strokeWidth: 2, strokeColor: Colors.white)),
            belowBarData: BarAreaData(show: true,
                gradient: LinearGradient(
                    colors: [
                      AppColors.sage.withOpacity(0.15),
                      AppColors.sage.withOpacity(0.0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter)),
          )],
        ))),
      ],
    ));
  }
}

// ── Weekly bar chart ──────────────────────────────────────────────────────────────

class _WeeklyBar extends StatelessWidget {
  final List<ChartDataPoint> dataPoints;
  final ProgressStats stats;
  const _WeeklyBar({required this.dataPoints, required this.stats});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final now   = DateTime.now();
    final weeks = List.generate(4, (i) {
      final weekStart = now.subtract(Duration(days: now.weekday - 1 + (3 - i) * 7));
      final weekEnd   = weekStart.add(const Duration(days: 6));
      final count     = dataPoints
          .where((p) => !p.date.isBefore(weekStart) && !p.date.isAfter(weekEnd))
          .fold(0, (sum, p) => sum + p.entryCount);
      return count;
    });

    final maxY  = (weeks.reduce((a, b) => a > b ? a : b) + 1).toDouble();
    final labels = ['Wk1', 'Wk2', 'Wk3', 'Now'];

    return WCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WSectionHead(title: 'Weekly Entries', sub: 'Last 4 weeks'),
        const SizedBox(height: 24),
        SizedBox(height: 200, child: BarChart(BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY < 1 ? 5 : maxY,
          gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AppColors.border, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 24, interval: 1,
                getTitlesWidget: (v, _) =>
                    Text('${v.toInt()}', style: t.labelSmall))),
            rightTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) => Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(labels[v.toInt()], style: t.labelSmall)))),
          ),
          barGroups: weeks.asMap().entries.map((e) =>
              BarChartGroupData(x: e.key, barRods: [
                BarChartRodData(
                  toY: e.value.toDouble(),
                  color: e.key == 3 ? AppColors.sage : AppColors.sageLt,
                  width: 26,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6)),
                ),
              ])).toList(),
        ))),
      ],
    ));
  }
}

// ── Badges ────────────────────────────────────────────────────────────────────

class _Badges extends StatelessWidget {
  final List<BadgeItem> badges;
  const _Badges({required this.badges});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      WSectionHead(title: 'Achievements', sub: '${badges.length} earned'),
      const SizedBox(height: 14),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 280,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.8),
        itemCount: badges.length,
        itemBuilder: (ctx, i) => WCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: AppColors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(7)),
                child: const Text('🏅',
                    style: TextStyle(fontSize: 18))),
            const SizedBox(width: 10),
            Expanded(child: Text(badges[i].label,
                style: t.titleSmall,
                overflow: TextOverflow.ellipsis)),
            const Icon(Icons.check_circle_rounded,
                color: AppColors.amber, size: 17),
          ]),
        ),
      ),
    ]);
  }
}