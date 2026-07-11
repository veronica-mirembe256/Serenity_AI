import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenity/core/theme/app_theme.dart';
import 'package:serenity/models/app_models.dart';
import 'package:serenity/shared/widgets/web_widgets.dart';
import 'package:serenity/state/providers.dart';

class InsightsPage extends ConsumerStatefulWidget {
  const InsightsPage({super.key});
  @override ConsumerState<InsightsPage> createState() => _State();
}

class _State extends ConsumerState<InsightsPage> {
  InsightItem? _sel;

  @override
  Widget build(BuildContext context) {
    // Use a refreshable provider - this will auto-refresh when invalidated
    final insightsAsync = ref.watch(insightsProvider);
    final t = Theme.of(context).textTheme;

    return SizedBox.expand(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // List panel
        SizedBox(width: 360,
          child: Container(
            decoration: BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.border))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                child: Row(
                  children: [
                    Text('All Insights', style: t.headlineSmall),
                    const Spacer(),
                    // Add a refresh button
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      onPressed: () {
                        print('🔄 [INSIGHTS] Manual refresh triggered');
                        ref.invalidate(insightsProvider);
                      },
                      tooltip: 'Refresh insights',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: insightsAsync.when(
                loading: () => ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: 5,
                  itemBuilder: (_, __) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: WShimmer(h: 64)),
                ),
                error: (err, stack) {
                  print('❌ [INSIGHTS] Error: $err');
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Failed to load insights.', style: t.bodyMedium),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            print('🔄 [INSIGHTS] Retry fetch');
                            ref.invalidate(insightsProvider);
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                },
                data: (list) {
                  print('📊 [INSIGHTS] Displaying ${list.length} insights');
                  if (list.isEmpty) {
                    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('🌱', style: TextStyle(fontSize: 32)),
                      const SizedBox(height: 10),
                      Text('No insights yet.', style: t.bodyMedium?.copyWith(color: AppColors.inkMid)),
                      const SizedBox(height: 8),
                      Text('Write a journal entry to get insights.',
                          style: t.bodySmall?.copyWith(color: AppColors.inkLt)),
                    ]));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    itemCount: list.length,
                    itemBuilder: (ctx, i) => _ListTile(
                      item: list[i],
                      selected: _sel?.id == list[i].id,
                      onTap: () => setState(() => _sel = list[i]),
                    ),
                  );
                },
              )),
            ]),
          ),
        ),
        // Detail panel
        Expanded(child: _sel == null ? _DetailPlaceholder() : _DetailPanel(item: _sel!)),
      ]),
    );
  }
}

class _ListTile extends StatefulWidget {
  final InsightItem item;
  final bool selected;
  final VoidCallback onTap;
  const _ListTile({required this.item, required this.selected, required this.onTap});

  @override State<_ListTile> createState() => _ListTileState();
}
class _ListTileState extends State<_ListTile> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = switch (widget.item.relapseRiskLevel.toLowerCase()) {
      'high' => AppColors.rose, 'moderate' => AppColors.amber, _ => AppColors.sage,
    };
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: widget.selected ? AppColors.sageSurf : _h ? AppColors.surfaceAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: widget.selected ? AppColors.sageLt : Colors.transparent),
          ),
          child: Row(children: [
            Container(width: 3, height: 36,
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('MMM d, yyyy').format(widget.item.createdAt),
                  style: t.labelMedium),
              const SizedBox(height: 3),
              Text(widget.item.detectedEmotion,
                  style: t.bodySmall?.copyWith(color: AppColors.inkMid),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            RiskBadge(level: widget.item.relapseRiskLevel),
          ]),
        ),
      ),
    );
  }
}

class _DetailPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(color: AppColors.surfaceAlt, child: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🔍', style: TextStyle(fontSize: 36)),
        const SizedBox(height: 12),
        Text('Select an insight to view details',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.inkMid)),
      ]),
    ));
  }
}

class _DetailPanel extends StatelessWidget {
  final InsightItem item;
  const _DetailPanel({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      color: AppColors.surfaceAlt,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(DateFormat('EEEE, MMMM d, yyyy').format(item.createdAt),
                    style: t.labelMedium?.copyWith(color: AppColors.inkLt)),
                const SizedBox(height: 4),
                Text('Insight Detail', style: t.headlineMedium),
              ]),
              const Spacer(),
              RiskBadge(level: item.relapseRiskLevel),
            ]),
            const SizedBox(height: 22),
            WCard(color: AppColors.sageSurf, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('💚  Encouragement', style: t.labelMedium?.copyWith(color: AppColors.sageDk)),
              const SizedBox(height: 8),
              Text(item.encouragement,
                  style: t.bodyLarge?.copyWith(color: AppColors.sageDk, height: 1.65, fontStyle: FontStyle.italic)),
            ])),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: WCard(child: _DR(Icons.mood_rounded, AppColors.mist, 'Emotion', item.detectedEmotion))),
              const SizedBox(width: 12),
              Expanded(child: WCard(child: _DR(Icons.timeline_rounded, AppColors.peach, 'Pattern', item.patternInsight))),
            ]),
            if (item.recommendations.isNotEmpty) ...[
              const SizedBox(height: 14),
              WCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.lightbulb_outline_rounded, size: 17, color: AppColors.amber),
                  const SizedBox(width: 7),
                  Text('Recommendations', style: t.titleSmall),
                ]),
                const SizedBox(height: 12),
                ...item.recommendations.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 20, height: 20, margin: const EdgeInsets.only(right: 9, top: 1),
                      decoration: BoxDecoration(color: AppColors.sageSurf, borderRadius: BorderRadius.circular(5)),
                      child: Center(child: Text('${e.key+1}',
                          style: t.labelSmall?.copyWith(color: AppColors.sage))),
                    ),
                    Expanded(child: Text(e.value, style: t.bodyMedium?.copyWith(height: 1.55))),
                  ]),
                )),
              ])),
            ],
          ]),
        ),
      ),
    );
  }
}

class _DR extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value;
  const _DR(this.icon, this.color, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 6),
        Text(label, style: t.labelMedium?.copyWith(color: color))]),
      const SizedBox(height: 6),
      Text(value, style: t.bodySmall?.copyWith(height: 1.5)),
    ]);
  }
}
