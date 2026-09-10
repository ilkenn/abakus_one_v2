import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/courier_type.dart';
import '../../../courier/domain/identity/courier.dart';
import '../../../courier/presentation/widgets/courier_assignment_dialog.dart';
import '../../../orders/domain/models/order.dart';
import '../providers/courier_dispatch_dependencies_provider.dart';

/// AP-6 Sprint 2 — the branch's active delivery orders (`ready`/
/// `outForDelivery`), each with its courier-assignment state and a "Kurye
/// Ata" action. No existing delivery-order-detail screen exists anywhere in
/// POS/Admin to extend (confirmed by research) — this is genuinely new UI,
/// mirroring the shape of other AP-5/6 list screens. Design tokens
/// (`AppColors`/`AppTypography`/`AppSpacing`) only.
class DeliveryOrderDispatchScreen extends ConsumerWidget {
  const DeliveryOrderDispatchScreen({
    super.key,
    required this.organizationId,
    required this.branchId,
  });

  final String organizationId;
  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(assignableDeliveryOrdersProvider(branchId));
    final couriersAsync = ref.watch(allCouriersForBranchProvider(branchId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Kurye Dağıtımı')),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(
              child: Text(
                'Şu anda dağıtım bekleyen teslimat siparişi yok.',
                style: AppTypography.bodyMedium,
              ),
            );
          }
          final couriersById = <String, Courier>{
            for (final courier in couriersAsync.valueOrNull ?? const <Courier>[])
              courier.id: courier,
          };
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final order = orders[index];
              return _DeliveryOrderRow(
                order: order,
                assignedCourier: order.assignedCourierId == null
                    ? null
                    : couriersById[order.assignedCourierId],
                onAssign: () => showDialog<void>(
                  context: context,
                  builder: (_) => CourierAssignmentDialog(
                    organizationId: organizationId,
                    branchId: branchId,
                    orderId: order.id.value,
                    courierType: order.courierType,
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text(
            'Teslimat siparişleri yüklenemedi.',
            style: AppTypography.bodyMedium,
          ),
        ),
      ),
    );
  }
}

class _DeliveryOrderRow extends StatelessWidget {
  const _DeliveryOrderRow({
    required this.order,
    required this.assignedCourier,
    required this.onAssign,
  });

  final Order order;
  final Courier? assignedCourier;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final isMarketplace = order.courierType == CourierType.marketplace;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.kMedium,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.orderNumber.value, style: AppTypography.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${order.contactFirstName ?? ''} ${order.contactLastName ?? ''}'
                      .trim(),
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                _CourierStateBadge(
                  isMarketplace: isMarketplace,
                  assignedCourier: assignedCourier,
                ),
              ],
            ),
          ),
          if (isMarketplace)
            const SizedBox.shrink()
          else
            TextButton(onPressed: onAssign, child: const Text('Kurye Ata')),
        ],
      ),
    );
  }
}

class _CourierStateBadge extends StatelessWidget {
  const _CourierStateBadge({
    required this.isMarketplace,
    required this.assignedCourier,
  });

  final bool isMarketplace;
  final Courier? assignedCourier;

  @override
  Widget build(BuildContext context) {
    if (isMarketplace) {
      return Text(
        'Pazaryeri Kuryesi Taşımaktadır',
        style: AppTypography.caption.copyWith(color: AppColors.warning),
      );
    }
    if (assignedCourier != null) {
      return Text(
        'Kurye: ${assignedCourier!.displayName}',
        style: AppTypography.caption.copyWith(color: AppColors.success),
      );
    }
    return Text(
      'Kurye atanmadı',
      style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
    );
  }
}
