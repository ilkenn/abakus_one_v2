import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../cart/domain/models/cart_item.dart';
import '../../../menu/presentation/screens/menu_screen.dart';
import '../providers/preorder_cart_provider.dart';
import 'reservation_preorder_scope.dart';

/// Step 5 — optional preorder. Faz R.2 §10/§11: the customer can finish
/// the reservation without ordering ("Şimdilik Geç"), or add items by
/// reusing the existing menu/product-detail/Bowl Builder UI unmodified
/// (`ReservationPreorderScope` isolates the cart it writes into — see that
/// widget's own doc comment). Pricing shown here is always whatever
/// `CartItem` already computes client-side — the same "consistent preview,
/// never authoritative" caveat every other cart screen in this app already
/// carries; `submitReservation`'s own Faz R.1D.1 pricing is what actually
/// prices the order.
class PreorderStep extends ConsumerWidget {
  const PreorderStep({super.key});

  void _openMenu(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const ReservationPreorderScope(child: MenuScreen()),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(preorderCartProvider);

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Column(
          children: [
            const Icon(Icons.restaurant_menu_rounded,
                size: 48, color: AppColors.primaryLight),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Masanız hazır olduğunda ne yiyeceğinizi şimdiden seçebilirsiniz — tamamen isteğe bağlı.',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton.icon(
              onPressed: () => _openMenu(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ön Sipariş Ekle'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.kExtraLarge),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Rezervasyon Ön Siparişi',
                style: AppTypography.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: () => _openMenu(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Ekle'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final item in items) _PreorderCartLine(item: item),
        const Divider(height: AppSpacing.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Toplam', style: AppTypography.titleMedium),
            Text(
              '${items.fold<double>(0, (sum, i) => sum + i.totalRowPrice).toStringAsFixed(0)} TL',
              style: AppTypography.priceLarge,
            ),
          ],
        ),
      ],
    );
  }
}

class _PreorderCartLine extends ConsumerWidget {
  const _PreorderCartLine({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: AppTypography.bodyLarge),
                if (item.desc.isNotEmpty)
                  Text(
                    item.desc,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          _QuantityControl(item: item),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 64,
            child: Text(
              '${item.totalRowPrice.toStringAsFixed(0)} TL',
              textAlign: TextAlign.end,
              style: AppTypography.bodyMedium
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.textSecondary,
            tooltip: 'Kaldır',
            onPressed: () => ref
                .read(preorderCartProvider.notifier)
                .removeFromCart(customizationsKey: item.customizationsKey),
          ),
        ],
      ),
    );
  }
}

class _QuantityControl extends ConsumerWidget {
  const _QuantityControl({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
          onPressed: () => ref
              .read(preorderCartProvider.notifier)
              .decrementQuantity(item.customizationsKey),
        ),
        Text('${item.quantity}', style: AppTypography.bodyLarge),
        IconButton(
          icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
          onPressed: () => ref
              .read(preorderCartProvider.notifier)
              .incrementQuantity(item.customizationsKey),
        ),
      ],
    );
  }
}
