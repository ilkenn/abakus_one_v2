import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/branding/presentation/providers/resolved_app_theme_provider.dart';

class AbakusApp extends ConsumerWidget {
  const AbakusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Phase 8 (`docs/decisions.md` ADR-025): `resolvedAppThemeProvider`
    // falls back to the unmodified `AppTheme.lightTheme` while
    // loading/on error/when no tenant brand theme exists yet — today's
    // single-tenant appearance is unaffected until a tenant owner
    // actually sets one.
    final theme = ref.watch(resolvedAppThemeProvider).when(
          data: (theme) => theme,
          loading: () => AppTheme.lightTheme,
          error: (_, __) => AppTheme.lightTheme,
        );
    return MaterialApp.router(
      title: 'Abaküs One',
      debugShowCheckedModeBanner: false,
      theme: theme,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
