import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:serenity/core/theme/app_theme.dart';
import 'package:serenity/shared/widgets/web_widgets.dart';
import 'package:serenity/state/providers.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});
  @override ConsumerState<OnboardingPage> createState() => _State();
}

class _State extends ConsumerState<OnboardingPage> {
  int _step = 0;
  String _recovery = 'both';
  final Set<String> _challenges = {};
  final Set<String> _goals = {};


  @override
  void dispose() {

    super.dispose();
  }

  void _next() { if (_step < 2) setState(() => _step++); else _finish(); }
  void _back() { if (_step > 0) setState(() => _step--); }

  Future<void> _finish() async {
    try {
      final res = await ref.read(apiProvider).post(
  '/onboarding',
  data: {
    'recovery_type': _recovery,
    'challenges': _challenges.toList(),
    'goals': _goals.toList(),
  },
);

      if (res.statusCode == 200 || res.statusCode == 201) {
        await ref.read(storageProvider).setOnboardingDone();
        // Fix: profileProvider doesn't exist in providers.dart — removed
        // Only invalidate providers that actually exist
        ref.invalidate(statsProvider);
        ref.invalidate(insightsProvider);

        if (mounted) context.go('/dashboard');
      } else {
        throw Exception("Failed to save preferences");
      }
    } catch (e) {
      debugPrint("Onboarding failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Something went wrong. Please try again.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(padding: const EdgeInsets.all(48),
          child: Column(children: [
            // Progress
            Row(children: [
              Text('Serenity', style: GoogleFonts.fraunces(
                  fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink)),
              const Spacer(),
              ...List.generate(3, (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.only(left: 7),
                width: i == _step ? 26 : 8, height: 8,
                decoration: BoxDecoration(
                  color: i <= _step ? AppColors.sage : AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              )),
            ]),
            const SizedBox(height: 56),

            // Step content
            Expanded(child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: KeyedSubtree(key: ValueKey(_step), child: [
                _StepType(selected: _recovery, onSelect: (v) => setState(() => _recovery = v)),
                _StepChallenges(selected: _challenges, onToggle: (v) => setState(() {
                  _challenges.contains(v) ? _challenges.remove(v) : _challenges.add(v);
                })),
                // Fix: was missing comma after onToggle callback closing brace
                _StepGoals(
                  selected: _goals,
                  onToggle: (v) => setState(() {
                    _goals.contains(v) ? _goals.remove(v) : _goals.add(v);
                  }),
                ),
              ][_step]),
            )),

            const SizedBox(height: 32),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              if (_step > 0)
                OutlinedButton(onPressed: _back, child: const Text('Back'))
              else
                const SizedBox(),
              SizedBox(height: 46, child: ElevatedButton.icon(
                onPressed: _next,
                icon: Icon(_step < 2 ? Icons.arrow_forward_rounded : Icons.dashboard_rounded, size: 16),
                label: Text(_step < 2 ? 'Continue' : 'Go to Dashboard'),
              )),
            ]),
          ]),
        ),
      )),
    );
  }
}

class _StepType extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _StepType({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final opts = [
      ('addiction','🌿','Addiction Recovery','Managing sobriety and substance use.'),
      ('mental_health','🧠','Mental Health','Anxiety, depression, emotional wellbeing.'),
      ('both','💫','Both','A combined approach to full recovery.'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('What brings you to Serenity?', style: t.displaySmall),
      const SizedBox(height: 6),
      Text("We'll personalise your experience around your needs.",
          style: t.bodyLarge?.copyWith(color: AppColors.inkMid)),
      const SizedBox(height: 28),
      ...opts.map((o) {
        final (val, emoji, title, desc) = o;
        final sel = selected == val;
        return Padding(padding: const EdgeInsets.only(bottom: 10),
          child: WCard(
            color: sel ? AppColors.sageSurf : AppColors.surface,
            onTap: () => onSelect(val),
            child: Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: t.titleMedium),
                Text(desc, style: t.bodySmall),
              ])),
              if (sel) const Icon(Icons.check_circle_rounded, color: AppColors.sage),
            ]),
          ));
      }),
    ]);
  }
}

class _StepChallenges extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const _StepChallenges({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final opts = [
      ('urges','🌊','Urges & Cravings'), ('anxiety','😰','Anxiety'),
      ('loneliness','🫂','Loneliness'), ('stress','⚡','Stress'),
      ('medication_fatigue','💊','Medication Fatigue'), ('stigma','💬','Stigma & Shame'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('What challenges do you face?', style: t.displaySmall),
      const SizedBox(height: 6),
      Text('Select all that apply.', style: t.bodyLarge?.copyWith(color: AppColors.inkMid)),
      const SizedBox(height: 28),
      Expanded(child: GridView.count(crossAxisCount: 3, crossAxisSpacing: 10,
        mainAxisSpacing: 10, childAspectRatio: 2.2,
        children: opts.map((o) {
          final (val, emoji, label) = o;
          final sel = selected.contains(val);
          return WCard(
            color: sel ? AppColors.sageSurf : AppColors.surface,
            onTap: () => onToggle(val),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: t.titleSmall?.copyWith(
                  color: sel ? AppColors.sageDk : AppColors.ink), overflow: TextOverflow.ellipsis)),
              if (sel) const Icon(Icons.check_rounded, size: 14, color: AppColors.sage),
            ]),
          );
        }).toList(),
      )),
    ]);
  }
}

class _StepGoals extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _StepGoals({
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final goals = [
      'Stay sober daily',
      'Improve my mental health',
      'Build healthy habits',
      'Strengthen my support network',
      'Reconnect with what matters',
      'Reduce relapse risk'
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What are your goals?', style: t.displaySmall),
        const SizedBox(height: 6),
        Text(
          'Choose what matters most right now.',
          style: t.bodyLarge?.copyWith(color: AppColors.inkMid),
        ),
        const SizedBox(height: 28),
        Expanded(
          child: ListView(
            children: [
              ...goals.map((g) {
                final sel = selected.contains(g);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: WCard(
                    color: sel ? AppColors.sageSurf : AppColors.surface,
                    onTap: () => onToggle(g),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                    child: Row(
                      children: [
                        Icon(
                          sel ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(g),
                      ],
                    ),
                  ),
                );
              }),


            ],
          ),
        ),
      ],
    );
  }
}