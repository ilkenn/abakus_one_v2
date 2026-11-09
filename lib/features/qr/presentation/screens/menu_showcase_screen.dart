import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../menu/presentation/screens/menu_screen.dart';
import '../providers/menu_showcase_mode_provider.dart';

/// 2026-11-09 — the read-only "vitrin" menu behind the floor-stand QR at the
/// entrance (`AppRoutes.menuShowcase`). Reuses the real [MenuScreen]
/// unchanged — categories, products, allergen filter and prices — with no
/// cart tab around it. Every add-to-cart entry point checks
/// `allowCartAdd`, which shows "Sipariş verebilmek için lütfen oturduğunuz
/// masadaki QR kodu okutun." while this mode is active and no table is
/// set. Scanning a table's QR opens `/table/:token`, whose table context
/// lifts the restriction.
class MenuShowcaseScreen extends ConsumerStatefulWidget {
  const MenuShowcaseScreen({super.key});

  @override
  ConsumerState<MenuShowcaseScreen> createState() => _MenuShowcaseScreenState();
}

class _MenuShowcaseScreenState extends ConsumerState<MenuShowcaseScreen> {
  @override
  void initState() {
    super.initState();
    // Providers must not be modified during the first build.
    Future.microtask(() {
      if (mounted) ref.read(menuShowcaseModeProvider.notifier).enter();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _ShowcaseBanner(),
          Expanded(child: MenuScreen()),
        ],
      ),
    );
  }
}

class _ShowcaseBanner extends StatelessWidget {
  const _ShowcaseBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryExtraLight,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(Icons.qr_code_2_rounded, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Menümüzü inceleyin — sipariş için masanızdaki QR kodu '
                  'okutun.',
                  key: const Key('menuShowcaseBanner'),
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
