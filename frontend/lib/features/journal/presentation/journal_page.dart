import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenity/core/constants/app_constants.dart';
import 'package:serenity/core/theme/app_theme.dart';
import 'package:serenity/models/app_models.dart';
import 'package:serenity/shared/widgets/web_widgets.dart';
import 'package:serenity/state/providers.dart';

class JournalPage extends ConsumerStatefulWidget {
  const JournalPage({super.key});
  @override
  ConsumerState<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends ConsumerState<JournalPage> {
  final _ctrl = TextEditingController();
  int? _mood;
  int _chars = 0;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() => _chars = _ctrl.text.length));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.length < 10) {
      _showError('Please write a bit more (at least 10 characters).');
      return;
    }

    // Uses streaming endpoint — live status updates shown in _EmptyPanel
    final success = await ref.read(journalProvider.notifier).submit(text, _mood);

    if (!mounted) return;

    if (success) {
      final result = ref.read(journalProvider).result;
      if (result?.relapseRiskLevel == AppConstants.riskHigh) {
        context.push('/crisis');
      }
    } else {
      final errorMsg = ref.read(journalProvider).error ?? 'Analysis failed';
      _showError(errorMsg);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: AppColors.rose,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _reset() {
    _ctrl.clear();
    setState(() => _mood = null);
    ref.read(journalProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final journal = ref.watch(journalProvider);
    final result  = journal.result;
    final t       = Theme.of(context).textTheme;

    return SizedBox.expand(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        // ── Editor panel ──────────────────────────────────────────────────────
        Expanded(
          flex: 5,
          child: Container(
            decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.border))),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(36),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Today's Journal", style: t.displaySmall),
                const SizedBox(height: 4),
                Text("Your private space. Write freely.",
                    style: t.bodyMedium?.copyWith(color: AppColors.inkMid)),
                const SizedBox(height: 28),

                // Mood picker
                WCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('How are you feeling?',
                        style: t.titleSmall?.copyWith(color: AppColors.inkMid)),
                    const SizedBox(height: 12),
                    WMoodPicker(
                        selected: _mood,
                        onSelect: (v) => setState(() => _mood = v)),
                  ]),
                ),
                const SizedBox(height: 16),

                // Text field
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.r),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    TextField(
                      controller: _ctrl,
                      maxLines: 12,
                      minLines: 8,
                      enabled: !journal.isSubmitting && result == null,
                      decoration: InputDecoration(
                        hintText:
                            "What's on your mind today?\n\nThere are no right or wrong answers...",
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.all(20),
                        hintStyle: t.bodyLarge
                            ?.copyWith(color: AppColors.inkLt, height: 1.7),
                      ),
                      style: t.bodyLarge?.copyWith(height: 1.7),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 16, 10),
                      child: Text('$_chars chars',
                          style: t.labelSmall?.copyWith(color: AppColors.inkLt)),
                    ),
                  ]),
                ),

                if (journal.error != null) ...[
                  const SizedBox(height: 10),
                  Text(journal.error!,
                      style: t.bodySmall?.copyWith(color: AppColors.rose)),
                ],
                const SizedBox(height: 20),

                // Actions
                Row(children: [
                  if (result != null)
                    OutlinedButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text('New Entry'),
                    ),
                  const Spacer(),
                  SizedBox(
                    width: 200,
                    child: ElevatedButton.icon(
                      onPressed: result == null && !journal.isSubmitting
                          ? _submit : null,
                      icon: journal.isSubmitting
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome_rounded, size: 15),
                      label: Text(journal.isSubmitting
                          ? 'Analysing...' : 'Analyse Entry'),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),

        // ── Result / status panel ─────────────────────────────────────────────
        Expanded(
          flex: 4,
          child: result == null
              ? _EmptyPanel(
                  loading:     journal.isSubmitting,
                  statusLabel: journal.streamStatusLabel,
                )
              : _ResultPanel(result: result),
        ),
      ]),
    );
  }
}

// ── Empty / streaming status panel ───────────────────────────────────────────

class _EmptyPanel extends StatelessWidget {
  final bool loading;
  final String? statusLabel;
  const _EmptyPanel({required this.loading, this.statusLabel});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    // Pipeline stage labels and their icons
    const stages = [
      ('Analysing your entry…',        Icons.search_rounded),
      ('Reflecting on patterns…',      Icons.psychology_rounded),
      ('Building your support plan…',  Icons.favorite_rounded),
      ('Finalising insights…',         Icons.auto_awesome_rounded),
    ];

    return Container(
      color: AppColors.surfaceAlt,
      child: Center(
        child: loading
            ? Padding(
                padding: const EdgeInsets.all(40),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(
                    width: 44, height: 44,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.sage)),
                  const SizedBox(height: 24),

                  // Live status label from streaming events
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      statusLabel ?? 'Sending…',
                      key: ValueKey(statusLabel),
                      style: t.titleMedium?.copyWith(color: AppColors.ink),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Stage indicators
                  ...stages.map((s) {
                    final (label, icon) = s;
                    final isActive = statusLabel == label;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.sageSurf
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isActive
                                ? AppColors.sageLt
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(icon,
                              size: 16,
                              color: isActive
                                  ? AppColors.sage
                                  : AppColors.inkLt),
                          const SizedBox(width: 10),
                          Text(label,
                              style: t.bodySmall?.copyWith(
                                color: isActive
                                    ? AppColors.sageDk
                                    : AppColors.inkLt,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              )),
                        ]),
                      ),
                    );
                  }),
                ]),
              )
            : Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('✨', style: TextStyle(fontSize: 38)),
                const SizedBox(height: 14),
                Text('AI insights will appear here',
                    style: t.headlineSmall?.copyWith(color: AppColors.inkMid)),
                const SizedBox(height: 6),
                const Text('Write your entry and press Analyse.',
                    style: TextStyle(fontSize: 12, color: AppColors.inkLt)),
              ]),
      ),
    );
  }
}

// ── Result panel ──────────────────────────────────────────────────────────────

class _ResultPanel extends StatelessWidget {
  final JournalResponse result;
  const _ResultPanel({required this.result});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final riskColor = switch (result.relapseRiskLevel) {
      'high'     => AppColors.rose,
      'moderate' => AppColors.amber,
      _          => AppColors.sage,
    };

    return Container(
      color: AppColors.surfaceAlt,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Header
         Row(children: [
  Flexible(
    child: Text('AI Insight',
      style: t.headlineMedium,
      overflow: TextOverflow.ellipsis,
    ),
  ),
  const SizedBox(width: 8),
  RiskBadge(level: result.relapseRiskLevel),
]),
          if (result.streak > 0) ...[
            const SizedBox(height: 4),
     Flexible(
  child: Text('🔥 ${result.streak}-day streak!',
      style: t.bodySmall?.copyWith(
          color: AppColors.sage, fontWeight: FontWeight.w600),
      overflow: TextOverflow.ellipsis),
),
          ],
          const SizedBox(height: 20),

          // Emotion + Pattern
          WCard(child: Column(children: [
            _IR(Icons.mood_rounded, AppColors.mist,
                'Detected Emotion', result.detectedEmotion),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            _IR(Icons.timeline_rounded, AppColors.peach,
                'Pattern Insight', result.patternInsight),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            _IR(Icons.warning_amber_rounded, riskColor,
                'Relapse Risk', result.relapseRiskLevel.toUpperCase()),
          ])),
          const SizedBox(height: 16),

          // Encouragement
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.sageSurf,
              borderRadius: BorderRadius.circular(AppSpacing.r),
              border: Border.all(color: AppColors.sageLt),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('💙', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(child: Text(result.encouragementMessage,
                  style: t.bodyMedium?.copyWith(
                      color: AppColors.sageDk, height: 1.55))),
            ]),
          ),
          const SizedBox(height: 16),

          // Recommendations
          if (result.recommendations.isNotEmpty) ...[
            Text('Recommendations', style: t.titleSmall),
            const SizedBox(height: 10),
            ...result.recommendations.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.check_circle_outline_rounded,
                    size: 15, color: AppColors.sage),
                const SizedBox(width: 8),
                Expanded(child: Text(r,
                    style: t.bodySmall?.copyWith(height: 1.5))),
              ]),
            )),
            const SizedBox(height: 8),
          ],

          // Alternative suggestions
          if (result.alternativeSuggestions.isNotEmpty) ...[
            Text('Try instead', style: t.titleSmall),
            const SizedBox(height: 10),
            ...result.alternativeSuggestions.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb_outline_rounded,
                    size: 15, color: AppColors.amber),
                const SizedBox(width: 8),
                Expanded(child: Text(s,
                    style: t.bodySmall?.copyWith(height: 1.5))),
              ]),
            )),
            const SizedBox(height: 8),
          ],

          // Medication / stigma notes
          if (result.medicationSupport != null) ...[
            _InfoBanner(
                icon: Icons.medication_outlined,
                color: AppColors.mist,
                text: result.medicationSupport!),
            const SizedBox(height: 8),
          ],
          if (result.stigmaReassurance != null) ...[
            _InfoBanner(
                icon: Icons.favorite_border_rounded,
                color: AppColors.rose,
                text: result.stigmaReassurance!),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => GoRouter.of(context).go('/insights'),
              icon: const Icon(Icons.insights_rounded, size: 15),
              label: const Text('View All Insights'),
            ),
          ),
        ]),
      ),
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
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.labelMedium?.copyWith(color: color)),
        const SizedBox(height: 3),
        Text(value, style: t.bodySmall?.copyWith(height: 1.5)),
      ])),
    ]);
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoBanner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color, height: 1.5))),
      ]),
    );
  }
}