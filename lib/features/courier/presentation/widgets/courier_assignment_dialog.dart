import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/courier_type.dart';
import '../../../pos/presentation/providers/courier_dispatch_dependencies_provider.dart';
import '../../data/courier_dispatch_gateway.dart';
import '../../domain/identity/courier.dart';

/// AP-6 Sprint 2 — the cashier dispatch dialog: FIFO-sorted available
/// couriers (first entry tagged "Önerilen (İlk Dönen)"), a plain "Ata"
/// action on every other one (staff override, no restriction), and a
/// lightweight inline quick-add. Mirrors `ReservationProposeChangeDialog`'s
/// shape (`AlertDialog` + `TextButton`/`FilledButton`, design tokens only).
///
/// If [courierType] is already [CourierType.marketplace], the whole dialog
/// renders a locked, no-action state instead — see `assignCourierToOrder.ts`'s
/// own `MarketplaceCourierImmutableViolation` doc comment for why.
class CourierAssignmentDialog extends ConsumerStatefulWidget {
  const CourierAssignmentDialog({
    super.key,
    required this.organizationId,
    required this.branchId,
    required this.orderId,
    required this.courierType,
  });

  final String organizationId;
  final String branchId;
  final String orderId;

  /// The order's current `courierType` — `null`/non-marketplace means
  /// assignment is allowed.
  final CourierType? courierType;

  @override
  ConsumerState<CourierAssignmentDialog> createState() =>
      _CourierAssignmentDialogState();
}

class _CourierAssignmentDialogState
    extends ConsumerState<CourierAssignmentDialog> {
  bool _isSubmitting = false;
  String? _error;
  bool _showQuickAdd = false;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  CourierType _quickAddType = CourierType.internal;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _assign(Courier courier) async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref.read(courierDispatchGatewayProvider).assignCourierToOrder(
            orderId: widget.orderId,
            courierId: courier.id,
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

  Future<void> _quickAddCourier() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    if (name.isEmpty || phone.isEmpty) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref.read(courierDispatchGatewayProvider).setCourier(
            organizationId: widget.organizationId,
            branchId: widget.branchId,
            displayName: name,
            phoneNumber: phone,
            type: _quickAddType,
          );
      if (!mounted) return;
      _nameController.clear();
      _phoneController.clear();
      setState(() => _showQuickAdd = false);
    } on CourierDispatchException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.courierType == CourierType.marketplace) {
      return const _MarketplaceLockedDialog();
    }

    final couriersAsync =
        ref.watch(availableCouriersForBranchProvider(widget.branchId));

    return AlertDialog(
      title: const Text('Kurye Ata'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              couriersAsync.when(
                data: (couriers) => couriers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                        child: Text(
                          'Şu anda dükkanda uygun kurye yok.',
                          style: AppTypography.bodyMedium,
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < couriers.length; i++)
                            _CourierRow(
                              courier: couriers[i],
                              isRecommended: i == 0,
                              isSubmitting: _isSubmitting,
                              onAssign: () => _assign(couriers[i]),
                            ),
                        ],
                      ),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const Text(
                  'Kurye listesi yüklenemedi.',
                  style: AppTypography.bodyMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (!_showQuickAdd)
                TextButton.icon(
                  onPressed: () => setState(() => _showQuickAdd = true),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Yeni Kurye Ekle'),
                )
              else
                _QuickAddForm(
                  nameController: _nameController,
                  phoneController: _phoneController,
                  type: _quickAddType,
                  onTypeChanged: (type) => setState(() => _quickAddType = type),
                  isSubmitting: _isSubmitting,
                  onSubmit: _quickAddCourier,
                  onCancel: () => setState(() => _showQuickAdd = false),
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
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

class _MarketplaceLockedDialog extends StatelessWidget {
  const _MarketplaceLockedDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kurye Ata'),
      content: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: AppRadius.kMedium,
          border: Border.all(color: AppColors.warning),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_rounded, color: AppColors.warning),
            SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                'Pazaryeri Kuryesi Taşımaktadır',
                style: AppTypography.bodyMedium,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

class _CourierRow extends StatelessWidget {
  const _CourierRow({
    required this.courier,
    required this.isRecommended,
    required this.isSubmitting,
    required this.onAssign,
  });

  final Courier courier;
  final bool isRecommended;
  final bool isSubmitting;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(courier.displayName, style: AppTypography.bodyMedium),
                if (isRecommended)
                  Container(
                    margin: const EdgeInsets.only(top: AppSpacing.xs),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: AppRadius.kPill,
                    ),
                    child: Text(
                      'Önerilen (İlk Dönen)',
                      style: AppTypography.caption.copyWith(color: AppColors.success),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: isSubmitting ? null : onAssign,
            child: const Text('Ata'),
          ),
        ],
      ),
    );
  }
}

class _QuickAddForm extends StatelessWidget {
  const _QuickAddForm({
    required this.nameController,
    required this.phoneController,
    required this.type,
    required this.onTypeChanged,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final CourierType type;
  final ValueChanged<CourierType> onTypeChanged;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Ad Soyad'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: phoneController,
          decoration: const InputDecoration(labelText: 'Telefon'),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            ChoiceChip(
              label: const Text('Şirket İçi'),
              selected: type == CourierType.internal,
              onSelected: (_) => onTypeChanged(CourierType.internal),
            ),
            ChoiceChip(
              label: const Text('Havuz'),
              selected: type == CourierType.pool,
              onSelected: (_) => onTypeChanged(CourierType.pool),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: isSubmitting ? null : onCancel,
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: isSubmitting ? null : onSubmit,
              child: const Text('Ekle'),
            ),
          ],
        ),
      ],
    );
  }
}
