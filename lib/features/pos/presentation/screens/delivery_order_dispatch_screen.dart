import 'package:flutter/material.dart';
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
import '../../domain/delivery_neighborhood_clusterer.dart';
import '../providers/courier_dispatch_dependencies_provider.dart';

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
    final ordersAsync = ref.watch(assignableDeliveryOrdersProvider(widget.branchId));
    final couriersAsync = ref.watch(allCouriersForBranchProvider(widget.branchId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kurye Dağıtımı'),
        actions: [
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
            for (final courier in couriersAsync.valueOrNull ?? const <Courier>[])
              courier.id: courier,
          };
          final clusters = DeliveryNeighborhoodClusterer.cluster(orders);
          final visibleClusters = _selectedNeighborhoodFilter == null
              ? clusters
              : clusters
                  .where((c) => c.neighborhoodName == _selectedNeighborhoodFilter)
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
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
  });

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
  });

  final Order order;
  final Courier? assignedCourier;
  final bool isSelectable;
  final bool isSelected;
  final ValueChanged<bool> onSelectionChanged;
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

class _PickupLocationIndicator extends StatelessWidget {
  const _PickupLocationIndicator({required this.merchantName});

  final String? merchantName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          merchantName == null ? Icons.storefront_rounded : Icons.storefront_outlined,
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
                decoration: const InputDecoration(labelText: 'Teslimat Ücreti (kuruş)'),
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
                decoration: const InputDecoration(labelText: 'Mahalle (kümeleme için)'),
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
                    style: AppTypography.bodySmall.copyWith(color: AppColors.error),
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
