import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenity/core/theme/app_theme.dart';
import 'package:serenity/shared/widgets/web_widgets.dart';
import 'package:serenity/state/providers.dart'; // Fix: correct import — has both apiProvider and statsProvider

class CrisisPage extends ConsumerWidget {
  const CrisisPage({super.key});

  Future<void> _sendEmergencyAlert(WidgetRef ref) async {
    try {
      await ref.read(apiProvider).post('/user/emergency-alert');
    } catch (e) {
      debugPrint("Emergency alert failed: $e");
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.ink),
          onPressed: () => context.go('/dashboard'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [

                /// CALM
                const Text('🙏', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text('You are safe here.', style: t.displaySmall),
                const SizedBox(height: 10),
                Text(
                  "Pause. Breathe. This moment will pass.",
                  textAlign: TextAlign.center,
                  style: t.bodyLarge?.copyWith(color: AppColors.inkMid),
                ),

                const SizedBox(height: 30),
                const _BreathingCard(),

                const SizedBox(height: 30),

                /// EMERGENCY ACTION
                WCard(
                  color: AppColors.rose.withOpacity(0.1),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.emergency, color: AppColors.rose, size: 30),
                      const SizedBox(height: 10),
                      Text("Alert someone you trust", style: t.titleLarge),
                      const SizedBox(height: 8),
                      const Text(
                        "We will notify your emergency contact immediately.",
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _sendEmergencyAlert(ref),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.rose,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: const Text("Send Alert Now"),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                /// HOTLINES
                const _HotlineCard(
                  emoji: '📞',
                  label: 'Call 999',
                  subtitle: '24/7 confidential support',
                ),

                const SizedBox(height: 20),

                /// AI SUPPORT
                WCard(
                  child: ListTile(
                    leading: const Icon(Icons.auto_awesome, color: AppColors.sage),
                    title: const Text("Talk to Serenity AI"),
                    subtitle: const Text("You're not alone. Talk now."),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/journal'),
                  ),
                ),

                const SizedBox(height: 30),

                /// WHY — profileProvider doesn't exist in providers.dart; static chips as fallback
                Text("Remember why you started", style: t.titleMedium),
                const SizedBox(height: 10),
                const Wrap(
                  spacing: 10,
                  children: [
                    Chip(label: Text('Stay strong')),
                    Chip(label: Text('One day at a time')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _BreathingCard
// ─────────────────────────────────────────────
class _BreathingCard extends StatefulWidget {
  const _BreathingCard();

  @override
  State<_BreathingCard> createState() => _BreathingCardState();
}

class _BreathingCardState extends State<_BreathingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  static const _phases = ['Breathe in…', 'Hold…', 'Breathe out…'];
  int _phaseIndex = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() => _phaseIndex = (_phaseIndex + 1) % _phases.length);
          _ctrl.reverse();
        } else if (status == AnimationStatus.dismissed) {
          setState(() => _phaseIndex = (_phaseIndex + 1) % _phases.length);
          _ctrl.forward();
        }
      });

    _scale = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WCard(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      child: Column(
        children: [
          Text(_phases[_phaseIndex], style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          ScaleTransition(
            scale: _scale,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.sage.withOpacity(0.25),
                border: Border.all(color: AppColors.sage, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Follow the circle to calm your breath.', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _HotlineCard
// ─────────────────────────────────────────────
class _HotlineCard extends StatelessWidget {
  const _HotlineCard({
    required this.emoji,
    required this.label,
    required this.subtitle,
  });

  final String emoji;
  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return WCard(
      child: ListTile(
        leading: Text(emoji, style: const TextStyle(fontSize: 28)),
        title: Text(label),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {},
      ),
    );
  }
}