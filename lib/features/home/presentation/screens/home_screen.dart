import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../bowl_builder/presentation/screens/bowl_builder_screen.dart';
import '../../../navigation/presentation/providers/navigation_provider.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../orders/presentation/screens/active_order_screen.dart';
import '../../../profile/presentation/screens/loyalty_screen.dart';
import '../../../qr/presentation/screens/qr_scanner_screen.dart';
import '../../../takeaway/presentation/screens/takeaway_branch_selection_screen.dart';
import '../widgets/active_order_banner.dart';
import '../widgets/boncuk_section.dart';
import '../widgets/build_bowl_banner.dart';
import '../widgets/featured_content_section.dart';
import '../widgets/home_category_section.dart';
import '../widgets/home_hero_section.dart';
import '../widgets/home_top_bar.dart';
import '../widgets/order_mode_section.dart';
import '../widgets/popular_products_section.dart';

/// The customer Home screen — rebuilt (Phase 1: structure + asset
/// integration) around 9 explicitly ordered sections: compact top bar,
/// active-order banner, hero, order-mode section, Bowl Builder banner,
/// featured content, popular products, categories, Boncuk. Each section is
/// its own component (see `features/home/presentation/widgets/`) — this
/// screen only assembles them and wires navigation, it holds no section's
/// own layout.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Compact top bar.
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

              // Compact active-order banner — only when a real order exists.
              if (activeOrder != null) ...[
                const SizedBox(height: AppSpacing.md),
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

              // 2. Primary hero.
              const SizedBox(height: AppSpacing.lg),
              HomeHeroSection(
                onCreateBowlTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BowlBuilderScreen(),
                  ),
                ),
              ),

              // 3. Order mode section.
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
                    builder: (context) => const TakeawayBranchSelectionScreen(),
                  ),
                ),
                onDelivery: () =>
                    ref.read(navigationProvider.notifier).selectTab(
                          AppTab.menu,
                        ),
                onReservation: () => context.push(AppRoutes.reservationPrefix),
              ),

              // 4. Bowl Builder feature banner.
              const SizedBox(height: AppSpacing.xl),
              BuildBowlBanner(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BowlBuilderScreen(),
                  ),
                ),
              ),

              // 5. Featured content — hides itself entirely when empty.
              const FeaturedContentSection(),

              // 6. Popular products — hides itself entirely when empty.
              const PopularProductsSection(),

              // 7. Categories — hides itself entirely when empty.
              const HomeCategorySection(),

              // 8. Boncuk section.
              const SizedBox(height: AppSpacing.xl),
              BoncukSection(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const LoyaltyScreen()),
                ),
                onLoginTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
