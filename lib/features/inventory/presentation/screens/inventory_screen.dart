import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../domain/branch_stock.dart';
import '../../domain/ingredient.dart';
import '../../domain/inventory_item.dart';
import '../providers/inventory_dependencies_provider.dart';

/// Inventory — Phase 7 (`docs/decisions.md` ADR-024). Read-only view of
/// this organization's tracked [InventoryItem]s and this branch's
/// on-hand [BranchStock] balances. `BranchStock` is a pure read-model —
/// the only way to change an on-hand quantity is `RecordStockMovement`
/// (manual entry, adjustment approval, or future automatic
/// consumption/purchasing), never a direct edit from this screen.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({
    super.key,
    required this.organizationId,
    required this.branchId,
  });

  final String organizationId;
  final String branchId;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  List<InventoryItem>? _items;
  Map<String, Ingredient>? _ingredientsById;
  Map<String, BranchStock>? _stockByItemId;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final items = await ref
          .read(inventoryItemRepositoryProvider)
          .findByOrganizationId(widget.organizationId);
      final ingredients = await ref
          .read(ingredientRepositoryProvider)
          .findByOrganizationId(widget.organizationId);
      final balances = await ref
          .read(branchStockRepositoryProvider)
          .findByBranchId(widget.branchId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _ingredientsById = {
          for (final ingredient in ingredients) ingredient.id: ingredient,
        };
        _stockByItemId = {
          for (final stock in balances) stock.inventoryItemId: stock,
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final ingredientsById = _ingredientsById;
    final stockByItemId = _stockByItemId;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Envanter'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(_error!,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.error)),
              ),
            Expanded(
              child: items == null ||
                      ingredientsById == null ||
                      stockByItemId == null
                  ? const LoadingView(message: 'Envanter yükleniyor...')
                  : items.isEmpty
                      ? const EmptyView(
                          icon: Icons.inventory_2_outlined,
                          message: 'Takip edilen envanter kalemi yok.',
                        )
                      : ListView(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          children: [
                            for (final item in items)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm),
                                child: AppCard(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        ingredientsById[item.ingredientId]
                                                ?.name ??
                                            item.ingredientId,
                                        style: AppTypography.titleMedium,
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        'Birim: ${item.trackingUnit.displayName} · '
                                        'Negatif stok: ${item.negativeStockPolicy.name}',
                                        style: AppTypography.bodySmall.copyWith(
                                            color: AppColors.textSecondary),
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Builder(builder: (context) {
                                        final stock = stockByItemId[item.id];
                                        if (stock == null) {
                                          return Text(
                                            'Bu şubede stok kaydı yok',
                                            style: AppTypography.bodySmall
                                                .copyWith(
                                                    color: AppColors
                                                        .textSecondary),
                                          );
                                        }
                                        return Text(
                                          'Mevcut: ${stock.quantityOnHand}'
                                          '${stock.isNegativeStockWarning ? ' ⚠ negatif' : ''}',
                                          style:
                                              AppTypography.bodyMedium.copyWith(
                                            color: stock.isNegativeStockWarning
                                                ? AppColors.error
                                                : AppColors.textPrimary,
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
