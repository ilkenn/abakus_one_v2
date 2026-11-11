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
import '../../../admin/data/takeaway_order_response_gateway.dart';
import '../../../admin/presentation/providers/admin_dependencies_provider.dart';
import '../../../orders/domain/models/order.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../orders/domain/models/order_status.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../data/kitchen_action_gateway.dart';
import '../../data/pos_action_gateway.dart' show PosDeviceContext;
import '../providers/kds_dependencies_provider.dart';
import 'pos_new_takeaway_order_screen.dart';

/// Adım 5 (2026-11-07) — "Paket / Gel-Al" POS screen. Replaces the
/// Masalar 5-tab area filter's disclosed placeholder (ADR-060) for the
/// `takeaway` tab with a real, basic interface: lists this branch's
/// takeaway orders live, lets staff confirm/reject a newly-placed one
/// (reusing `TakeawayOrderResponseGateway`, previously wired to zero
/// client callers anywhere in this app — see that file's own doc
/// comment) and advance an already-confirmed one through
/// `preparing -> ready -> completed` (reusing `KitchenActionGateway
/// .advanceOrderStatus`, the exact same dispatch the KDS board already
/// uses for every channel), and opens [PosNewTakeawayOrderScreen] for a
/// staff-initiated new order.
///
/// **Turkish status labels corrected against the real backend lifecycle**
/// (`advanceTakeawayOrderStatus.ts`'s own `confirmed -> preparing ->
/// ready -> completed`, user-confirmed via Decision Review): no "Yolda"
/// step exists for pickup — that's `outForDelivery`, a delivery-only
/// concept. Reuses the exact Turkish strings `admin_orders_screen.dart`'s
/// own (file-private) `_statusLabel` already established for app-wide
/// consistency, rather than inventing new wording for the same statuses.
class PosTakeawayOrdersScreen extends ConsumerWidget {
  const PosTakeawayOrdersScreen({super.key, required this.ctx});

  final PosDeviceContext ctx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(takeawayOrdersForBranchProvider(ctx));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
          child: Row(
            children: [
              const Expanded(
                child: Text('Gel-Al Siparişleri',
                    style: AppTypography.titleMedium),
              ),
              ElevatedButton.icon(
                key: const Key('newTakeawayOrderButton'),
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('Yeni Gel-Al Siparişi'),
                onPressed: () async {
                  final created = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => PosNewTakeawayOrderScreen(ctx: ctx),
                    ),
                  );
                  if (created == true) {
                    ref.invalidate(takeawayOrdersForBranchProvider(ctx));
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ordersAsync.when(
            loading: () =>
                const LoadingView(message: 'Paket siparişler yükleniyor...'),
            error: (error, stackTrace) => ErrorView(
              message: 'Paket siparişler yüklenemedi.',
              retryLabel: 'Yeniden Dene',
              onRetry: () =>
                  ref.invalidate(takeawayOrdersForBranchProvider(ctx)),
            ),
            data: (orders) {
              if (orders.isEmpty) {
                return const EmptyView(
                  icon: Icons.takeout_dining_outlined,
                  message: 'Şu anda aktif paket/gel-al siparişi yok.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                itemCount: orders.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _TakeawayOrderCard(
                    order: orders[index],
                    ctx: ctx,
                    onChanged: () =>
                        ref.invalidate(takeawayOrdersForBranchProvider(ctx)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Live, branch-scoped takeaway orders still worth a staff action —
/// mirrors `adminOrdersProvider`'s own `watchByBranch` shape, filtered to
/// `channel == takeaway` and the statuses a staff member can still act
/// on. `completed`/`cancelled`/`rejected`/`refunded` orders fall out of
/// this list on their own next update — this screen's job is "what needs
/// doing now," not order history (the Admin Siparişler screen already
/// covers that).
final takeawayOrdersForBranchProvider =
    StreamProvider.family<List<Order>, PosDeviceContext>((ref, ctx) {
  final repository = ref.watch(canonicalOrderRepositoryProvider);
  return repository
      .watchByBranch(organizationId: ctx.organizationId, branchId: ctx.branchId)
      .map((orders) {
    final active = orders
        .where((order) =>
            order.channel == OrderChannel.takeaway &&
            (order.status == OrderStatus.pendingConfirmation ||
                order.status == OrderStatus.confirmed ||
                order.status == OrderStatus.preparing ||
                order.status == OrderStatus.ready))
        .toList();
    active.sort((a, b) => a.timestamps.created.compareTo(b.timestamps.created));
    return active;
  });
});

String takeawayStatusLabel(OrderStatus status) {
  switch (status) {
    case OrderStatus.pendingConfirmation:
      return 'Onay Bekliyor';
    case OrderStatus.confirmed:
      return 'Onaylandı';
    case OrderStatus.preparing:
      return 'Hazırlanıyor';
    case OrderStatus.ready:
      return 'Hazır, Gelip Alabilir';
    case OrderStatus.completed:
      return 'Tamamlandı';
    default:
      return status.name;
  }
}

Color _takeawayStatusColor(OrderStatus status) {
  switch (status) {
    case OrderStatus.ready:
    case OrderStatus.completed:
      return AppColors.success;
    case OrderStatus.preparing:
      return AppColors.warning;
    default:
      return AppColors.textSecondary;
  }
}

String _rejectionReasonLabel(TakeawayRejectionReasonCode code) {
  switch (code) {
    case TakeawayRejectionReasonCode.itemUnavailable:
      return 'Ürün stokta yok';
    case TakeawayRejectionReasonCode.kitchenUnavailable:
      return 'Mutfak müsait değil';
    case TakeawayRejectionReasonCode.capacityUnavailable:
      return 'Kapasite yetersiz';
    case TakeawayRejectionReasonCode.operationalIssue:
      return 'Operasyonel sorun';
    case TakeawayRejectionReasonCode.other:
      return 'Diğer';
  }
}

class _TakeawayOrderCard extends ConsumerWidget {
  const _TakeawayOrderCard({
    required this.order,
    required this.ctx,
    required this.onChanged,
  });

  final Order order;
  final PosDeviceContext ctx;
  final VoidCallback onChanged;

  String get _contactName {
    final first = order.contactFirstName ?? '';
    final last = order.contactLastName ?? '';
    final full = '$first $last'.trim();
    return full.isEmpty ? 'İsimsiz Müşteri' : full;
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(takeawayOrderResponseGatewayProvider)
          .confirm(orderId: order.id.value);
      onChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sipariş onaylandı.')));
    } on TakeawayOrderResponseException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    TakeawayRejectionReasonCode selected =
        TakeawayRejectionReasonCode.itemUnavailable;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Siparişi Reddet'),
          content: RadioGroup<TakeawayRejectionReasonCode>(
            groupValue: selected,
            onChanged: (value) => setState(() => selected = value!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final code in TakeawayRejectionReasonCode.values)
                  RadioListTile<TakeawayRejectionReasonCode>(
                    value: code,
                    title: Text(_rejectionReasonLabel(code)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reddet'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(takeawayOrderResponseGatewayProvider)
          .reject(orderId: order.id.value, reasonCode: selected);
      onChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sipariş reddedildi.')));
    } on TakeawayOrderResponseException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _advance(
      BuildContext context, WidgetRef ref, String targetStatus) async {
    try {
      await ref.read(kitchenActionGatewayProvider).advanceOrderStatus(
            orderId: order.id.value,
            channel: 'takeaway',
            targetStatus: targetStatus,
          );
      onChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Durum güncellendi: ${takeawayStatusLabel(
        OrderStatus.values.firstWhere((s) => s.name == targetStatus),
      )}')));
    } on KitchenActionException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget? _actionButton(BuildContext context, WidgetRef ref) {
    switch (order.status) {
      case OrderStatus.confirmed:
        return ElevatedButton(
          onPressed: () => _advance(context, ref, 'preparing'),
          child: const Text('Hazırlanıyor Olarak İşaretle'),
        );
      case OrderStatus.preparing:
        return ElevatedButton(
          onPressed: () => _advance(context, ref, 'ready'),
          child: const Text('Hazır Olarak İşaretle'),
        );
      case OrderStatus.ready:
        return ElevatedButton(
          onPressed: () => _advance(context, ref, 'completed'),
          child: const Text('Teslim Edildi'),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = _takeawayStatusColor(order.status);
    final actionButton = _actionButton(context, ref);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${order.orderNumber.value} — $_contactName',
                  style: AppTypography.bodyMedium
                      .copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: AppRadius.kPill,
                ),
                child: Text(
                  takeawayStatusLabel(order.status),
                  style: AppTypography.bodySmall.copyWith(
                      color: statusColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (order.contactPhone != null && order.contactPhone!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(order.contactPhone!,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary)),
            ),
          const SizedBox(height: AppSpacing.sm),
          for (final line in order.lines)
            Text('${line.quantity}x ${line.productName}',
                style: AppTypography.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (order.status == OrderStatus.pendingConfirmation) ...[
                TextButton(
                  onPressed: () => _reject(context, ref),
                  child: const Text('Reddet'),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton(
                  onPressed: () => _confirm(context, ref),
                  child: const Text('Onayla'),
                ),
              ] else if (actionButton != null)
                actionButton,
            ],
          ),
        ],
      ),
    );
  }
}
