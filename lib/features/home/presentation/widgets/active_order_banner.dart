import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../orders/domain/models/order_model.dart';

/// A compact conditional contextual card shown only when the customer has
/// a real active order ([activeOrderProvider] non-null). H.1.1 — restyled
/// from a single-line pill into a two-line premium card (icon badge +
/// status/summary stack + chevron) so it reads as clearly important
/// without visually outweighing the promo-carousel slot above it — still
/// deliberately quieter than a full hero.
class ActiveOrderBanner extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onTap;

  const ActiveOrderBanner(
      {super.key, required this.order, required this.onTap});

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
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.primaryExtraLight,
            borderRadius: AppRadius.kLarge,
            border: Border.all(color: AppColors.primaryLight),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      order.status,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
