import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme_constants.dart';
import '../../../../shared/widgets/badges/boncuk_balance_pill.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/cards/bowl_builder_feature_card.dart';
import '../../../../shared/widgets/cards/loyalty_campaign_card.dart';
import '../../../../shared/widgets/images/product_image.dart';
import '../../../../shared/widgets/misc/spin_wheel_icon.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../campaigns/presentation/screens/campaigns_screen.dart';
import '../../../favorites/presentation/providers/favorites_provider.dart';
import '../../../navigation/presentation/providers/navigation_provider.dart';
import '../../../menu/presentation/providers/menu_catalog_provider.dart';
import '../../../menu/presentation/providers/menu_filter_provider.dart';
import '../../../menu/presentation/screens/product_detail_screen.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';
import '../../../orders/domain/models/order_model.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../orders/presentation/screens/active_order_screen.dart';
import '../../../orders/presentation/screens/orders_screen.dart';
import '../../../profile/domain/models/loyalty_level.dart';
import '../../../profile/domain/models/loyalty_task_model.dart';
import '../../../profile/presentation/providers/addresses_provider.dart';
import '../../../profile/presentation/providers/loyalty_provider.dart';
import '../../../profile/presentation/screens/loyalty_screen.dart';
import '../../../qr/presentation/screens/qr_scanner_screen.dart';
import '../../../restaurant/presentation/providers/delivery_zone_provider.dart';
import '../../../restaurant/presentation/providers/restaurant_status_provider.dart';
import '../widgets/campaign_carousel.dart';

/// The restaurant name shown in the branch/delivery info block. No
/// `Branch`/branch-selection provider exists anywhere in this codebase yet
/// (`shared/models/branch.dart` is defined but never instantiated) — this is
/// a deliberate static placeholder until one does, per product decision.
const String _kStaticBranchName = 'Abaküs Ortaköy';

/// Real menu categories, in catalog order — must stay in sync with
/// `AbakusMenuCatalog.categories`. A category tapped here is handed to
/// `menuFilterProvider` verbatim, so a name here that doesn't match a real
/// category would silently fall back to "Tümü" in Menu.
const List<String> _kQuickCategories = [
  'Bowl',
  'Salata',
  'Wrap',
  'Hamburger',
  'Makarna',
  'Atıştırmalık',
  'İçecekler',
];

/// Turkish time-of-day greeting — no name. No real user-profile name exists
/// anywhere in the auth domain model (`AuthSession` only carries a phone
/// number), so showing one would mean fabricating it; this greeting
/// deliberately never does.
String _greetingForHour(int hour) {
  if (hour >= 5 && hour < 12) return 'Günaydın';
  if (hour >= 12 && hour < 18) return 'İyi Günler';
  if (hour >= 18 && hour < 22) return 'İyi Akşamlar';
  return 'İyi Geceler';
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final PageController _campaignPageController;

  @override
  void initState() {
    super.initState();
    _campaignPageController = PageController(
      viewportFraction: AppThemeConstants.campaignViewportFraction,
    );
  }

  @override
  void dispose() {
    _campaignPageController.dispose();
    super.dispose();
  }

  void _openLoyalty() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoyaltyScreen()),
    );
  }

  void _openLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  void _showComingSoon(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = ref.watch(
      authProvider.select((state) => state.isAuthenticated),
    );
    final favoriteItems = ref.watch(
      favoritesProvider.select((state) => state.items),
    );
    final selectedAddress = ref.watch(
      addressesProvider.select((list) => list.isEmpty ? null : list.first),
    );
    final restaurantStatus = ref.watch(restaurantStatusProvider);
    final deliveryZoneNotifier = ref.watch(deliveryZoneProvider.notifier);
    final featuredProducts = ref.watch(featuredMenuProductsProvider);
    final activeOrder = ref.watch(activeOrderProvider);
    final loyaltyState = isAuthenticated ? ref.watch(loyaltyProvider) : null;

    final eligibility = deliveryZoneNotifier.checkEligibility(selectedAddress);
    final greeting = _greetingForHour(DateTime.now().hour);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Üst karşılama alanı.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$greeting 👋',
                    style: AppTypography.headlineMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      if (isAuthenticated) ...[
                        GestureDetector(
                          onTap: _openLoyalty,
                          child: Semantics(
                            button: true,
                            label: 'Boncuk bakiyen, detay için dokun',
                            child: const BoncukBalancePill(),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                      Semantics(
                        button: true,
                        label: 'Bildirimler',
                        child: IconButton(
                          icon: const Icon(
                            Icons.notifications_outlined,
                            color: AppColors.textPrimary,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const NotificationsScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // 2. Şube ve teslimat/gel-al bilgisi.
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: AppRadius.kMedium,
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.storefront_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _kStaticBranchName,
                            style: AppTypography.labelLarge.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: (restaurantStatus.isOpen &&
                                    restaurantStatus.acceptsOrders)
                                ? AppColors.success
                                : AppColors.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          (restaurantStatus.isOpen &&
                                  restaurantStatus.acceptsOrders)
                              ? 'Açık'
                              : 'Kapalı',
                          style: AppTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Icon(
                          Icons.timelapse_rounded,
                          size: 16,
                          color: restaurantStatus.isBusy
                              ? AppColors.warning
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '${restaurantStatus.estimatedDeliveryMinutes} dk',
                          style: AppTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.bold,
                            color: restaurantStatus.isBusy
                                ? AppColors.warning
                                : AppColors.textPrimary,
                          ),
                        ),
                        if (restaurantStatus.isBusy) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.12),
                              borderRadius: AppRadius.kSmall,
                            ),
                            child: Text(
                              'Yoğun',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.warning,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (selectedAddress != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${selectedAddress.title} (${selectedAddress.neighborhood}) · $eligibility',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // 3. Aktif sipariş kartı — yalnızca gerçekten varsa.
              if (activeOrder != null) ...[
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Aktif Siparişin',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _ActiveOrderCard(order: activeOrder),
              ],

              // 4. Ana kampanya alanı — tek görsel küme (carousel + tüm
              // kampanyalar bağlantısı), kullanıcı kontrollü kaydırma,
              // autoplay yok.
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Kampanyalar',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              CampaignCarousel(pageController: _campaignPageController),
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                button: true,
                label: 'Tüm kampanyaları ve indirim kodlarını gör',
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CampaignsScreen(),
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: AppRadius.kMedium,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Tüm kampanyaları ve kuponları gör',
                            style: AppTypography.bodyMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 5. Hızlı aksiyonlar — tam olarak 4: QR, Gel-Al, Rezervasyon,
              // Siparişlerim.
              const SizedBox(height: AppSpacing.xl),
              _QuickActionsRow(
                onQrOrder: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const QrScannerScreen(),
                    ),
                  );
                },
                onPickup: () => ref
                    .read(navigationProvider.notifier)
                    .selectTab(AppTab.menu),
                onReservation: () =>
                    _showComingSoon('Rezervasyon özelliği yakında eklenecek.'),
                onMyOrders: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const OrdersScreen(),
                    ),
                  );
                },
              ),

              // 6. Kategori kısayolları.
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Hızlı Kategoriler',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _kQuickCategories.length,
                  itemBuilder: (context, index) {
                    final category = _kQuickCategories[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: ActionChip(
                        label: Text(category),
                        backgroundColor: AppColors.surfaceVariant,
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.kMedium,
                        ),
                        side: BorderSide.none,
                        onPressed: () {
                          ref
                              .read(menuFilterProvider.notifier)
                              .setFilter(category);
                          ref
                              .read(navigationProvider.notifier)
                              .selectTab(AppTab.menu);
                        },
                      ),
                    );
                  },
                ),
              ),

              // 7. Kendi Bowlunu Yarat kartı.
              const SizedBox(height: AppSpacing.xl),
              BowlBuilderFeatureCard(
                onTap: () => ref
                    .read(navigationProvider.notifier)
                    .selectTab(AppTab.buildBowl),
              ),

              // 8. Popüler ürünler — tek liste, gerçek görsellerle.
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Popüler Ürünler',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: featuredProducts.length,
                itemBuilder: (context, index) {
                  final product = featuredProducts[index];
                  final isFav = favoriteItems.any(
                    (item) => item.productId == product.id,
                  );

                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: AppCard(
                      child: ListTile(
                        leading: ProductImage(
                          imageKey: product.imageKey,
                          width: AppThemeConstants.popularProductImageSize,
                          height: AppThemeConstants.popularProductImageSize,
                          borderRadius: AppRadius.kSmall,
                        ),
                        title: Text(
                          product.name,
                          style: AppTypography.bodyLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${product.basePrice.toStringAsFixed(0)} TL',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        trailing: Semantics(
                          button: true,
                          label: isFav
                              ? '${product.name} favorilerden çıkar'
                              : '${product.name} favorilere ekle',
                          child: Icon(
                            isFav
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isFav
                                ? AppColors.error
                                : AppColors.textSecondary,
                          ),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ProductDetailScreen(product: product),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),

              // 9. Boncuk/sadakat özeti — guest'te uydurma bakiye yok.
              const SizedBox(height: AppSpacing.xl),
              if (isAuthenticated && loyaltyState != null) ...[
                _LoyaltyGlanceRow(
                  loyaltyState: loyaltyState,
                  onTap: _openLoyalty,
                ),
                if (loyaltyState.tasks.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Bugünün Boncuk Görevleri',
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 124,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: loyaltyState.tasks.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(
                            right: AppSpacing.md,
                          ),
                          child: GestureDetector(
                            onTap: _openLoyalty,
                            child: _TaskCard(task: loyaltyState.tasks[index]),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (loyaltyState.campaigns.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Boncuk Kampanyaları',
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final campaign in loyaltyState.campaigns)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: GestureDetector(
                        onTap: _openLoyalty,
                        child: LoyaltyCampaignCard(campaign: campaign),
                      ),
                    ),
                ],
              ] else
                _GuestLoyaltyCard(onLoginTap: _openLogin),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown instead of [_LoyaltyGlanceRow] for a guest (or otherwise
/// unauthenticated) session — no personal Boncuk balance exists for a guest,
/// so none is fabricated here.
class _GuestLoyaltyCard extends StatelessWidget {
  final VoidCallback onLoginTap;

  const _GuestLoyaltyCard({required this.onLoginTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Boncuk kazanmak için giriş yap',
      child: GestureDetector(
        onTap: onLoginTap,
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              const Icon(
                Icons.eco_rounded,
                color: AppColors.primary,
                size: 24,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Boncuk kazanmaya başla',
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Siparişlerinde puan kazanmak için giriş yap.',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.textSecondary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A two-card row summarizing the customer's Boncuk (loyalty) standing at a
/// glance — tapping either card opens the full [LoyaltyScreen], which owns
/// the actual "spin the wheel" and "redeem a reward" actions; nothing here
/// duplicates that logic.
class _LoyaltyGlanceRow extends StatelessWidget {
  final LoyaltyState loyaltyState;
  final VoidCallback onTap;

  const _LoyaltyGlanceRow({required this.loyaltyState, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: '${LoyaltyLevelInfo.labelFor(loyaltyState.level)} seviye, '
                '${loyaltyState.currentBalance} Boncuk, detay için dokun',
            child: GestureDetector(
              onTap: onTap,
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.eco_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          LoyaltyLevelInfo.labelFor(loyaltyState.level),
                          style: AppTypography.labelLarge.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${loyaltyState.currentBalance} Boncuk',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loyaltyState.nextLevel == null
                          ? 'En üst seviyedesin!'
                          : '${loyaltyState.pointsToNextLevel} boncuk kaldı',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Semantics(
            button: true,
            label: loyaltyState.dailySpinAvailable
                ? 'Şans Çarkı, çevirme hakkın var'
                : 'Şans Çarkı, bugünkü hakkını kullandın',
            child: GestureDetector(
              onTap: onTap,
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Şans Çarkı 🎡',
                            style: AppTypography.labelLarge.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            loyaltyState.dailySpinAvailable
                                ? 'Hakkın var, çevir!'
                                : 'Bugün kullandın',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SpinWheelIcon(size: 36),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Replaces the old "Son Siparişin" mock section — reads the customer's real
/// current order from [activeOrderProvider] instead of hardcoded demo
/// products, and "Takip Et" opens the real [ActiveOrderScreen] instead of
/// silently re-adding fixed items to the cart.
class _ActiveOrderCard extends StatelessWidget {
  final OrderModel order;

  const _ActiveOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final summary = order.items.isEmpty
        ? order.status
        : order.items
            .map((item) => '${item.quantity}x ${item.productName}')
            .join(', ');

    return Semantics(
      button: true,
      label: 'Aktif siparişin: $summary, ${order.status}, detay için dokun',
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ActiveOrderScreen(orderId: order.id),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.kMedium,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.primaryExtraLight,
                        borderRadius: AppRadius.kSmall,
                      ),
                      child: Text(
                        order.status,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      summary,
                      style: AppTypography.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${order.totalAmount.toStringAsFixed(0)} TL',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.textSecondary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final LoyaltyTaskModel task;

  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.kMedium,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                task.isCompleted
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: task.isCompleted
                    ? AppColors.success
                    : AppColors.textSecondary,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '+${task.rewardPoints}',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            task.title,
            style: AppTypography.bodySmall.copyWith(
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: AppRadius.kPill,
            child: LinearProgressIndicator(
              value: task.progressRatio,
              backgroundColor: AppColors.border,
              color: AppColors.primary,
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  final VoidCallback onQrOrder;
  final VoidCallback onPickup;
  final VoidCallback onReservation;
  final VoidCallback onMyOrders;

  const _QuickActionsRow({
    required this.onQrOrder,
    required this.onPickup,
    required this.onReservation,
    required this.onMyOrders,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionPill(
            icon: Icons.qr_code_2_rounded,
            label: 'Masada QR Oku',
            onTap: onQrOrder,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _QuickActionPill(
            icon: Icons.storefront_rounded,
            label: 'Gel Al',
            onTap: onPickup,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _QuickActionPill(
            icon: Icons.event_seat_rounded,
            label: 'Rezervasyon',
            onTap: onReservation,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _QuickActionPill(
            icon: Icons.receipt_long_rounded,
            label: 'Siparişlerim',
            onTap: onMyOrders,
          ),
        ),
      ],
    );
  }
}

class _QuickActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.kMedium,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.kMedium,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: kMinInteractiveDimension,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: AppColors.primary, size: 20),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
