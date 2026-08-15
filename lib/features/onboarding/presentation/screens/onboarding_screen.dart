import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_radius.dart';
import '../provider/onboarding_provider.dart';

/// Exposes the controls row's own [BuildContext] so
/// [_OnboardingScreenState] can measure its real rendered height (needed to
/// size the artwork's [Positioned] box above it) and so widget tests can
/// independently locate the same element to assert the two meet correctly.
final GlobalKey onboardingControlsKey = GlobalKey();

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const double _bottomGap = 10.0;

  // Only used for the very first frame, before the controls row has been
  // laid out and measured once. Close to its real measured height on a
  // typical device so there's no visible jump once the real value lands.
  static const double _fallbackControlsContentHeight = 76.0;

  double? _measuredControlsContentHeight;

  static const List<String> _onboardingImages = [
    'assets/images/onboarding/onboarding_1.png',
    'assets/images/onboarding/onboarding_2.png',
    'assets/images/onboarding/onboarding_3.png',
  ];

  // Crop-window position within each image's box (BoxFit.cover keeps the
  // image scaled to fill the box either way -- alignment only chooses
  // which part of the source is visible). Top-aligned so the logo near
  // the source's top edge is never cut; excess height is cropped from
  // the bottom instead. Independent per image so each can be tuned on
  // its own if one image's internal composition needs a different bias.
  static const List<Alignment> _onboardingImageAlignments = [
    Alignment(0.0, -1.0),
    Alignment(0.0, -1.0),
    Alignment(0.0, -1.0),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_measureControlsHeight);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _measureControlsHeight(Duration _) {
    final renderObject =
        onboardingControlsKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final height = renderObject.size.height;
      if (height != _measuredControlsContentHeight && mounted) {
        setState(() => _measuredControlsContentHeight = height);
      }
    }
  }

  void _navigateToLogin() {
    ref.read(onboardingCompleteProvider.notifier).completeOnboarding();
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    // Bottom-only trim: the image's box stays pinned to the very top of
    // the screen (top: 0 -- full-bleed, not pushed down) and is only
    // shortened at the bottom, against the controls row. That bottom trim
    // is what gives BoxFit.cover real vertical crop room to work with;
    // `alignment` below then chooses where in that room the crop sits.
    // This is a crop-position change, not a resize -- the image still
    // scales to fully cover its box on every device.
    final controlsContentHeight =
        _measuredControlsContentHeight ?? _fallbackControlsContentHeight;
    final bottomInset =
        controlsContentHeight + mediaQuery.padding.bottom + _bottomGap;

    return Scaffold(
      // No SafeArea here, deliberately — the background artwork must
      // extend edge-to-edge behind the status bar and the gesture/nav
      // area. SafeArea is applied only around the control row below, per
      // "respect SafeArea for interactive controls, not the image."
      body: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: bottomInset,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _onboardingImages.length,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              itemBuilder: (context, index) {
                return Image.asset(
                  _onboardingImages[index],
                  fit: BoxFit.cover,
                  alignment: _onboardingImageAlignments[index],
                  width: double.infinity,
                  height: double.infinity,
                );
              },
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                key: onboardingControlsKey,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.lg,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _navigateToLogin,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                      ),
                      child: const Text('Atla'),
                    ),
                    Row(
                      children: List.generate(
                        _onboardingImages.length,
                        (index) => Container(
                          margin: const EdgeInsets.only(right: 6),
                          width: _currentPage == index ? 20 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? AppColors.primary
                                : AppColors.border,
                            borderRadius: AppRadius.kSmall,
                          ),
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        if (_currentPage < _onboardingImages.length - 1) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeIn,
                          );
                        } else {
                          _navigateToLogin();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                          vertical: AppSpacing.md,
                        ),
                      ),
                      child: Text(_currentPage == _onboardingImages.length - 1
                          ? 'Başla'
                          : 'İleri'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
