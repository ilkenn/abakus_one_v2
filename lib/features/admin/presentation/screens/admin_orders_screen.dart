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
import '../../../orders/domain/models/dine_in_line_status.dart';
import '../../../orders/domain/models/order.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../orders/domain/models/order_status.dart';
import '../../data/dine_in_order_response_gateway.dart';
import '../../data/takeaway_order_response_gateway.dart';
import '../providers/admin_dependencies_provider.dart';
import '../providers/admin_orders_provider.dart';

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

String _statusLabel(OrderStatus status) {
  switch (status) {
    case OrderStatus.created:
      return 'Oluşturuldu';
    case OrderStatus.pendingConfirmation:
      return 'Onay Bekliyor';
    case OrderStatus.confirmed:
      return 'Onaylandı';
    case OrderStatus.preparing:
      return 'Hazırlanıyor';
    case OrderStatus.ready:
      return 'Hazır';
    case OrderStatus.outForDelivery:
      return 'Yolda';
    case OrderStatus.served:
      return 'Servis Edildi';
    case OrderStatus.completed:
      return 'Tamamlandı';
    case OrderStatus.cancelled:
      return 'İptal Edildi';
    case OrderStatus.rejected:
      return 'Reddedildi';
    case OrderStatus.refunded:
      return 'İade Edildi';
    case OrderStatus.scheduled:
      return 'Zamanlandı';
    case OrderStatus.readyForPickup:
      return 'Teslim Almaya Hazır';
  }
}

Color _statusColor(OrderStatus status) {
  switch (status) {
    case OrderStatus.completed:
    case OrderStatus.served:
    case OrderStatus.ready:
    case OrderStatus.readyForPickup:
      return AppColors.success;
    case OrderStatus.cancelled:
    case OrderStatus.rejected:
    case OrderStatus.refunded:
      return AppColors.error;
    default:
      return AppColors.warning;
  }
}

String _channelLabel(OrderChannel channel) {
  switch (channel) {
    case OrderChannel.dineInQr:
      return 'Masa (QR)';
    case OrderChannel.dineInStaff:
      return 'Masa (Personel)';
    case OrderChannel.takeaway:
      return 'Gel Al';
    case OrderChannel.delivery:
      return 'Teslimat';
    case OrderChannel.reservationPreorder:
      return 'Rezervasyon Ön Sipariş';
  }
}

/// 2026-10-28 launch — `" · İç Masa 1 (İç Mekan)"`-style suffix for a
/// dine-in order, so staff see which physical table it came from without
/// opening it. Empty for any order with no table snapshot (every non-table
/// channel, and any dine-in order placed before this field existed).
String _tableSuffix(String? tableNumber, String? tableSection) {
  if (tableNumber == null || tableNumber.isEmpty) return '';
  final section =
      (tableSection == null || tableSection.isEmpty) ? '' : ' ($tableSection)';
  return ' · $tableNumber$section';
}

String _formatDate(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Admin Siparişler — a branch-wide listing of every order (every status,
/// every channel), newest first. Reuses `CanonicalOrderRepository` (the
/// same store POS and customer checkout already share) rather than a
/// parallel repository — see `adminOrdersProvider`'s own doc comment.
///
/// **One real mutation, added 2026-10-28**: accept/reject for a
/// `pendingConfirmation` takeaway order (`respondToTakeawayOrder` —
/// `TakeawayOrderResponseGateway`). This was the missing link in the real
/// order lifecycle: a new order (any channel) starts `pendingConfirmation`
/// and only becomes Kitchen-visible once `confirmed`
/// (`acceptOrderLine.ts` materializes `kitchenWorkItems` on that exact
/// transition) — `respondToTakeawayOrder` already existed as a real,
/// tested Cloud Function but had zero client callers anywhere in this app
/// before this. Dine-in/delivery's own equivalents
/// (`respondToDineInOrderLines`/`respondToDeliveryOrder`) are a separate,
/// not-yet-wired follow-up — deliberately not built ahead of being asked
/// for. Every OTHER mutation (cancel/refund/status-advance) still lives on
/// its own channel-specific screen (POS, Kitchen, Courier) — this screen
/// does not grow into a general order-action console.
class AdminOrdersScreen extends ConsumerWidget {
  const AdminOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminOrdersProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Siparişler'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const LoadingView(message: 'Siparişler yükleniyor...'),
          error: (error, stack) => ErrorView(
            message: 'Siparişler yüklenemedi.',
            retryLabel: 'Tekrar dene',
            onRetry: () => ref.invalidate(adminOrdersProvider),
          ),
          data: (orders) {
            if (orders.isEmpty) {
              return const EmptyView(
                icon: Icons.receipt_long_outlined,
                message: 'Bu şubede henüz bir sipariş yok.',
              );
            }
            final sorted = [...orders]..sort(
                (a, b) => b.timestamps.created.compareTo(a.timestamps.created));
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: sorted.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final order = sorted[index];
                final isPending =
                    order.status == OrderStatus.pendingConfirmation;
                final canRespondTakeaway =
                    isPending && order.channel == OrderChannel.takeaway;
                final canRespondDineIn =
                    isPending && order.channel == OrderChannel.dineInQr;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: AppRadius.kMedium,
                    onTap: () => _openOrderDetail(context, ref, order),
                    child: AppCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.circle,
                                  size: 10, color: _statusColor(order.status)),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${order.orderNumber}',
                                        style: AppTypography.bodyMedium),
                                    Text(
                                      '${_channelLabel(order.channel)}'
                                      '${_tableSuffix(order.tableNumber, order.tableSection)} · '
                                      '${_formatDate(order.timestamps.created)}',
                                      style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${order.pricing.grandTotal}',
                                      style: AppTypography.bodyMedium),
                                  Text(_statusLabel(order.status),
                                      style: AppTypography.bodySmall.copyWith(
                                          color: _statusColor(order.status))),
                                ],
                              ),
                            ],
                          ),
                          if (canRespondTakeaway) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                  onPressed: () =>
                                      _reject(context, ref, order.id.value),
                                  child: const Text('Reddet'),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                ElevatedButton(
                                  onPressed: () =>
                                      _confirm(context, ref, order.id.value),
                                  child: const Text('Kabul Et'),
                                ),
                              ],
                            ),
                          ],
                          if (canRespondDineIn) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                  onPressed: () =>
                                      _rejectDineIn(context, ref, order),
                                  child: const Text('Reddet'),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                ElevatedButton(
                                  onPressed: () =>
                                      _confirmDineIn(context, ref, order),
                                  child: const Text('Onayla'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

Future<void> _confirm(
    BuildContext context, WidgetRef ref, String orderId) async {
  try {
    await ref
        .read(takeawayOrderResponseGatewayProvider)
        .confirm(orderId: orderId);
    ref.invalidate(adminOrdersProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Sipariş kabul edildi.')));
  } on TakeawayOrderResponseException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Future<void> _reject(
    BuildContext context, WidgetRef ref, String orderId) async {
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
        .reject(orderId: orderId, reasonCode: selected);
    ref.invalidate(adminOrdersProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Sipariş reddedildi.')));
  } on TakeawayOrderResponseException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// [Order.lineApprovalStates] is empty for an order that never carried the
/// per-line approval concept at all (every pre-AP-3 order, every non-
/// dine-in channel) — treated as "nothing pending," not an error.
List<int> _pendingDineInLineIndexes(Order order) {
  return [
    for (final state in order.lineApprovalStates)
      if (state.status == DineInLineStatus.pendingApproval) state.lineIndex,
  ];
}

Future<void> _confirmDineIn(
    BuildContext context, WidgetRef ref, Order order) async {
  try {
    await ref.read(dineInOrderResponseGatewayProvider).confirm(
          orderId: order.id.value,
          pendingLineIndexes: _pendingDineInLineIndexes(order),
        );
    ref.invalidate(adminOrdersProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Sipariş onaylandı.')));
  } on DineInOrderResponseException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Future<void> _rejectDineIn(
    BuildContext context, WidgetRef ref, Order order) async {
  DineInRejectionReasonCode selected =
      DineInRejectionReasonCode.itemUnavailable;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Siparişi Reddet'),
        content: RadioGroup<DineInRejectionReasonCode>(
          groupValue: selected,
          onChanged: (value) => setState(() => selected = value!),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final code in DineInRejectionReasonCode.values)
                RadioListTile<DineInRejectionReasonCode>(
                  value: code,
                  title: Text(_dineInRejectionReasonLabel(code)),
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
    await ref.read(dineInOrderResponseGatewayProvider).reject(
          orderId: order.id.value,
          reasonCode: selected,
        );
    ref.invalidate(adminOrdersProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Sipariş reddedildi.')));
  } on DineInOrderResponseException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.message)));
  }
}

String _dineInRejectionReasonLabel(DineInRejectionReasonCode code) {
  switch (code) {
    case DineInRejectionReasonCode.itemUnavailable:
      return 'Ürün stokta yok';
    case DineInRejectionReasonCode.kitchenUnavailable:
      return 'Mutfak müsait değil';
    case DineInRejectionReasonCode.capacityUnavailable:
      return 'Kapasite yetersiz';
    case DineInRejectionReasonCode.operationalIssue:
      return 'Operasyonel sorun';
    case DineInRejectionReasonCode.other:
      return 'Diğer';
  }
}

/// 2026-10-29 — tapping an order card opens this detail sheet (the
/// "sipariş detay modalı" gap): full line list, then the same accept/
/// reject actions the card itself offers for a `pendingConfirmation`
/// order. Read-only for every other status — this sheet never grows a
/// second, parallel set of lifecycle actions beyond accept/reject; kitchen-
/// side progress (preparing/ready/served) is the KDS board's own screen.
void _openOrderDetail(BuildContext context, WidgetRef ref, Order order) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _OrderDetailSheet(order: order),
  );
}

class _OrderDetailSheet extends ConsumerWidget {
  const _OrderDetailSheet({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPending = order.status == OrderStatus.pendingConfirmation;
    final canRespondTakeaway =
        isPending && order.channel == OrderChannel.takeaway;
    final canRespondDineIn =
        isPending && order.channel == OrderChannel.dineInQr;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${order.orderNumber}',
                      style: AppTypography.titleMedium),
                ),
                Text(_statusLabel(order.status),
                    style: AppTypography.bodyMedium
                        .copyWith(color: _statusColor(order.status))),
              ],
            ),
            Text(
              '${_channelLabel(order.channel)}'
              '${_tableSuffix(order.tableNumber, order.tableSection)} · '
              '${_formatDate(order.timestamps.created)}',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: order.lines.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final line = order.lines[index];
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${line.quantity}x ${line.productName}',
                          style: AppTypography.bodyMedium,
                        ),
                      ),
                      Text('${line.lineTotal}',
                          style: AppTypography.bodyMedium),
                    ],
                  );
                },
              ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Toplam', style: AppTypography.titleMedium),
                Text('${order.pricing.grandTotal}',
                    style: AppTypography.titleMedium),
              ],
            ),
            if (canRespondTakeaway || canRespondDineIn) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        if (canRespondTakeaway) {
                          _reject(context, ref, order.id.value);
                        } else {
                          _rejectDineIn(context, ref, order);
                        }
                      },
                      child: const Text('Reddet'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        if (canRespondTakeaway) {
                          _confirm(context, ref, order.id.value);
                        } else {
                          _confirmDineIn(context, ref, order);
                        }
                      },
                      child: Text(canRespondTakeaway ? 'Kabul Et' : 'Onayla'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
