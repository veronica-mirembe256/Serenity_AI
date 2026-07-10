import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:serenity/core/theme/app_theme.dart';
import 'package:serenity/state/providers.dart';

class DashboardShell extends ConsumerStatefulWidget {
  final Widget child;
  const DashboardShell({super.key, required this.child});

  @override ConsumerState<DashboardShell> createState() => _State();
}

class _State extends ConsumerState<DashboardShell> {
  bool _col = false;

  static const _nav = [
    ('/dashboard', Icons.home_rounded,         'Home'),
    ('/journal',   Icons.edit_note_rounded,    'Journal'),
    ('/insights',  Icons.auto_awesome_rounded, 'Insights'),
    ('/progress',  Icons.bar_chart_rounded,    'Progress'),
    ('/settings',  Icons.settings_outlined,    'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final w   = MediaQuery.of(context).size.width;
    final col = _col || w < 1100;
    final sw  = col ? AppSpacing.sidebarWMin : AppSpacing.sidebarW;
    final loc = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Row(children: [
        // ── Sidebar ────────────────────────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: sw,
          decoration: const BoxDecoration(
            color: AppColors.sidebar,
            border: Border(right: BorderSide(color: Color(0xFF2A3D2C))),
          ),
          child: Column(children: [
            // Logo row
            SizedBox(height: AppSpacing.topbarH,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: col ? 16 : 18),
                child: Row(children: [
                  Container(width: 30, height: 30,
                    decoration: BoxDecoration(color: AppColors.sage, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.eco_rounded, color: Colors.white, size: 17)),
                  if (!col) ...[
                    const SizedBox(width: 10),
                    Text('Serenity', style: GoogleFonts.fraunces(
                        color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
                  ],
                  const Spacer(),
                  if (!col) _MenuBtn(onTap: () => setState(() => _col = !_col)),
                ]),
              ),
            ),

            // Nav
            Expanded(child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: _nav.map((n) {
                final (path, icon, label) = n;
                return _NavItem(
                  icon: icon, label: label,
                  active: loc.startsWith(path),
                  col: col,
                  onTap: () => context.go(path),
                );
              }).toList(),
            )),

            // Bottom actions
            Padding(padding: const EdgeInsets.all(8), child: Column(children: [
              _NavItem(icon: Icons.favorite_border_rounded, label: 'Crisis',
                  active: false, col: col, color: AppColors.rose,
                  onTap: () => context.push('/crisis')),
              const SizedBox(height: 4),
              _NavItem(icon: Icons.logout_rounded, label: 'Sign Out',
                  active: false, col: col,
                  onTap: () => ref.read(authProvider.notifier).logout()),
            ])),

            if (col) Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
              child: _MenuBtn(onTap: () => setState(() => _col = !_col)),
            ),
            const SizedBox(height: 8),
          ]),
        ),

        // ── Main ───────────────────────────────────────────────────────────
        Expanded(child: Column(children: [
          _Topbar(title: _title(loc)),
          Expanded(child: widget.child),
        ])),
      ]),
    );
  }

  String _title(String loc) {
    if (loc.startsWith('/dashboard')) return 'Dashboard';
    if (loc.startsWith('/journal'))   return 'Journal';
    if (loc.startsWith('/insights'))  return 'Insights';
    if (loc.startsWith('/progress'))  return 'Progress';
    if (loc.startsWith('/settings'))  return 'Settings';
    return 'Serenity';
  }
}

class _MenuBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _MenuBtn({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(Icons.menu_rounded, color: AppColors.sidebarTxt, size: 17),
    ),
  );
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active, col;
  final VoidCallback onTap;
  final Color? color;
  const _NavItem({required this.icon, required this.label, required this.active,
      required this.col, required this.onTap, this.color});

  @override State<_NavItem> createState() => _NavItemState();
}
class _NavItemState extends State<_NavItem> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final ic = widget.color ?? (widget.active || _h ? Colors.white : AppColors.sidebarTxt);
    final bg = widget.active ? AppColors.sidebarAct : _h ? AppColors.sidebarHov : Colors.transparent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          margin: const EdgeInsets.only(bottom: 2),
          padding: EdgeInsets.symmetric(horizontal: widget.col ? 14 : 12, vertical: 10),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
          child: Row(children: [
            Icon(widget.icon, color: ic, size: 18),
            if (!widget.col) ...[
              const SizedBox(width: 10),
              Text(widget.label, style: TextStyle(color: ic, fontSize: 14,
                  fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Topbar extends StatelessWidget {
  final String title;
  const _Topbar({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSpacing.topbarH,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const Spacer(),
        // Crisis button
        _TopBtn('Crisis Support', Icons.favorite_border_rounded, AppColors.rose,
            () => GoRouter.of(context).push('/crisis')),
        const SizedBox(width: 12),
        Container(width: 36, height: 36,
          decoration: BoxDecoration(color: AppColors.sageSurf,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border)),
          child: const Icon(Icons.person_outline_rounded, color: AppColors.sage, size: 18)),
      ]),
    );
  }
}

class _TopBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _TopBtn(this.label, this.icon, this.color, this.onTap);

  @override State<_TopBtn> createState() => _TopBtnState();
}
class _TopBtnState extends State<_TopBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _h ? widget.color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _h ? widget.color.withOpacity(0.4) : AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(widget.icon, size: 15, color: widget.color),
          const SizedBox(width: 6),
          Text(widget.label, style: TextStyle(color: widget.color, fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      ),
    ),
  );
}
