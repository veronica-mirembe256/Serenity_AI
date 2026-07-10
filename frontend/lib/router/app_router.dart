import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenity/core/theme/app_theme.dart';
import 'package:serenity/state/providers.dart';
import 'package:serenity/shared/layout/dashboard_shell.dart';
import 'package:serenity/features/auth/presentation/login_page.dart';
import 'package:serenity/features/auth/presentation/register_page.dart';
import 'package:serenity/features/onboarding/presentation/onboarding_page.dart';
import 'package:serenity/features/dashboard/presentation/dashboard_page.dart';
import 'package:serenity/features/journal/presentation/journal_page.dart';
import 'package:serenity/features/insights/presentation/insights_page.dart';
import 'package:serenity/features/progress/presentation/progress_page.dart';
import 'package:serenity/features/crisis/presentation/crisis_page.dart';
import 'package:serenity/features/settings/presentation/settings_page.dart';
import 'package:serenity/features/therapist/presentation/therapist_dashboard_page.dart';

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider.autoDispose<GoRouter>((ref) {
  final listenable = _AuthListenable(ref);

  final router = GoRouter(
    initialLocation: '/splash',
    debugLogDiagnostics: false,
    refreshListenable: listenable,

    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc  = state.matchedLocation;

      if (!auth.isInitialized) return '/splash';

      final authed   = auth.isAuthenticated;
      final isPublic = loc == '/splash'
          || loc.startsWith('/login')
          || loc.startsWith('/register')
          || loc.startsWith('/onboarding')
          || loc.startsWith('/crisis')
          || loc.startsWith('/therapist-dashboard');

      if (!authed && !isPublic)                     return '/login';
      if (!authed && loc == '/splash')              return '/login';
      if (authed && (loc == '/splash'
          || loc == '/login' || loc == '/register')) return '/dashboard';
      return null;
    },

    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _Splash()),

      // Public
      GoRoute(path: '/login',      builder: (_, __) => const LoginPage()),
      GoRoute(path: '/register',   builder: (_, __) => const RegisterPage()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingPage()),
      GoRoute(path: '/crisis',     builder: (_, __) => const CrisisPage()),

      // Therapist portal — separate shell, no patient sidebar
      GoRoute(
        path: '/therapist-dashboard',
        builder: (_, __) => const Scaffold(
          backgroundColor: AppColors.bg,
          body: TherapistDashboardPage(),
        ),
      ),

      // Authenticated patient shell
      ShellRoute(
        builder: (ctx, state, child) => DashboardShell(child: child),
        routes: [
          GoRoute(path: '/dashboard',
              pageBuilder: (_, s) => NoTransitionPage(
                  key: s.pageKey, child: const DashboardPage())),
          GoRoute(path: '/journal',
              pageBuilder: (_, s) => NoTransitionPage(
                  key: s.pageKey, child: const JournalPage())),
          GoRoute(path: '/insights',
              pageBuilder: (_, s) => NoTransitionPage(
                  key: s.pageKey, child: const InsightsPage())),
          GoRoute(path: '/progress',
              pageBuilder: (_, s) => NoTransitionPage(
                  key: s.pageKey, child: const ProgressPage())),
          GoRoute(path: '/settings',
              pageBuilder: (_, s) => NoTransitionPage(
                  key: s.pageKey, child: const SettingsPage())),
        ],
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('404', style: TextStyle(
            fontSize: 56, color: AppColors.inkLt,
            fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text('Page not found',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => GoRouter.of(context).go('/login'),
          child: const Text('Go to Login'),
        ),
      ])),
    ),
  );

  ref.onDispose(listenable.dispose);
  return router;
});

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppColors.bg,
    body: Center(child: CircularProgressIndicator(
        strokeWidth: 2, color: AppColors.sage)),
  );
}