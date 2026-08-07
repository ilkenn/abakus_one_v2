import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../onboarding/presentation/provider/onboarding_provider.dart';
import '../widgets/premium_abacus_hero.dart';

/// The app's boot screen — Sprint 1 premium redesign (see the approved
/// plan's five-concept ideation): a calm, light-first brand moment. The
/// abacus resolves from soft focus to sharp (implying a camera settling on
/// the object, not a UI element popping in), beads cascade and settle,
/// then a very subtle "breathing" scale keeps the frame from feeling
/// static, before a soft-cut into Onboarding/Login. Deliberately not
/// flashy: no bounce, no elastic overshoot on the frame itself, no
/// loading spinner. Replaces the previous version in full — see
/// `docs/master_spec_migration.md` for this screen's design history.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
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
  static const _breatheDelay = Duration(milliseconds: 1300);
  static const _totalDuration = Duration(milliseconds: 3000);

  /// Drives the soft-focus-to-sharp resolve on the hero — starts the
  /// instant the frame becomes visible, finishes well within its own
  /// fade/scale-in.
  late final AnimationController _focusController;

  /// A single slow, tiny scale cycle — "camera breathing" — started once
  /// the frame has already settled. Amplitude is deliberately minuscule
  /// (0.6%) so it reads as alive, not animated.
  late final AnimationController _breatheController;
  late final Animation<double> _breatheScale;

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

    _focusController = AnimationController(
      vsync: this,
      duration: _motion(const Duration(milliseconds: 250)),
    );
    _breatheController = AnimationController(
      vsync: this,
      duration: _motion(const Duration(milliseconds: 1400)),
    );
    _breatheScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.008)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.008, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
    ]).animate(_breatheController);

    if (_reduceMotion) {
      _showFrame = true;
      _showWordmark = true;
      _showTagline = true;
      _focusController.value = 1.0;
    }
    _runSequence();
  }

  @override
  void dispose() {
    _focusController.dispose();
    _breatheController.dispose();
    super.dispose();
  }

  Future<void> _runSequence() async {
    if (!_reduceMotion) {
      await Future.delayed(_frameDelay);
      if (!mounted) return;
      setState(() => _showFrame = true);
      _focusController.forward();

      await Future.delayed(_breatheDelay - _frameDelay);
      if (!mounted) return;
      unawaited(_breatheController.forward());

      await Future.delayed(_wordmarkDelay - _breatheDelay);
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
        // A single warm glow biased toward the upper-left — implies one
        // soft morning-light source, matching the hero's own shadow
        // direction, rather than a flat centered vignette.
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.35, -0.5),
            radius: 1.3,
            colors: [_SplashPalette.warmGlow, AppColors.background],
            stops: [0.0, 1.0],
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
                    scale: _showFrame ? 1 : 0.94,
                    duration: _motion(const Duration(milliseconds: 500)),
                    curve: Curves.easeOutCubic,
                    // Accessibility Standards §12: the abacus illustration
                    // is decorative branding, not information — "Abaküs" +
                    // the tagline below already carry the semantic
                    // content, so it's excluded from the accessibility
                    // tree rather than left to pick up an incidental
                    // default label.
                    child: ExcludeSemantics(
                      child: AnimatedBuilder(
                        animation: Listenable.merge(
                            [_focusController, _breatheController]),
                        builder: (context, child) {
                          // Resolves from a soft focus pull (sigma 6 → 0)
                          // into the settled, very slight breathing scale
                          // — two distinct effects, sequenced not layered
                          // simultaneously, so neither reads as "jittery."
                          final sigma =
                              (1 - _focusController.value).clamp(0.0, 1.0) *
                                  6.0;
                          return ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX: sigma,
                              sigmaY: sigma,
                            ),
                            child: Transform.scale(
                              scale: _breatheScale.value,
                              child: child,
                            ),
                          );
                        },
                        child: const PremiumAbacusHero(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxxl),
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
                        letterSpacing: 3.5,
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
                        letterSpacing: 2.4,
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

/// Colors specific to this one screen's warm-glow background and tagline —
/// not general UI tokens, so they live here rather than in `AppColors`,
/// mirroring `CLAUDE.md` §6's documented screen-local-decorative-color
/// exception. See `docs/master_spec_migration.md`.
abstract final class _SplashPalette {
  _SplashPalette._();

  /// The warm light-source color the upper-left radial gradient glows
  /// from, fading into `AppColors.background` — biased warmer/lighter
  /// than the old centered gradient's edge tone, since this is now the
  /// brightest point implying the light source, not just a border tint.
  static const Color warmGlow = Color(0xFFF3E8D2);

  /// Darkened from an earlier `#8A6D4A` — that value computed to ~3.7:1
  /// contrast against the background, short of Accessibility Standards
  /// §3's 4.5:1 normal-text minimum. This value computes to ~5.9:1.
  static const Color tagline = Color(0xFF6B4E30);
}
