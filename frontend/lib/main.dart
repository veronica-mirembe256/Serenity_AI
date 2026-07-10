import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:serenity/core/theme/app_theme.dart';
import 'package:serenity/router/app_router.dart';
import 'package:serenity/state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  runApp(const ProviderScope(child: SerenityApp()));
}

class SerenityApp extends ConsumerWidget {
  const SerenityApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth   = ref.watch(authProvider);
    final router = ref.watch(routerProvider);

    if (!auth.isInitialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: const Scaffold(
          backgroundColor: AppColors.bg,
          body: Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.sage),
          ),
        ),
      );
    }

    return MaterialApp.router(
      title: 'Serenity',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      routerConfig: router,
      scrollBehavior: const _WebScroll(),
    );
  }
}

class _WebScroll extends ScrollBehavior {
  const _WebScroll();
  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
  };
}
