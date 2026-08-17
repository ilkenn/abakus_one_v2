import 'package:flutter/material.dart';
import '../../../../core/config/asset_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import 'home_section_title.dart';
import 'order_mode_grid_card.dart';

/// "Nasıl sipariş vermek istersin?" — H.2: a compact, static 2×2 premium
/// grid (previously a horizontally-scrolling row of cards each ~75% of
/// the screen width — the exact "order-mode cards still dominate too much
/// vertical space" complaint this phase addresses). No scrolling needed
/// at all now; all four modes are visible at once, `NeverScrollableScroll
/// Physics` since `GridView` sits inside Home's own outer vertical scroll.
class OrderModeSection extends StatelessWidget {
  final VoidCallback onDineIn;
  final VoidCallback onPickup;
  final VoidCallback onDelivery;
  final VoidCallback onReservation;

  const OrderModeSection({
    super.key,
    required this.onDineIn,
    required this.onPickup,
    required this.onDelivery,
    required this.onReservation,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionTitle('Nasıl sipariş vermek istersin?'),
        GridView.count(
          key: const Key('orderModeGrid'),
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          // H.2.1: shortened ~25% from the original 0.95 (cards read as
          // having too much empty space below the images) — combined with
          // the card's own Expanded image, the image now fills nearly the
          // whole cell instead of leaving a gap.
          childAspectRatio: 1.25,
          children: [
            OrderModeGridCard(
              assetPath: '${AssetPaths.homeOrderModesDirectory}dine_in.webp',
              icon: Icons.table_restaurant_rounded,
              title: 'Masada Sipariş',
              onTap: onDineIn,
            ),
            OrderModeGridCard(
              assetPath: '${AssetPaths.homeOrderModesDirectory}pickup.webp',
              icon: Icons.storefront_rounded,
              title: 'Gel Al',
              onTap: onPickup,
            ),
            OrderModeGridCard(
              assetPath: '${AssetPaths.homeOrderModesDirectory}delivery.webp',
              icon: Icons.moped_rounded,
              title: 'Paket Servis',
              onTap: onDelivery,
            ),
            OrderModeGridCard(
              assetPath:
                  '${AssetPaths.homeOrderModesDirectory}reservation.webp',
              icon: Icons.event_seat_rounded,
              title: 'Rezervasyon',
              onTap: onReservation,
            ),
          ],
        ),
      ],
    );
  }
}
