import 'package:flutter/material.dart';
import 'package:serenity/core/theme/app_theme.dart';

/// Scrollable page area. Uses SingleChildScrollView ONLY — no Scrollbar.
class PageScroll extends StatelessWidget {
  final List<Widget> children;
  final double maxW;
  const PageScroll({super.key, required this.children, this.maxW = 1200});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ),
    );
  }
}

/// Card — GestureDetector only, never InkWell
class WCard extends StatefulWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? color;
  final VoidCallback? onTap;
  final double radius;
  const WCard({super.key, required this.child, this.padding, this.color, this.onTap, this.radius = 14});

  @override State<WCard> createState() => _WCardState();
}
class _WCardState extends State<WCard> {
  bool _h = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: widget.padding ?? const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: widget.color ?? AppColors.surface,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: _h && widget.onTap != null ? AppColors.sage.withOpacity(0.5) : AppColors.border),
          boxShadow: _h && widget.onTap != null
              ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))]
              : [],
        ),
        child: widget.child,
      ),
    ),
  );
}

/// Clickable row/tile — GestureDetector only, never InkWell
class WTile extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final EdgeInsets padding;
  final BorderRadius? radius;
  const WTile({super.key, required this.child, required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    this.radius});

  @override State<WTile> createState() => _WTileState();
}
class _WTileState extends State<WTile> {
  bool _h = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: widget.padding,
        decoration: BoxDecoration(
          color: _h ? AppColors.sageSurf : AppColors.surfaceAlt,
          borderRadius: widget.radius ?? BorderRadius.circular(8),
          border: Border.all(color: _h ? AppColors.sageLt : AppColors.border),
        ),
        child: widget.child,
      ),
    ),
  );
}

/// Stat card
class StatCard extends StatelessWidget {
  final String emoji, value, label;
  final Color? accent;
  const StatCard({super.key, required this.emoji, required this.value, required this.label, this.accent});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return WCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const Spacer(),
          if (accent != null) Container(width: 8, height: 8,
              decoration: BoxDecoration(color: accent!, shape: BoxShape.circle)),
        ]),
        const SizedBox(height: 12),
        Text(value, style: t.headlineLarge),
        const SizedBox(height: 3),
        Text(label, style: t.bodySmall),
      ]),
    );
  }
}

/// Risk badge
class RiskBadge extends StatelessWidget {
  final String level;
  const RiskBadge({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = switch (level.toLowerCase()) {
      'high'     => (AppColors.rose,  'High Risk',  Icons.warning_amber_rounded),
      'moderate' => (AppColors.amber, 'Moderate',   Icons.info_outline_rounded),
      _          => (AppColors.sage,  'Low Risk',   Icons.check_circle_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Mood selector — GestureDetector only
class WMoodPicker extends StatelessWidget {
  final int? selected;
  final ValueChanged<int> onSelect;
  const WMoodPicker({super.key, this.selected, required this.onSelect});

  static const _m = [(1,'😔','Low'),(3,'😕','Meh'),(5,'😐','Okay'),(7,'🙂','Good'),(10,'😊','Great')];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(children: _m.map((m) {
      final (score, emoji, label) = m;
      final sel = selected == score;
      final color = AppColors.moods[(score/10*4).round().clamp(0,4)];
      return Expanded(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: GestureDetector(
          onTap: () => onSelect(score),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: sel ? color.withOpacity(0.15) : AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: sel ? color : AppColors.border, width: sel ? 1.5 : 1),
              ),
              child: Column(children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 4),
                Text(label, style: t.labelSmall?.copyWith(
                    color: sel ? color : AppColors.inkLt,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
              ]),
            ),
          ),
        ),
      ));
    }).toList());
  }
}

/// Shimmer placeholder
class WShimmer extends StatelessWidget {
  final double h;
  final double? w;
  const WShimmer({super.key, this.h = 80, this.w});

  @override
  Widget build(BuildContext context) => Container(
    height: h, width: w,
    decoration: BoxDecoration(
      color: AppColors.border.withOpacity(0.55),
      borderRadius: BorderRadius.circular(AppSpacing.r),
    ),
  );
}

/// Section header
class WSectionHead extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget? action;
  const WSectionHead({super.key, required this.title, this.sub, this.action});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: t.headlineSmall),
        if (sub != null) ...[const SizedBox(height: 2), Text(sub!, style: t.bodySmall)],
      ])),
      if (action != null) action!,
    ]);
  }
}

/// Text link button
class WTextBtn extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const WTextBtn({super.key, required this.label, required this.onTap});

  @override State<WTextBtn> createState() => _WTextBtnState();
}
class _WTextBtnState extends State<WTextBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: Text(widget.label, style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: _h ? AppColors.sageDk : AppColors.sage, fontWeight: FontWeight.w600)),
    ),
  );
}
