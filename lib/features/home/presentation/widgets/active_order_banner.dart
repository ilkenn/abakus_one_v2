import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../orders/domain/models/order_model.dart';

/// A compact, single-line conditional banner shown only when the customer
/// has a real active order ([activeOrderProvider] non-null) — deliberately
/// small so it doesn't compete with the Home hero for attention, unlike the
/// old multi-line bordered card this replaces.
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: const BoxDecoration(
            color: AppColors.primaryExtraLight,
            borderRadius: AppRadius.kPill,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.local_shipping_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '${order.status} · $summary',
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
