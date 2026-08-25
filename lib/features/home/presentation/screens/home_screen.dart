import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/layout/app_breakpoints.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../bowl_builder/presentation/screens/bowl_builder_screen.dart';
import '../../../delivery/presentation/screens/delivery_address_selection_screen.dart';
import '../../../navigation/presentation/providers/navigation_provider.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../orders/presentation/screens/active_order_screen.dart';
import '../../../loyalty/presentation/screens/loyalty_screen.dart';
import '../../../qr/presentation/screens/qr_scanner_screen.dart';
import '../../../takeaway/presentation/screens/takeaway_branch_selection_screen.dart';
import '../widgets/active_order_banner.dart';
import '../widgets/boncuk_section.dart';
import '../widgets/community_preview_section.dart';
import '../widgets/compact_bowl_builder_card.dart';
import '../widgets/home_category_section.dart';
import '../widgets/home_hero_carousel.dart';
import '../widgets/home_top_bar.dart';
import '../widgets/order_mode_section.dart';
import '../widgets/popular_products_section.dart';
import '../widgets/weekly_editorial_section.dart';

/// The customer Home screen — H.2 true redesign. Section order follows the
/// locked final Home composition: header, real 3-slide promo carousel,
/// 2×2 order modes, conditional active context, Boncuk, categories, one
/// compact Bowl Builder promo, Abaküs'ün Favorileri, Topluluk & Yorumlar,
/// weekly editorial spotlight.
///
/// `FeaturedContentSection` is deliberately omitted from this tree — the
/// hero carousel now owns the primary-promotion role it used to play, and
/// showing both would duplicate campaign messaging — but its file/provider
/// is untouched, per the no-silent-deletion rule; only this screen's
/// reference to it was removed. `HomeHeroSection`/`BuildBowlBanner` (the
/// two previous, separate Bowl Builder promos) are likewise no longer
/// referenced here, superseded by the single `CompactBowlBuilderCard`
/// below — both files are left in place, now orphaned, not deleted.
///
/// Each section is its own component (see `features/home/presentation/
/// widgets/`) — this screen only assembles them, wires navigation, and
/// applies shell-level spacing/responsive width; it holds no section's own
/// layout.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// Content column max width once the viewport is at/above
  /// [AppBreakpoints.tablet] — keeps text/cards from stretching edge-to-edge
  /// on tablet/web, per H.1's responsive requirement. Scoped to this screen
  /// rather than promoted to a shared design token, since Home is the first
  /// consumer-facing screen to need it — promote later if a second screen
  /// needs the same value.
  static const double _kMaxContentWidth = 640.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(
      authProvider.select((state) => state.isAuthenticated),
    );
    // Phase 9K: activeOrderProvider is sourced from the canonical
    // Firestore-backed order store, scoped by the signed-in customer's uid
    // — gated on isAuthenticated for the same reason as before (no session
    // means nothing real to query).
    final activeOrder = isAuthenticated ? ref.watch(activeOrderProvider) : null;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= AppBreakpoints.tablet;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isWide ? _kMaxContentWidth : double.infinity,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Premium header.
                      HomeTopBar(
                        onBoncukTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const LoyaltyScreen()),
                        ),
                        onNotificationsTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const NotificationsScreen(),
                          ),
                        ),
                      ),

                      // 2. Real promo carousel (banner_02/04) — P8-B.1
                      // (2026-08-25): banner_01's campaign slide is
                      // temporarily removed, see HomeHeroCarousel's own doc
                      // comment.
                      const SizedBox(height: AppSpacing.xl),
                      HomeHeroCarousel(
                        onLoyaltyTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const LoyaltyScreen()),
                        ),
                        onDeliveryTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const DeliveryAddressSelectionScreen(),
                          ),
                        ),
                      ),

                      // 3. Order modes — compact 2×2 grid (H.2), same
                      // navigation behavior as before.
                      const SizedBox(height: AppSpacing.xl),
                      OrderModeSection(
                        onDineIn: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const QrScannerScreen(),
                          ),
                        ),
                        onPickup: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const TakeawayBranchSelectionScreen(),
                          ),
                        ),
                        onDelivery: () =>
                            ref.read(navigationProvider.notifier).selectTab(
                                  AppTab.menu,
                                ),
                        onReservation: () =>
                            context.push(AppRoutes.reservationPrefix),
                      ),

                      // 4. Conditional active context — today this is only
                      // the active-order banner; an upcoming-reservation
                      // card is not built here since no repository query
                      // for "this customer's reservations" exists yet
                      // (H.0 audit) — never fabricated.
                      if (activeOrder != null) ...[
                        const SizedBox(height: AppSpacing.xl),
                        ActiveOrderBanner(
                          order: activeOrder,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ActiveOrderScreen(orderId: activeOrder.id),
                            ),
                          ),
                        ),
                      ],

                      // 5. Boncuk section.
                      const SizedBox(height: AppSpacing.xl),
                      BoncukSection(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const LoyaltyScreen()),
                        ),
                        onLoginTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const LoginScreen()),
                        ),
                      ),

                      // 6. Categories — hides itself entirely when empty.
                      const SizedBox(height: AppSpacing.xl),
                      const HomeCategorySection(),

                      // 7. ONE compact Kendi Bowl'unu Yarat promo (H.2
                      // consolidation — the previous two separate promos,
                      // `HomeHeroSection`/`BuildBowlBanner`, are no longer
                      // referenced here; see class doc comment).
                      const SizedBox(height: AppSpacing.xl),
                      CompactBowlBuilderCard(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const BowlBuilderScreen(),
                          ),
                        ),
                      ),

                      // 8. Abaküs'ün Favorileri — real featured-product data,
                      // restaurant/editorial picks (not a saved-favorites
                      // list).
                      const SizedBox(height: AppSpacing.xl),
                      const PopularProductsSection(),

                      // 9. Topluluk & Yorumlar — presentation shell only,
                      // no fake review data; functional implementation
                      // follows in H.5.
                      const SizedBox(height: AppSpacing.xl),
                      const CommunityPreviewSection(),

                      // 10. Weekly editorial spotlight — real product data.
                      const SizedBox(height: AppSpacing.xl),
                      const WeeklyEditorialSection(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
