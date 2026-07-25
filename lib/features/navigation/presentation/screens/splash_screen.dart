import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../onboarding/presentation/provider/onboarding_provider.dart';
import '../widgets/splash_abacus_animation.dart';

/// The app's boot screen — a staged, cinematic brand reveal: wooden frame →
/// beads cascade and settle → "Abaküs" wordmark → tagline → soft fade into
/// Onboarding/Login. Rebuilt per explicit user direction after an earlier
/// version (flat primary-green full-bleed background, mark+wordmark
/// appearing instantly together, a spinner) was judged to read as a
/// generic/default splash rather than a premium brand moment. See
/// `docs/master_spec_migration.md` for the full design rationale.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  /// Accessibility Standards §9 (Hareket Hassasiyeti): the staged reveal is
  /// decorative motion, not load-bearing information, so it's skipped
  /// entirely — content appears immediately — when the OS "reduce motion"
  /// preference is on.
  final bool _reduceMotion = WidgetsBinding
      .instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  bool _showFrame = false;
  bool _showWordmark = false;
  bool _showTagline = false;

  static const _frameDelay = Duration(milliseconds: 30);
  static const _wordmarkDelay = Duration(milliseconds: 1650);
  static const _taglineDelay = Duration(milliseconds: 2100);
  static const _totalDuration = Duration(milliseconds: 3000);

  Duration _motion(Duration normal) => _reduceMotion ? Duration.zero : normal;

  /// Started immediately, in parallel with the reveal animation below, so
  /// checking for a persisted session never adds to the splash's fixed
  /// 3000ms duration in the normal case — `_runSequence` only awaits it
  /// once the animation timeline itself is already done.
  late final Future<void> _sessionCheck;

  @override
  void initState() {
    super.initState();
    _sessionCheck = ref.read(authProvider.notifier).checkPersistedSession();
    if (_reduceMotion) {
      _showFrame = true;
      _showWordmark = true;
      _showTagline = true;
    }
    _runSequence();
  }

  Future<void> _runSequence() async {
    if (!_reduceMotion) {
      await Future.delayed(_frameDelay);
      if (!mounted) return;
      setState(() => _showFrame = true);

      await Future.delayed(_wordmarkDelay - _frameDelay);
      if (!mounted) return;
      setState(() => _showWordmark = true);

      await Future.delayed(_taglineDelay - _wordmarkDelay);
      if (!mounted) return;
      setState(() => _showTagline = true);

      await Future.delayed(_totalDuration - _taglineDelay);
    } else {
      await Future.delayed(_totalDuration);
    }
    await _sessionCheck;
    if (!mounted) return;
    _navigateToNext();
  }

  void _navigateToNext() {
    final isAuthenticated = ref.read(authProvider).isAuthenticated;
    if (isAuthenticated) {
      context.go(AppRoutes.main);
      return;
    }
    final isOnboardingCompleted = ref.read(onboardingCompleteProvider);
    context.go(isOnboardingCompleted ? AppRoutes.login : AppRoutes.onboarding);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.15),
            radius: 1.1,
            colors: [AppColors.background, _SplashPalette.warmEdge],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedOpacity(
                  opacity: _showFrame ? 1 : 0,
                  duration: _motion(const Duration(milliseconds: 500)),
                  curve: Curves.easeOut,
                  child: AnimatedScale(
                    scale: _showFrame ? 1 : 0.9,
                    duration: _motion(const Duration(milliseconds: 500)),
                    curve: Curves.easeOutCubic,
                    // Accessibility Standards §12: the abacus illustration is
                    // decorative branding, not information — "Abaküs" +
                    // the tagline below already carry the semantic content,
                    // so it's excluded from the accessibility tree rather
                    // than left to pick up an incidental default label.
                    child:
                        const ExcludeSemantics(child: SplashAbacusAnimation()),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                AnimatedSlide(
                  offset: _showWordmark ? Offset.zero : const Offset(0, 0.18),
                  duration: _motion(const Duration(milliseconds: 450)),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _showWordmark ? 1 : 0,
                    duration: _motion(const Duration(milliseconds: 450)),
                    curve: Curves.easeOut,
                    child: Text(
                      'Abaküs',
                      style: AppTypography.displayLarge.copyWith(
                        color: AppColors.primary,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AnimatedSlide(
                  offset: _showTagline ? Offset.zero : const Offset(0, 0.18),
                  duration: _motion(const Duration(milliseconds: 450)),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _showTagline ? 1 : 0,
                    duration: _motion(const Duration(milliseconds: 450)),
                    curve: Curves.easeOut,
                    child: Text(
                      'DENGENİ BUL, LEZZETİ HİSSET',
                      style: AppTypography.labelLarge.copyWith(
                        color: _SplashPalette.tagline,
                        letterSpacing: 2.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Colors specific to this one screen's warm-cream brand-moment background
/// and tagline — not general UI tokens, so they live here rather than in
/// `AppColors`. See `docs/master_spec_migration.md`.
abstract final class _SplashPalette {
  _SplashPalette._();

  static const Color warmEdge = Color(0xFFEDE1CB);

  /// Darkened from an earlier `#8A6D4A` — that value computed to ~3.7:1
  /// contrast against [warmEdge], short of Accessibility Standards §3's
  /// 4.5:1 normal-text minimum. This value computes to ~5.9:1.
  static const Color tagline = Color(0xFF6B4E30);
}
