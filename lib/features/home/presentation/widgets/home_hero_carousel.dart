import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/config/asset_paths.dart';
import '../../../../core/layout/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/images/cropped_asset_image.dart';

/// One carousel slide's fixed data — H.2/H.2.1. [imageAspectRatio] is the
/// asset's own real pixel width/height (verified once via direct file
/// inspection, never guessed).
///
/// Two rendering strategies share this same data, picked by
/// [HomeHeroCarousel] per current screen width:
/// - **Tablet/wide**: the full artwork, `BoxFit.contain`, with an
///   invisible `Semantics(button:true)` hit target aligned to the
///   artwork's own baked-in button ([wideCtaRect]/[wideCtaSemanticsLabel]).
/// - **Phone** (H.2.1): the full wide artwork scaled down made its baked
///   text illegible, so the phone composition instead shows only a small,
///   confirmed-clean crop of the artwork's photography
///   ([mobileCropX0]..[mobileCropY1] — never any part of the baked
///   headline/badge/mockup) alongside a real Flutter headline/support/CTA
///   ([mobileHeadline]/[mobileSupport]/[mobileCtaLabel]).
class HeroSlideData {
  const HeroSlideData({
    required this.assetFileName,
    required this.imageAspectRatio,
    required this.wideCtaRect,
    required this.wideCtaSemanticsLabel,
    required this.mobileCropX0,
    required this.mobileCropX1,
    required this.mobileCropY0,
    required this.mobileCropY1,
    required this.mobileHeadline,
    required this.mobileSupport,
    required this.mobileCtaLabel,
    required this.onTap,
  });

  final String assetFileName;
  final double imageAspectRatio;

  /// Fractional bounding box of the artwork's own baked-in CTA button
  /// (tablet/wide mode only), measured directly from
  /// `banner_01/02/04.png`.
  final Rect wideCtaRect;
  final String wideCtaSemanticsLabel;

  /// Fractional crop window (phone mode only) into a confirmed-clean
  /// photography region of the same source asset — measured by direct
  /// visual inspection, deliberately excluding every baked headline/
  /// badge/mockup element.
  final double mobileCropX0;
  final double mobileCropX1;
  final double mobileCropY0;
  final double mobileCropY1;

  final String mobileHeadline;
  final String mobileSupport;
  final String mobileCtaLabel;

  final VoidCallback onTap;

  double get mobileCropAspectRatio =>
      ((mobileCropX1 - mobileCropX0) * imageAspectRatio) /
      (mobileCropY1 - mobileCropY0);
}

/// The real 3-slide promotional hero carousel — H.2/H.2.1. Auto-rotates,
/// swipeable, infinite loop, resets its rotation timer after any user
/// interaction. Carousel shell (timer/controller/indicator) is identical
/// on phone and tablet/wide — only each slide's own content composition
/// differs, per [HeroSlideData]'s class doc comment.
class HomeHeroCarousel extends StatefulWidget {
  const HomeHeroCarousel({
    super.key,
    required this.onCampaignTap,
    required this.onLoyaltyTap,
    required this.onDeliveryTap,
  });

  final VoidCallback onCampaignTap;
  final VoidCallback onLoyaltyTap;
  final VoidCallback onDeliveryTap;

  /// Tablet/wide viewport aspect ratio — the middle ground of the three
  /// real asset ratios (3.0 / 1.78 / 2.0), so no single slide is
  /// letterboxed excessively more than the others.
  static const double wideViewportAspectRatio = 2.0;

  /// Phone viewport aspect ratio — a compact split card (real Flutter
  /// text panel + a small clean photography crop), short enough to read
  /// as "premium compact," not a giant hero.
  static const double mobileViewportAspectRatio = 1.9;

  static const Duration autoRotateInterval = Duration(seconds: 7);
  static const Duration transitionDuration = Duration(milliseconds: 500);

  /// Large enough that a customer can swipe backward from the first slide
  /// many times before ever reaching page 0 — the standard Flutter
  /// "effectively infinite" `PageView` technique (real `itemCount` stays
  /// null; `itemBuilder` cycles `index % slides.length`).
  static const int _infiniteAnchorMultiplier = 5000;

  @override
  State<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<HomeHeroCarousel> {
  late final List<HeroSlideData> _slides;
  late final PageController _pageController;
  Timer? _autoTimer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _slides = [
      HeroSlideData(
        assetFileName: 'banner_01.png',
        imageAspectRatio: 2172 / 724,
        wideCtaRect: const Rect.fromLTRB(0.04, 0.68, 0.37, 0.85),
        wideCtaSemanticsLabel: 'Fırsatı Kullan, ilk siparişe 100 TL indirim',
        // Right side of the bowl (avocado/cabbage) — clears the "100 TL"
        // badge (ends ~0.58) and the headline block entirely.
        mobileCropX0: 0.62,
        mobileCropX1: 0.903,
        mobileCropY0: 0.0,
        mobileCropY1: 1.0,
        mobileHeadline: 'İlk Siparişine 100 TL Bizden',
        mobileSupport: 'İlk siparişinde 100 TL avantaj seni bekliyor.',
        mobileCtaLabel: 'Fırsatı Kullan',
        onTap: widget.onCampaignTap,
      ),
      HeroSlideData(
        assetFileName: 'banner_02.png',
        imageAspectRatio: 1672 / 941,
        wideCtaRect: const Rect.fromLTRB(0.06, 0.60, 0.36, 0.75),
        wideCtaSemanticsLabel: 'Boncukları Keşfet',
        // The ceramic bowl + hanging bead, right of the phone mockup
        // (which ends ~0.66) — never shows the mockup's own numbers.
        mobileCropX0: 0.68,
        mobileCropX1: 1.0,
        mobileCropY0: 0.15,
        mobileCropY1: 0.819,
        mobileHeadline: 'Boncuklarını Biriktirmeye Başla',
        mobileSupport: 'Her uygun siparişinle Boncuk kazan.',
        mobileCtaLabel: 'Boncukları Keşfet',
        onTap: widget.onLoyaltyTap,
      ),
      HeroSlideData(
        assetFileName: 'banner_04.png',
        imageAspectRatio: 1774 / 887,
        wideCtaRect: const Rect.fromLTRB(0.03, 0.72, 0.29, 0.86),
        wideCtaSemanticsLabel: 'Adresini Seç, Paket Servis',
        // The bowl + Bosphorus bridge, between the headline block (ends
        // ~0.42) and the paper bag's own branding (starts ~0.87).
        mobileCropX0: 0.45,
        mobileCropX1: 0.87,
        mobileCropY0: 0.0,
        mobileCropY1: 0.98,
        mobileHeadline: 'Paket Servis Hazır',
        mobileSupport: 'Sağlıklı lezzetler adresine gelsin.',
        mobileCtaLabel: 'Adresini Seç',
        onTap: widget.onDeliveryTap,
      ),
    ];
    _pageController = PageController(
      initialPage: HomeHeroCarousel._infiniteAnchorMultiplier * _slides.length,
    );
    _armAutoTimer();
  }

  void _armAutoTimer() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(HomeHeroCarousel.autoRotateInterval, (_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.nextPage(
        duration: HomeHeroCarousel.transitionDuration,
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < AppBreakpoints.tablet;
    final viewportAspectRatio = isMobile
        ? HomeHeroCarousel.mobileViewportAspectRatio
        : HomeHeroCarousel.wideViewportAspectRatio;

    return Column(
      children: [
        ClipRRect(
          borderRadius: AppRadius.kExtraLarge,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              boxShadow: AppShadows.card,
            ),
            child: AspectRatio(
              aspectRatio: viewportAspectRatio,
              // Resets the 7s auto-rotate countdown after ANY scroll
              // activity on the PageView — both a manual swipe and the
              // timer's own animated `nextPage()` call emit
              // ScrollStartNotification, so re-arming here is correct in
              // both cases: a genuine user interaction gets a full fresh
              // 7s before the next auto-advance, and an auto-advance
              // itself simply re-establishes the next 7s cycle.
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification) {
                    _armAutoTimer();
                  }
                  return false;
                },
                child: PageView.builder(
                  key: const Key('homeHeroCarousel'),
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index % _slides.length);
                  },
                  itemBuilder: (context, index) {
                    final slide = _slides[index % _slides.length];
                    final assetPath =
                        '${AssetPaths.homeBannerDirectory}${slide.assetFileName}';
                    return isMobile
                        ? _MobileHeroSlideView(
                            assetPath: assetPath,
                            slide: slide,
                          )
                        : _HeroSlideView(assetPath: assetPath, slide: slide);
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          key: const Key('heroCarouselIndicator'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _slides.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _currentIndex ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color:
                      i == _currentIndex ? AppColors.primary : AppColors.border,
                  borderRadius: AppRadius.kPill,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Tablet/wide slide — the full artwork, `BoxFit.contain` (never cropped/
/// stretched), with an invisible hit target aligned to its own baked-in
/// CTA button. Unchanged from H.2.
class _HeroSlideView extends StatelessWidget {
  const _HeroSlideView({required this.assetPath, required this.slide});

  final String assetPath;
  final HeroSlideData slide;

  static const double _minHitTargetSize = 48.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.maxWidth;
        final boxHeight = constraints.maxHeight;
        final boxRatio = boxWidth / boxHeight;

        late double renderWidth, renderHeight, offsetX, offsetY;
        if (slide.imageAspectRatio > boxRatio) {
          renderWidth = boxWidth;
          renderHeight = boxWidth / slide.imageAspectRatio;
          offsetX = 0;
          offsetY = (boxHeight - renderHeight) / 2;
        } else {
          renderHeight = boxHeight;
          renderWidth = boxHeight * slide.imageAspectRatio;
          offsetX = (boxWidth - renderWidth) / 2;
          offsetY = 0;
        }

        var ctaLeft = offsetX + slide.wideCtaRect.left * renderWidth;
        var ctaTop = offsetY + slide.wideCtaRect.top * renderHeight;
        var ctaRight = offsetX + slide.wideCtaRect.right * renderWidth;
        var ctaBottom = offsetY + slide.wideCtaRect.bottom * renderHeight;

        if (ctaRight - ctaLeft < _minHitTargetSize) {
          final centerX = (ctaLeft + ctaRight) / 2;
          ctaLeft = centerX - _minHitTargetSize / 2;
          ctaRight = centerX + _minHitTargetSize / 2;
        }
        if (ctaBottom - ctaTop < _minHitTargetSize) {
          final centerY = (ctaTop + ctaBottom) / 2;
          ctaTop = centerY - _minHitTargetSize / 2;
          ctaBottom = centerY + _minHitTargetSize / 2;
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              assetPath,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              errorBuilder: (context, error, stackTrace) => const ColoredBox(
                color: AppColors.primaryExtraLight,
              ),
            ),
            Positioned(
              left: ctaLeft,
              top: ctaTop,
              width: ctaRight - ctaLeft,
              height: ctaBottom - ctaTop,
              child: Semantics(
                button: true,
                label: slide.wideCtaSemanticsLabel,
                child: GestureDetector(
                  key: Key('heroCta_${slide.assetFileName}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: slide.onTap,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Phone slide (H.2.1) — a compact split card: a real Flutter headline/
/// support/CTA panel on the left, and a small confirmed-clean crop of the
/// artwork's own photography on the right (never any baked text). A soft
/// cream gradient blends the photo's left seam into the text panel.
class _MobileHeroSlideView extends StatelessWidget {
  const _MobileHeroSlideView({required this.assetPath, required this.slide});

  final String assetPath;
  final HeroSlideData slide;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${slide.mobileHeadline}. ${slide.mobileSupport}',
      child: Material(
        color: AppColors.background,
        child: InkWell(
          key: Key('heroCta_${slide.assetFileName}'),
          onTap: slide.onTap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  // Center + SingleChildScrollView rather than a plain
                  // Column(mainAxisAlignment: center): at large text-scale
                  // accessibility settings the headline/support/CTA stack
                  // can exceed the carousel's fixed compact height — this
                  // scrolls instead of throwing a RenderFlex overflow,
                  // while looking identical (centered, no visible scroll
                  // affordance) at every normal text scale.
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            slide.mobileHeadline,
                            style: AppTypography.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            slide.mobileSupport,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: AppRadius.kPill,
                            ),
                            child: Text(
                              slide.mobileCtaLabel,
                              style: AppTypography.labelLarge.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              AspectRatio(
                aspectRatio: slide.mobileCropAspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CroppedAssetImage(
                      assetPath: assetPath,
                      sourceAspectRatio: slide.imageAspectRatio,
                      cropX0: slide.mobileCropX0,
                      cropX1: slide.mobileCropX1,
                      cropY0: slide.mobileCropY0,
                      cropY1: slide.mobileCropY1,
                    ),
                    // Soft seam blend, not a legibility mechanism — the
                    // text panel beside it has no image behind it at all.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 20,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              AppColors.background,
                              AppColors.background.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
