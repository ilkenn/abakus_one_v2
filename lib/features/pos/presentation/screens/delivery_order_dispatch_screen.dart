import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/courier_type.dart';
import '../../../courier/data/courier_dispatch_gateway.dart';
import '../../../courier/domain/identity/courier.dart';
import '../../../courier/presentation/widgets/courier_assignment_dialog.dart';
import '../../../orders/domain/models/order.dart';
import '../../../orders/domain/models/order_status.dart';
import '../../data/courier_pool_gateway.dart';
import '../../domain/delivery_neighborhood_clusterer.dart';
import '../providers/courier_dispatch_dependencies_provider.dart';
import '../widgets/print_courier_slip_action.dart';
import '../providers/pos_workspace_providers.dart';
import 'pos_courier_settlement_screen.dart';

/// AP-6 Sprint 2/3 — the branch's active delivery orders (`ready`/
/// `readyForPickup`/`outForDelivery`), grouped into neighborhood cluster
/// cards, each with its courier-assignment state, pickup-location
/// indicator, and a "Kurye Ata" action; a checkbox per row plus a bottom
/// action bar lets the cashier batch-assign several orders to one courier
/// at once. No existing delivery-order-detail screen exists anywhere in
/// POS/Admin to extend (confirmed by research) — this is genuinely new UI.
/// Design tokens (`AppColors`/`AppTypography`/`AppSpacing`) only.
class DeliveryOrderDispatchScreen extends ConsumerStatefulWidget {
  const DeliveryOrderDispatchScreen({
    super.key,
    required this.organizationId,
    required this.branchId,
  });

  final String organizationId;
  final String branchId;

  @override
  ConsumerState<DeliveryOrderDispatchScreen> createState() =>
      _DeliveryOrderDispatchScreenState();
}

class _DeliveryOrderDispatchScreenState
    extends ConsumerState<DeliveryOrderDispatchScreen> {
  /// `null` means "Tümü" (every neighborhood) — no filter applied.
  String? _selectedNeighborhoodFilter;
  final Set<String> _selectedOrderIds = {};

  bool _isOrderSelectable(Order order) =>
      order.courierType != CourierType.marketplace;

  String? _assigningOrderId;

  /// 2026-11-11 (Faz 2b) — pick the returning courier, then close their
  /// account on [PosCourierSettlementScreen].
  Future<void> _openSettlement(List<Courier> couriers) async {
    final ctx = ref.read(posDeviceContextProvider);
    if (ctx == null) return;
    final candidates = couriers
        .where(
            (c) => c.type == CourierType.internal || c.type == CourierType.pool)
        .map((c) => (c.id, c.displayName, c.activeOrderIds.length))
        .toList();
    // Faz 3a — an external courier is region-based and may be registered
    // at another branch: offer every courier carrying one of this branch's
    // packages too (name from the order's planned courier).
    final orders = ref
            .read(assignableDeliveryOrdersProvider(widget.branchId))
            .valueOrNull ??
        const <Order>[];
    final known = {for (final c in candidates) c.$1};
    final carried = <String, (String, int)>{};
    for (final order in orders) {
      final id = order.assignedCourierId;
      if (id == null ||
          known.contains(id) ||
          order.status != OrderStatus.outForDelivery) {
        continue;
      }
      final previous = carried[id];
      carried[id] = (
        order.plannedCourierName ?? previous?.$1 ?? 'Dış Kurye',
        (previous?.$2 ?? 0) + 1,
      );
    }
    candidates
      ..addAll([
        for (final e in carried.entries) (e.key, e.value.$1, e.value.$2),
      ])
      ..sort((a, b) => b.$3.compareTo(a.$3));
    final courierId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Hangi kurye döndü?'),
        children: [
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text('Bu şubede kayıtlı kurye yok.'),
            ),
          for (final courier in candidates)
            SimpleDialogOption(
              key: Key('settleCourier-${courier.$1}'),
              onPressed: () => Navigator.of(dialogContext).pop(courier.$1),
              child: Text('${courier.$2} · ${courier.$3} açık sipariş'),
            ),
        ],
      ),
    );
    if (courierId == null || !mounted) return;
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) =>
          PosCourierSettlementScreen(ctx: ctx, courierId: courierId),
    ));
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// 2026-11-11 (Faz 2) — one tap assigns the order to the courier staff
  /// planned when opening it (product owner: never automatically — the
  /// courier may not be at the shop). Same `assignCourierToOrder` call as
  /// the "Kurye Ata" dialog; the server only accepts a ready order.
  Future<void> _assignPlannedCourier(Order order) async {
    final courierId = order.plannedCourierId;
    if (courierId == null || _assigningOrderId != null) return;
    setState(() => _assigningOrderId = order.id.value);
    try {
      await ref
          .read(courierDispatchGatewayProvider)
          .assignCourierToOrder(orderId: order.id.value, courierId: courierId);
      if (mounted) {
        _snack('${order.orderNumber.value} '
            '${order.plannedCourierName ?? 'kuryeye'} atandı.');
      }
    } on CourierDispatchException catch (error) {
      if (!mounted) return;
      _snack(switch (error.code) {
        'failed-precondition' ||
        'failed_precondition' =>
          'Sipariş henüz hazır değil ya da kurye müsait değil; mutfak '
              'hazır dediğinde tekrar deneyin.',
        'permission-denied' ||
        'permission_denied' =>
          'Kurye atama yetkiniz yok.',
        _ => 'Kurye atanamadı. Lütfen tekrar deneyin.',
      });
    } finally {
      if (mounted) setState(() => _assigningOrderId = null);
    }
  }

  String? _poolBusyOrderId;

  /// 2026-11-12 (Faz 3a) — "Havuza Gönder" / "Havuzdan Geri Al".
  Future<void> _togglePool(Order order) async {
    if (_poolBusyOrderId != null) return;
    final publish = !order.isInDeliveryPool;
    setState(() => _poolBusyOrderId = order.id.value);
    try {
      final gateway = ref.read(courierPoolGatewayProvider);
      if (publish) {
        await gateway.publish(orderId: order.id.value);
      } else {
        await gateway.withdraw(orderId: order.id.value);
      }
      if (mounted) {
        _snack(publish
            ? '${order.orderNumber.value} dış kurye havuzuna gönderildi.'
            : '${order.orderNumber.value} havuzdan geri alındı.');
      }
    } on CourierPoolException catch (error) {
      if (!mounted) return;
      _snack(error.isPermissionDenied
          ? 'Havuz işlemi için yetkiniz yok.'
          : error.message.contains('district')
              ? 'Siparişin teslimat bölgesi (ilçe) belirlenemedi; şube '
                  'hizmet bölgelerini kontrol edin.'
              : 'Havuz işlemi yapılamadı. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _poolBusyOrderId = null);
    }
  }

  /// Rings once per newly arrived pool request (the QR-bell alert sound).
  final Set<String> _seenRequestIds = {};
  bool _requestsPrimed = false;

  void _onRequests(List<CourierPoolRequest> requests) {
    final ids = {for (final r in requests) r.requestId};
    final fresh = ids.difference(_seenRequestIds);
    _seenRequestIds
      ..clear()
      ..addAll(ids);
    if (_requestsPrimed && fresh.isNotEmpty) {
      SystemSound.play(SystemSoundType.alert);
    }
    _requestsPrimed = true;
  }

  Future<void> _openRequests() => showDialog<void>(
        context: context,
        builder: (_) => CourierPoolRequestsDialog(
          organizationId: widget.organizationId,
          branchId: widget.branchId,
        ),
      );

  void _toggleSelection(String orderId, bool selected) {
    setState(() {
      if (selected) {
        _selectedOrderIds.add(orderId);
      } else {
        _selectedOrderIds.remove(orderId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync =
        ref.watch(assignableDeliveryOrdersProvider(widget.branchId));
    final couriersAsync =
        ref.watch(allCouriersForBranchProvider(widget.branchId));
    final requestScope =
        (organizationId: widget.organizationId, branchId: widget.branchId);
    ref.listen(pendingCourierPoolRequestsProvider(requestScope), (_, next) {
      final requests = next.valueOrNull;
      if (requests != null) _onRequests(requests);
    });
    final pendingRequests = ref
            .watch(pendingCourierPoolRequestsProvider(requestScope))
            .valueOrNull ??
        const <CourierPoolRequest>[];
    final requestCountByOrder = <String, int>{};
    for (final r in pendingRequests) {
      requestCountByOrder[r.orderId] =
          (requestCountByOrder[r.orderId] ?? 0) + 1;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kurye Dağıtımı'),
        actions: [
          // 2026-11-12 (Faz 3a) — external couriers' pool requests, live.
          TextButton.icon(
            key: const Key('openPoolRequestsButton'),
            icon: Badge(
              isLabelVisible: pendingRequests.isNotEmpty,
              label: Text('${pendingRequests.length}'),
              child: const Icon(Icons.notifications_active_outlined),
            ),
            label: const Text('Havuz Talepleri'),
            onPressed: _openRequests,
          ),
          // 2026-11-11 (Faz 2b) — closing a returning courier's account
          // needs the till's trusted device (and its cash session), so it
          // is offered on the POS only, not in the Admin panel.
          if (ref.watch(posDeviceContextProvider) != null)
            TextButton.icon(
              key: const Key('openCourierSettlementButton'),
              icon: const Icon(Icons.point_of_sale_rounded),
              label: const Text('Kurye Hesap Kapat'),
              onPressed: () => _openSettlement(
                  couriersAsync.valueOrNull ?? const <Courier>[]),
            ),
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: 'Dış Restoran Siparişi Kaydet',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _RegisterConsortiumOrderDialog(
                organizationId: widget.organizationId,
                branchId: widget.branchId,
              ),
            ),
          ),
        ],
      ),
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
            for (final courier
                in couriersAsync.valueOrNull ?? const <Courier>[])
              courier.id: courier,
          };
          final clusters = DeliveryNeighborhoodClusterer.cluster(orders);
          final visibleClusters = _selectedNeighborhoodFilter == null
              ? clusters
              : clusters
                  .where(
                      (c) => c.neighborhoodName == _selectedNeighborhoodFilter)
                  .toList();

          return Column(
            children: [
              if (clusters.length > 1)
                _NeighborhoodFilterRow(
                  clusters: clusters,
                  selected: _selectedNeighborhoodFilter,
                  onSelected: (value) =>
                      setState(() => _selectedNeighborhoodFilter = value),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xxxl,
                  ),
                  children: [
                    for (final cluster in visibleClusters)
                      _ClusterCard(
                        cluster: cluster,
                        assignedCourierOf: (order) =>
                            order.assignedCourierId == null
                                ? null
                                : couriersById[order.assignedCourierId],
                        selectedOrderIds: _selectedOrderIds,
                        isOrderSelectable: _isOrderSelectable,
                        onSelectionChanged: _toggleSelection,
                        assigningOrderId: _assigningOrderId,
                        onAssignPlanned: _assignPlannedCourier,
                        poolBusyOrderId: _poolBusyOrderId,
                        onTogglePool: _togglePool,
                        requestCountOf: (order) =>
                            requestCountByOrder[order.id.value] ?? 0,
                        onPrintSlip: (order) => printCourierSlip(
                          context: context,
                          ref: ref,
                          branchId: widget.branchId,
                          orderId: order.id.value,
                          isCopy: true,
                        ),
                        onAssign: (order) => showDialog<void>(
                          context: context,
                          builder: (_) => CourierAssignmentDialog(
                            organizationId: widget.organizationId,
                            branchId: widget.branchId,
                            orderId: order.id.value,
                            courierType: order.courierType,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
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
      bottomNavigationBar: _selectedOrderIds.isEmpty
          ? null
          : _BatchAssignBar(
              count: _selectedOrderIds.length,
              onAssign: () async {
                await showDialog<void>(
                  context: context,
                  builder: (_) => CourierAssignmentDialog.batch(
                    organizationId: widget.organizationId,
                    branchId: widget.branchId,
                    orderIds: _selectedOrderIds.toList(),
                  ),
                );
                if (mounted) setState(_selectedOrderIds.clear);
              },
            ),
    );
  }
}

class _NeighborhoodFilterRow extends StatelessWidget {
  const _NeighborhoodFilterRow({
    required this.clusters,
    required this.selected,
    required this.onSelected,
  });

  final List<NeighborhoodCluster> clusters;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label: const Text('Tümü'),
                selected: selected == null,
                onSelected: (_) => onSelected(null),
              ),
            ),
            for (final cluster in clusters)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: ChoiceChip(
                  label: Text(
                    '${cluster.neighborhoodName ?? "Diğer"} (${cluster.orders.length})',
                  ),
                  selected: selected == cluster.neighborhoodName,
                  onSelected: (_) => onSelected(cluster.neighborhoodName),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ClusterCard extends StatelessWidget {
  const _ClusterCard({
    required this.cluster,
    required this.assignedCourierOf,
    required this.selectedOrderIds,
    required this.isOrderSelectable,
    required this.onSelectionChanged,
    required this.onAssign,
    required this.onAssignPlanned,
    required this.onPrintSlip,
    required this.assigningOrderId,
    required this.poolBusyOrderId,
    required this.onTogglePool,
    required this.requestCountOf,
  });

  final void Function(Order order) onAssignPlanned;
  final void Function(Order order) onPrintSlip;
  final String? assigningOrderId;
  final String? poolBusyOrderId;
  final void Function(Order order) onTogglePool;
  final int Function(Order order) requestCountOf;

  final NeighborhoodCluster cluster;
  final Courier? Function(Order order) assignedCourierOf;
  final Set<String> selectedOrderIds;
  final bool Function(Order order) isOrderSelectable;
  final void Function(String orderId, bool selected) onSelectionChanged;
  final void Function(Order order) onAssign;

  @override
  Widget build(BuildContext context) {
    final title = cluster.neighborhoodName == null
        ? 'Diğer (${cluster.orders.length} Paket)'
        : '${cluster.neighborhoodName} Bölgesi (${cluster.orders.length} Paket)';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: const BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: AppRadius.kLarge,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final order in cluster.orders)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _DeliveryOrderRow(
                  order: order,
                  assignedCourier: assignedCourierOf(order),
                  isSelectable: isOrderSelectable(order),
                  isSelected: selectedOrderIds.contains(order.id.value),
                  onSelectionChanged: (selected) =>
                      onSelectionChanged(order.id.value, selected),
                  onAssign: () => onAssign(order),
                  onAssignPlanned: () => onAssignPlanned(order),
                  onPrintSlip: () => onPrintSlip(order),
                  isAssigning: assigningOrderId == order.id.value,
                  isPoolBusy: poolBusyOrderId == order.id.value,
                  onTogglePool: () => onTogglePool(order),
                  poolRequestCount: requestCountOf(order),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryOrderRow extends StatelessWidget {
  const _DeliveryOrderRow({
    required this.order,
    required this.assignedCourier,
    required this.isSelectable,
    required this.isSelected,
    required this.onSelectionChanged,
    required this.onAssign,
    required this.onAssignPlanned,
    required this.onPrintSlip,
    required this.isAssigning,
    required this.isPoolBusy,
    required this.onTogglePool,
    required this.poolRequestCount,
  });

  final VoidCallback onAssignPlanned;
  final VoidCallback onPrintSlip;
  final bool isAssigning;
  final bool isPoolBusy;
  final VoidCallback onTogglePool;
  final int poolRequestCount;

  final Order order;
  final Courier? assignedCourier;
  final bool isSelectable;
  final bool isSelected;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final isMarketplace = order.courierType == CourierType.marketplace;
    // Faz 3a — a package without any courier (assigned or reserved) can be
    // sent to / taken back from the external-courier pool.
    final canUsePool = !isMarketplace &&
        order.assignedCourierId == null &&
        (order.plannedCourierId == null || order.isInDeliveryPool);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.kMedium,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Checkbox(
            value: isSelected,
            onChanged: isSelectable
                ? (value) => onSelectionChanged(value ?? false)
                : null,
          ),
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
                _PickupLocationIndicator(merchantName: order.merchantName),
                const SizedBox(height: AppSpacing.xs),
                _CourierStateBadge(
                  isMarketplace: isMarketplace,
                  assignedCourier: assignedCourier,
                ),
                _DeliveryProgressLabel(
                    order: order, poolRequestCount: poolRequestCount),
                // 2026-11-11 (Faz 2) — the courier note and the planned
                // courier of a staff-opened Paket Servis order.
                if (order.customerNote.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'Kurye Notu: ${order.customerNote.trim()}',
                      key: Key('courierNote-${order.id.value}'),
                      style: AppTypography.bodySmall.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                if (order.plannedCourierName != null &&
                    order.assignedCourierId == null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'Planlanan kurye: ${order.plannedCourierName}',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: Key('reprintSlip-${order.id.value}'),
            icon: const Icon(Icons.print_rounded),
            tooltip: 'Kurye Fişini Tekrar Yazdır',
            onPressed: onPrintSlip,
          ),
          if (isMarketplace)
            const SizedBox.shrink()
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (canUsePool)
                  OutlinedButton.icon(
                    key: Key('togglePool-${order.id.value}'),
                    icon: isPoolBusy
                        ? const SizedBox.square(
                            dimension: AppSpacing.md,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(order.isInDeliveryPool
                            ? Icons.undo_rounded
                            : Icons.groups_rounded),
                    label: Text(order.isInDeliveryPool
                        ? 'Havuzdan Geri Al'
                        : 'Havuza Gönder'),
                    onPressed: isPoolBusy ? null : onTogglePool,
                  ),
                if (order.plannedCourierId != null &&
                    order.assignedCourierId == null &&
                    !order.isInDeliveryPool)
                  ElevatedButton.icon(
                    key: Key('assignPlanned-${order.id.value}'),
                    icon: isAssigning
                        ? const SizedBox.square(
                            dimension: AppSpacing.md,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.two_wheeler_rounded),
                    label: Text('${order.plannedCourierName ?? 'Kurye'} Ata'),
                    onPressed: isAssigning ? null : onAssignPlanned,
                  ),
                TextButton(onPressed: onAssign, child: const Text('Kurye Ata')),
              ],
            ),
        ],
      ),
    );
  }
}

class _PickupLocationIndicator extends StatelessWidget {
  const _PickupLocationIndicator({required this.merchantName});

  final String? merchantName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          merchantName == null
              ? Icons.storefront_rounded
              : Icons.storefront_outlined,
          size: 14,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          merchantName ?? 'Kendi Dükkanımız',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// 2026-11-12 (Faz 3a) — where the package is: still in the kitchen, in
/// the external-courier pool (with its request count), on the road, or
/// "Teslim Edildi — Mutabakat Bekliyor" after the courier's "Teslim Ettim".
class _DeliveryProgressLabel extends StatelessWidget {
  const _DeliveryProgressLabel(
      {required this.order, required this.poolRequestCount});

  final Order order;
  final int poolRequestCount;

  @override
  Widget build(BuildContext context) {
    final (String?, Color) label;
    if (order.courierReportedDelivered) {
      label = ('Teslim Edildi — Mutabakat Bekliyor', AppColors.warning);
    } else if (order.courierDeparted &&
        order.status == OrderStatus.outForDelivery) {
      label = ('Kurye yolda', AppColors.success);
    } else if (order.isInDeliveryPool) {
      label = (
        poolRequestCount > 0
            ? 'Havuzda · $poolRequestCount kurye talebi'
            : 'Havuzda · talep bekleniyor',
        AppColors.info,
      );
    } else if (order.status == OrderStatus.confirmed ||
        order.status == OrderStatus.preparing) {
      label = ('Mutfakta hazırlanıyor', AppColors.textSecondary);
    } else {
      label = (null, AppColors.textSecondary);
    }
    final text = label.$1;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        text,
        key: Key('deliveryProgress-${order.id.value}'),
        style: AppTypography.caption
            .copyWith(color: label.$2, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// 2026-11-12 (Faz 3a) — the branch's pending external-courier requests;
/// approving one assigns (or, still in the kitchen, reserves) the package
/// for that courier and the server rejects the other requests for it.
class CourierPoolRequestsDialog extends ConsumerStatefulWidget {
  const CourierPoolRequestsDialog({
    super.key,
    required this.organizationId,
    required this.branchId,
  });

  final String organizationId;
  final String branchId;

  @override
  ConsumerState<CourierPoolRequestsDialog> createState() =>
      _CourierPoolRequestsDialogState();
}

class _CourierPoolRequestsDialogState
    extends ConsumerState<CourierPoolRequestsDialog> {
  String? _busyRequestId;
  String? _error;

  static String _tl(int minorUnits) {
    final whole = minorUnits ~/ 100;
    final cents = minorUnits % 100;
    return cents == 0
        ? '$whole TL'
        : '$whole,${cents.toString().padLeft(2, '0')} TL';
  }

  Future<void> _respond(CourierPoolRequest request, bool approve) async {
    setState(() {
      _busyRequestId = request.requestId;
      _error = null;
    });
    try {
      await ref
          .read(courierPoolGatewayProvider)
          .respond(requestId: request.requestId, approve: approve);
    } on CourierPoolException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.isPermissionDenied
          ? 'Kurye taleplerini onaylama yetkiniz yok.'
          : 'Talep yanıtlanamadı (paket başka kuryeye verilmiş ya da '
              'havuzdan alınmış olabilir).');
    } finally {
      if (mounted) setState(() => _busyRequestId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(pendingCourierPoolRequestsProvider(
        (organizationId: widget.organizationId, branchId: widget.branchId)));
    return AlertDialog(
      title: const Text('Dış Kurye Talepleri'),
      content: SizedBox(
        width: 460,
        child: requestsAsync.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => const Text('Talepler yüklenemedi.'),
          data: (requests) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (requests.isEmpty)
                  const Text('Bekleyen kurye talebi yok.',
                      key: Key('noPoolRequests')),
                for (final request in requests)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Container(
                      key: Key('poolRequest-${request.requestId}'),
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.kMedium,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${request.courierName} → '
                                  '${request.orderNumber}',
                                  style: AppTypography.labelLarge,
                                ),
                                Text(
                                  '${request.neighborhoodName} · '
                                  '${_tl(request.amountDueMinorUnits)}',
                                  style: AppTypography.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            key: Key('rejectPoolRequest-${request.requestId}'),
                            onPressed: _busyRequestId == null
                                ? () => _respond(request, false)
                                : null,
                            child: const Text('Reddet'),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          FilledButton(
                            key: Key('approvePoolRequest-${request.requestId}'),
                            onPressed: _busyRequestId == null
                                ? () => _respond(request, true)
                                : null,
                            child: Text(_busyRequestId == request.requestId
                                ? '...'
                                : 'Onayla'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_error != null)
                  Text(_error!,
                      key: const Key('poolRequestError'),
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.error)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
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

class _BatchAssignBar extends StatelessWidget {
  const _BatchAssignBar({required this.count, required this.onAssign});

  final int count;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$count Paket Seçildi',
                style: AppTypography.bodyMedium,
              ),
            ),
            FilledButton(
              onPressed: onAssign,
              child: const Text('Tek Kuryeye Ata'),
            ),
          ],
        ),
      ),
    );
  }
}

/// AP-6 Sprint 3 — the lightweight inline "Dış Restoran Siparişi Kaydet"
/// quick-add, mirrors `CourierAssignmentDialog`'s own inline-quick-add
/// precedent rather than a new full screen (see
/// `registerConsortiumOrder.ts`'s own scope note).
class _RegisterConsortiumOrderDialog extends ConsumerStatefulWidget {
  const _RegisterConsortiumOrderDialog({
    required this.organizationId,
    required this.branchId,
  });

  final String organizationId;
  final String branchId;

  @override
  ConsumerState<_RegisterConsortiumOrderDialog> createState() =>
      _RegisterConsortiumOrderDialogState();
}

class _RegisterConsortiumOrderDialogState
    extends ConsumerState<_RegisterConsortiumOrderDialog> {
  final _merchantNameController = TextEditingController();
  final _pickupAddressController = TextEditingController();
  final _feeController = TextEditingController();
  final _contactFirstNameController = TextEditingController();
  final _contactLastNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _dropoffAddressController = TextEditingController();
  final _neighborhoodController = TextEditingController();

  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _merchantNameController.dispose();
    _pickupAddressController.dispose();
    _feeController.dispose();
    _contactFirstNameController.dispose();
    _contactLastNameController.dispose();
    _contactPhoneController.dispose();
    _dropoffAddressController.dispose();
    _neighborhoodController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_isSubmitting &&
      _merchantNameController.text.trim().isNotEmpty &&
      _pickupAddressController.text.trim().isNotEmpty &&
      _feeController.text.trim().isNotEmpty &&
      _contactFirstNameController.text.trim().isNotEmpty &&
      _contactPhoneController.text.trim().isNotEmpty &&
      _dropoffAddressController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    final feeMinorUnits = int.tryParse(_feeController.text.trim());
    if (feeMinorUnits == null || feeMinorUnits < 0) {
      setState(() => _error = 'Teslimat ücreti geçerli bir tam sayı olmalı.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref.read(courierDispatchGatewayProvider).registerConsortiumOrder(
            organizationId: widget.organizationId,
            branchId: widget.branchId,
            merchantId: _merchantNameController.text.trim(),
            merchantName: _merchantNameController.text.trim(),
            pickupAddress: _pickupAddressController.text.trim(),
            consortiumDeliveryFeeMinorUnits: feeMinorUnits,
            contactFirstName: _contactFirstNameController.text.trim(),
            contactLastName: _contactLastNameController.text.trim(),
            contactPhone: _contactPhoneController.text.trim(),
            dropoffAddressDescription: _dropoffAddressController.text.trim(),
            dropoffNeighborhoodName: _neighborhoodController.text.trim().isEmpty
                ? null
                : _neighborhoodController.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context);
    } on CourierDispatchException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dış Restoran Siparişi Kaydet'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _merchantNameController,
                decoration: const InputDecoration(labelText: 'Restoran Adı'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _pickupAddressController,
                decoration: const InputDecoration(labelText: 'Alım Adresi'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _feeController,
                decoration:
                    const InputDecoration(labelText: 'Teslimat Ücreti (kuruş)'),
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Müşteri Bilgileri', style: AppTypography.bodyMedium),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _contactFirstNameController,
                decoration: const InputDecoration(labelText: 'Ad'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _contactLastNameController,
                decoration: const InputDecoration(labelText: 'Soyad'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _contactPhoneController,
                decoration: const InputDecoration(labelText: 'Telefon'),
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _neighborhoodController,
                decoration:
                    const InputDecoration(labelText: 'Mahalle (kümeleme için)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _dropoffAddressController,
                decoration: const InputDecoration(labelText: 'Teslimat Adresi'),
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: AppRadius.kMedium,
                  ),
                  child: Text(
                    _error!,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(_isSubmitting ? 'Kaydediliyor...' : 'Kaydet'),
        ),
      ],
    );
  }
}
