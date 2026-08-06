import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../../home/presentation/data/mock_data.dart';
import '../../../navigation/presentation/providers/navigation_provider.dart';
import '../providers/orders_provider.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  Future<void> _handleReorder(
    BuildContext context,
    WidgetRef ref,
    String orderId,
  ) async {
    final cartItems = ref.read(cartProvider);
    const availableProducts = HomeMockData.popularProducts;
    final itemsToReorder = <Map<String, dynamic>>[];

    if (orderId == 'ORD-2026-001') {
      final match1 = availableProducts.any((p) => p['name'] == 'Protein Bowl');
      if (match1) {
        final prod = availableProducts.firstWhere(
          (p) => p['name'] == 'Protein Bowl',
        );
        itemsToReorder.add({
          'id': 'prod_${prod['name'].hashCode}',
          'name': prod['name'],
          'desc': prod['desc'],
          'price':
              double.tryParse(prod['price']!.replaceAll(' TL', '')) ?? 150.0,
          'quantity': 1,
          'selectedProtein': 'Izgara Tavuk',
          'selectedSauce': 'Sarımsaklı Mayonez',
        });
      }
    } else {
      if (availableProducts.isNotEmpty) {
        final prod = availableProducts.first;
        itemsToReorder.add({
          'id': 'prod_${prod['name'].hashCode}',
          'name': prod['name'],
          'desc': prod['desc'],
          'price':
              double.tryParse(prod['price']!.replaceAll(' TL', '')) ?? 120.0,
          'quantity': 2,
          'selectedProtein': '',
          'selectedSauce': '',
        });
      }
    }

    if (itemsToReorder.isEmpty) return;

    void performAddition() {
      for (final item in itemsToReorder) {
        ref.read(cartProvider.notifier).addToCart(
              id: item['id'] as String,
              name: item['name'] as String,
              desc: item['desc'] as String,
              price: item['price'] as double,
              quantity: item['quantity'] as int,
              selectedProtein: item['selectedProtein'] as String? ?? '',
              selectedSauce: item['selectedSauce'] as String? ?? '',
            );
      }
      ref.read(navigationProvider.notifier).selectTab(AppTab.cart);
    }

    if (cartItems.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sepetiniz Dolu'),
          content: const Text('Sepetinizde ürün bulunuyor.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                performAddition();
              },
              child: const Text('Birleştir'),
            ),
          ],
        ),
      );
    } else {
      performAddition();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Siparişlerim'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: ordersAsync.when(
          loading: () => const LoadingView(),
          error: (error, stackTrace) => ErrorView(
            message: 'Siparişleriniz yüklenirken bir sorun oluştu.',
            retryLabel: 'Tekrar Dene',
            onRetry: () => ref.invalidate(ordersProvider),
          ),
          data: (orders) => orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long_rounded,
                        size: 64,
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Henüz bir siparişiniz bulunmuyor.',
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.refresh(ordersProvider.future),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    itemCount: orders.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      final isScheduled =
                          order.deliveryTimingType == 'scheduled';
                      final isCancelled = order.status == 'İptal Edildi';
                      final isDelivered = order.status == 'Teslim Edildi';
                      final isReviewed = order.overallRating != null;

                      return Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: isCancelled
                              ? AppColors.surfaceVariant.withValues(alpha: 0.4)
                              : AppColors.surface,
                          borderRadius: AppRadius.kMedium,
                          border: Border.all(
                            color: isCancelled
                                ? Colors.red.withValues(alpha: 0.2)
                                : AppColors.border,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      order.id,
                                      style: AppTypography.titleMedium.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: isCancelled
                                            ? AppColors.textSecondary
                                            : null,
                                      ),
                                    ),
                                    if (isScheduled && !isCancelled) ...[
                                      const SizedBox(width: AppSpacing.xs),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: AppRadius.kSmall,
                                        ),
                                        child: const Text(
                                          'Planlı Sipariş',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  order.status,
                                  style: AppTypography.labelLarge.copyWith(
                                    color: isCancelled
                                        ? Colors.red
                                        : (order.status == 'Hazırlanıyor'
                                            ? Colors.orange
                                            : (order.status == 'Onay Bekliyor'
                                                ? Colors.blue
                                                : Colors.green)),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Tarih: ${order.date}',
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (isScheduled &&
                                order.scheduledDeliveryDateTime.isNotEmpty &&
                                !isCancelled)
                              Text(
                                'Planlanan Zaman: ${order.scheduledDeliveryDateTime}',
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            Text(
                              'Toplam Tutar: ${order.totalAmount.toStringAsFixed(0)} TL',
                              style: AppTypography.bodyLarge.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isCancelled
                                    ? AppColors.textSecondary
                                    : AppColors.primary,
                              ),
                            ),
                            const Divider(height: AppSpacing.md),
                            Row(
                              children: [
                                const Icon(
                                  Icons.restaurant_rounded,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  order.serviceMaterialsPreference.isNotEmpty
                                      ? order.serviceMaterialsPreference
                                      : 'Belirtilmedi',
                                  style: AppTypography.bodySmall.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            if (isCancelled &&
                                order.cancellationReason != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'İptal Nedeni: ${order.cancellationReason}',
                                style: AppTypography.bodySmall.copyWith(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                            if (isDelivered) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Row(
                                children: [
                                  Icon(
                                    Icons.star_rounded,
                                    size: 16,
                                    color: isReviewed
                                        ? Colors.amber
                                        : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isReviewed
                                        ? 'Değerlendirildi (Puan: ${order.overallRating}/5)'
                                        : 'Henüz Değerlendirilmedi',
                                    style: AppTypography.bodySmall.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: isReviewed
                                          ? Colors.amber[800]
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              OrderDetailScreen(order: order),
                                        ),
                                      );
                                    },
                                    child: const Text('Detaylar / Puanla'),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 16,
                                    ),
                                    onPressed: () =>
                                        _handleReorder(context, ref, order.id),
                                    label: const Text('Tekrarla'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}
