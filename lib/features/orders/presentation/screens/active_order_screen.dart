import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../../menu/data/abakus_menu_catalog.dart';
import '../../../profile/presentation/screens/help_screen.dart';
import '../../domain/models/courier_visibility.dart';
import '../../domain/models/order_channel.dart';
import '../../domain/models/order_item_snapshot.dart';
import '../../domain/models/order_model.dart';
import '../../domain/models/order_status.dart';
import '../../domain/models/order_tracking_step.dart';
import '../providers/orders_provider.dart';
import '../widgets/dine_in_line_approval_section.dart';
import 'order_detail_screen.dart';

/// Customer-facing Active Order Tracking screen.
///
/// Reads state exclusively through [ordersProvider]/[activeOrderProvider] —
/// no order data is ever embedded in this widget. With [orderId] omitted,
/// shows the customer's current active order (see [activeOrderProvider]);
/// with it set, shows that specific order regardless of whether it's still
/// active (used by the post-checkout "Siparişi Takip Et" deep link, and by
/// a delivered/cancelled order's own "Detaylar" flow if ever routed here).
/// If no matching order exists — including a direct-route open with nothing
/// active — renders a safe empty state instead of crashing or showing
/// stale content.
class ActiveOrderScreen extends ConsumerWidget {
  final String? orderId;

  const ActiveOrderScreen({super.key, this.orderId});

  OrderModel? _resolveOrder(List<OrderModel> orders, OrderModel? active) {
    final targetId = orderId;
    if (targetId == null) return active;
    for (final order in orders) {
      if (order.id == targetId) return order;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersProvider);
    final active = ref.watch(activeOrderProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sipariş Takibi'),
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
            message: 'Sipariş bilgileri yüklenirken bir sorun oluştu.',
            retryLabel: 'Tekrar Dene',
            onRetry: () => ref.invalidate(ordersProvider),
          ),
          data: (orders) {
            final order = _resolveOrder(orders, active);
            return order == null
                ? EmptyView(
                    icon: Icons.receipt_long_rounded,
                    message:
                        'Şu anda takip edebileceğiniz aktif bir siparişiniz yok.',
                    actionLabel: 'Menüye Göz At',
                    onAction: () => Navigator.pop(context),
                  )
                : _ActiveOrderBody(order: order);
          },
        ),
      ),
    );
  }
}

class _ActiveOrderBody extends StatelessWidget {
  final OrderModel order;

  const _ActiveOrderBody({required this.order});

  @override
  Widget build(BuildContext context) {
    final isCancelled = order.lifecycleStatus == OrderStatus.cancelled ||
        order.lifecycleStatus == OrderStatus.rejected;
    final isDelivered = !isCancelled &&
        !OrderTrackingTimeline.isActiveForCustomer(order.lifecycleStatus);
    final steps = OrderTrackingTimeline.stepsFor(order.channel);
    final currentStep =
        OrderTrackingTimeline.currentStepFor(order.lifecycleStatus);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OrderHeaderCard(order: order),
          const SizedBox(height: AppSpacing.xl),
          if (isCancelled)
            _CancelledStatusCard(order: order)
          else
            _StatusTimelineCard(steps: steps, currentStep: currentStep),
          if (!isCancelled && order.channel == OrderChannel.delivery) ...[
            const SizedBox(height: AppSpacing.xl),
            _DeliveryPlaceholderCard(order: order),
          ],
          const SizedBox(height: AppSpacing.xl),
          _OrderItemsCard(order: order),
          if (!isCancelled)
            DineInLineApprovalSection(
              orderId: order.id,
              channel: order.channel,
            ),
          const SizedBox(height: AppSpacing.xl),
          _OrderSummaryCard(order: order),
          const SizedBox(height: AppSpacing.xl),
          _DeliveryOrTableInfoCard(order: order),
          const SizedBox(height: AppSpacing.xl),
          _ActionButtons(order: order, isDelivered: isDelivered),
        ],
      ),
    );
  }
}

class _OrderHeaderCard extends StatelessWidget {
  final OrderModel order;

  const _OrderHeaderCard({required this.order});

  String get _channelLabel {
    switch (order.channel) {
      case OrderChannel.delivery:
        return 'Paket Servis';
      case OrderChannel.takeaway:
        return 'Gel Al';
      case OrderChannel.dineInQr:
      case OrderChannel.dineInStaff:
        return 'Masada';
      case OrderChannel.reservationPreorder:
        return 'Rezervasyon Ön Siparişi';
    }
  }

  String get _createdAtText {
    final created = order.timestamps?.created;
    if (created == null) return order.date;
    final time =
        '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
    return '${order.date} · $time';
  }

  @override
  Widget build(BuildContext context) {
    final isCancelled = order.lifecycleStatus == OrderStatus.cancelled ||
        order.lifecycleStatus == OrderStatus.rejected;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  order.id,
                  style: AppTypography.titleLarge.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatusBadge(order: order),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _createdAtText,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              _InfoChip(
                  icon: Icons.storefront_rounded, label: order.branchName),
              _InfoChip(
                icon: Icons.local_shipping_outlined,
                label: _channelLabel,
              ),
            ],
          ),
          if (!isCancelled) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(
                  Icons.timelapse_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  order.channel == OrderChannel.delivery
                      ? 'Tahmini teslimat: ${order.estimatedMinutes} dk'
                      : 'Tahmini hazırlanma: ${order.estimatedMinutes} dk',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final OrderModel order;

  const _StatusBadge({required this.order});

  @override
  Widget build(BuildContext context) {
    final isCancelled = order.lifecycleStatus == OrderStatus.cancelled ||
        order.lifecycleStatus == OrderStatus.rejected;
    final step = OrderTrackingTimeline.currentStepFor(order.lifecycleStatus);
    final label = isCancelled
        ? 'İptal Edildi'
        : (step != null ? OrderTrackingTimeline.labelFor(step) : '');
    final color = isCancelled ? AppColors.error : AppColors.primary;

    return Semantics(
      label: 'Sipariş durumu: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: AppRadius.kPill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCancelled ? Icons.cancel_rounded : Icons.circle,
              size: isCancelled ? 14 : 8,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.labelLarge.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTimelineCard extends StatelessWidget {
  final List<OrderTrackingStep> steps;
  final OrderTrackingStep? currentStep;

  const _StatusTimelineCard({required this.steps, required this.currentStep});

  @override
  Widget build(BuildContext context) {
    final currentIndex = currentStep == null ? -1 : steps.indexOf(currentStep!);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sipariş Durumu',
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < steps.length; i++)
            _TimelineRow(
              step: steps[i],
              isCompleted: currentIndex >= 0 && i < currentIndex,
              isCurrent: i == currentIndex,
              isLast: i == steps.length - 1,
            ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final OrderTrackingStep step;
  final bool isCompleted;
  final bool isCurrent;
  final bool isLast;

  const _TimelineRow({
    required this.step,
    required this.isCompleted,
    required this.isCurrent,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = isCompleted || isCurrent;
    final label = OrderTrackingTimeline.labelFor(step);
    final textStyle = (isCurrent
            ? AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold)
            : AppTypography.bodyMedium)
        .copyWith(
            color: isDone ? AppColors.textPrimary : AppColors.textSecondary);

    return Semantics(
      label: isCurrent
          ? '$label, şu anki durum'
          : (isCompleted ? '$label, tamamlandı' : label),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        isDone ? AppColors.primary : AppColors.surfaceVariant,
                    border: Border.all(
                      color: isDone ? AppColors.primary : AppColors.border,
                      width: isCurrent ? 2 : 1,
                    ),
                  ),
                  child: isCompleted
                      ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        )
                      : (isCurrent
                          ? Center(
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            )
                          : null),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: isCompleted ? AppColors.primary : AppColors.border,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: isLast ? 0 : AppSpacing.lg,
                  top: 2,
                ),
                child: Text(label, style: textStyle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CancelledStatusCard extends StatelessWidget {
  final OrderModel order;

  const _CancelledStatusCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final reason = order.cancellation?.reason ?? order.cancellationReason;

    return AppCard(
      borderColor: AppColors.error.withValues(alpha: 0.3),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cancel_rounded, color: AppColors.error, size: 28),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bu sipariş iptal edildi',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (reason != null && reason.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Neden: $reason',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The explicitly-a-placeholder delivery panel. Enforces the courier
/// privacy rule at the presentation layer: never renders a map or any
/// location detail, and only switches its (still non-map) copy once
/// [OrderModel.courierVisibility] is [CourierVisibility.visibleToCustomer].
class _DeliveryPlaceholderCard extends StatelessWidget {
  final OrderModel order;

  const _DeliveryPlaceholderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final isVisible = order.lifecycleStatus == OrderStatus.outForDelivery &&
        order.courierVisibility == CourierVisibility.visibleToCustomer;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Teslimat',
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.xl,
              horizontal: AppSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: AppRadius.kMedium,
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Icon(
                  isVisible
                      ? Icons.delivery_dining_rounded
                      : Icons.map_outlined,
                  size: 40,
                  color: isVisible
                      ? AppColors.primary
                      : AppColors.textSecondary.withValues(alpha: 0.6),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  isVisible
                      ? 'Kuryeniz yolda'
                      : 'Canlı konum henüz görüntülenemiyor',
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.bold,
                    color:
                        isVisible ? AppColors.primary : AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  isVisible
                      ? 'Kurye bu siparişe özel yola çıktı. Canlı harita entegrasyonu yakında eklenecek.'
                      : 'Kuryeniz teslimat sırası geldiğinde konumu görüntülenecek.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderItemsCard extends StatelessWidget {
  final OrderModel order;

  const _OrderItemsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sipariş İçeriği',
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (order.items.isEmpty)
            Text(
              'Bu sipariş için ürün detayı kaydedilmemiş.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            for (var i = 0; i < order.items.length; i++) ...[
              _OrderItemRow(item: order.items[i]),
              if (i != order.items.length - 1)
                const Divider(height: AppSpacing.lg),
            ],
        ],
      ),
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  final OrderItemSnapshot item;

  const _OrderItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.quantity}x',
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(item.productName, style: AppTypography.bodyLarge),
            ),
            Text(
              '${item.lineTotal.toStringAsFixed(0)} TL',
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        if (item.modifierDescriptions.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              item.modifierDescriptions.join(' · '),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
        if (item.notes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              'Not: ${item.notes}',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _OrderSummaryCard extends StatelessWidget {
  final OrderModel order;

  const _OrderSummaryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final subtotal =
        order.items.fold<double>(0, (sum, item) => sum + item.lineTotal);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ödeme Özeti',
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _SummaryLine(label: 'Ara Toplam', value: subtotal),
          if (order.discountAmount > 0)
            _SummaryLine(
              label: 'İndirim',
              value: -order.discountAmount,
              valueColor: AppColors.primary,
            ),
          if (order.channel == OrderChannel.delivery)
            _SummaryLine(
              label: 'Teslimat Ücreti',
              value: order.deliveryFeeAmount,
            ),
          const Divider(height: AppSpacing.lg),
          _SummaryLine(
            label: 'Genel Toplam',
            value: order.totalAmount,
            isBold: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final double value;
  final bool isBold;
  final Color? valueColor;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final style = isBold
        ? AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold)
        : AppTypography.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(
            '${value < 0 ? '-' : ''}${value.abs().toStringAsFixed(0)} TL',
            style: style.copyWith(
              color: valueColor ?? (isBold ? AppColors.primary : null),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryOrTableInfoCard extends StatelessWidget {
  final OrderModel order;

  const _DeliveryOrTableInfoCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final isDelivery = order.channel == OrderChannel.delivery;
    if (isDelivery && order.deliveryAddressText.isEmpty) {
      return const SizedBox.shrink();
    }

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Icon(
            isDelivery
                ? Icons.location_on_rounded
                : Icons.table_restaurant_rounded,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDelivery ? 'Teslimat Adresi' : 'Sipariş Yeri',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isDelivery
                      ? order.deliveryAddressText
                      : (order.channel == OrderChannel.takeaway
                          ? 'Gel Al'
                          : (order.tableName ?? 'Masada Servis')),
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends ConsumerWidget {
  final OrderModel order;
  final bool isDelivered;

  const _ActionButtons({required this.order, required this.isDelivered});

  void _reorder(BuildContext context, WidgetRef ref) {
    if (order.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bu sipariş için ürün bilgisi kaydedilmediğinden tekrar eklenemiyor.',
          ),
        ),
      );
      return;
    }

    final added = <String>[];
    final skipped = <String>[];

    for (final item in order.items) {
      final matches = AbakusMenuCatalog.products
          .where((product) => product.id == item.productId)
          .toList();
      final match = matches.isEmpty ? null : matches.first;

      if (match == null || !match.isAvailable) {
        skipped.add(item.productName);
        continue;
      }

      // Güncel katalog fiyatı kullanılır — donmuş sipariş fiyatı asla
      // yeniden zorlanmaz.
      ref.read(cartProvider.notifier).addToCart(
            id: match.id,
            name: match.name,
            desc: match.description,
            price: match.basePrice,
            quantity: item.quantity,
          );
      added.add(item.productName);
    }

    if (added.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bu siparişteki ürünler artık menüde bulunmadığından hiçbiri eklenemedi.',
          ),
        ),
      );
      return;
    }

    final message = skipped.isEmpty
        ? '${added.length} ürün güncel fiyatlarla sepete eklendi. Not: modifier ve Bowl Builder seçimleri otomatik geri yüklenmez, menüden tekrar seçebilirsiniz.'
        : '${added.length} ürün sepete eklendi. ${skipped.length} ürün artık menüde olmadığından eklenemedi: ${skipped.join(", ")}.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.support_agent_rounded),
            label: const Text('Destek Al'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HelpScreen()),
              );
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            ),
          ),
        ),
        if (isDelivered) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tekrar Sipariş Ver'),
              onPressed: () => _reorder(context, ref),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.star_outline_rounded),
              label: const Text('Siparişi Değerlendir'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OrderDetailScreen(order: order),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
