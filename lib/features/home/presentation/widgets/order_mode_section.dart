import 'package:flutter/material.dart';
import '../../../../core/config/asset_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import 'order_mode_card.dart';

/// "Nasıl sipariş vermek istersin?" — exactly four premium
/// [OrderModeCard]s, horizontally scrollable. Each card is sized to ~75%
/// of the screen width so the list always shows one full card plus a
/// visible edge of the next — enough to read as "keep scrolling," never
/// two cards squeezed side by side.
class OrderModeSection extends StatelessWidget {
  final VoidCallback onDineIn;
  final VoidCallback onPickup;
  final VoidCallback onDelivery;
  final VoidCallback onReservation;

  static const double _cardWidthFraction = 0.75;

  /// Generous, fixed allowance for the title line below the artwork —
  /// enough headroom at large accessibility text scale without the
  /// section's height depending on any particular device's text size.
  static const double _textAreaHeight = 40;

  const OrderModeSection({
    super.key,
    required this.onDineIn,
    required this.onPickup,
    required this.onDelivery,
    required this.onReservation,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = screenWidth * _cardWidthFraction;
    final imageHeight = cardWidth / OrderModeCard.aspectRatio;
    final sectionHeight = imageHeight + _textAreaHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nasıl sipariş vermek istersin?',
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: sectionHeight,
          child: ListView(
            key: const Key('orderModeListView'),
            scrollDirection: Axis.horizontal,
            children: [
              OrderModeCard(
                assetPath: '${AssetPaths.homeOrderModesDirectory}dine_in.webp',
                icon: Icons.table_restaurant_rounded,
                title: 'Masada Sipariş',
                width: cardWidth,
                onTap: onDineIn,
              ),
              const SizedBox(width: AppSpacing.md),
              OrderModeCard(
                assetPath: '${AssetPaths.homeOrderModesDirectory}pickup.webp',
                icon: Icons.storefront_rounded,
                title: 'Gel Al',
                width: cardWidth,
                onTap: onPickup,
              ),
              const SizedBox(width: AppSpacing.md),
              OrderModeCard(
                assetPath: '${AssetPaths.homeOrderModesDirectory}delivery.webp',
                icon: Icons.moped_rounded,
                title: 'Paket Servis',
                width: cardWidth,
                onTap: onDelivery,
              ),
              const SizedBox(width: AppSpacing.md),
              OrderModeCard(
                assetPath:
                    '${AssetPaths.homeOrderModesDirectory}reservation.webp',
                icon: Icons.event_seat_rounded,
                title: 'Rezervasyon',
                width: cardWidth,
                onTap: onReservation,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
