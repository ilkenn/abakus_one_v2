import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/create_ingredient.dart';
import '../../domain/ingredient.dart';
import '../../domain/inventory_unit.dart';
import '../providers/inventory_dependencies_provider.dart';

/// Ingredient Catalog — Phase 7 (`docs/decisions.md` ADR-024). Lists
/// this organization's [Ingredient] master data and lets a manager add
/// a new one. Creating an ingredient never begins tracking it in
/// inventory by itself — see `InventoryScreen`/`CreateInventoryItem`
/// for that separate step ("an ingredient can exist in a recipe before
/// anyone decides to track it in inventory at all").
class IngredientCatalogScreen extends ConsumerStatefulWidget {
  const IngredientCatalogScreen({
    super.key,
    required this.organizationId,
    this.authorizationPolicy,
    this.performedByStaffId = '',
  });

  final String organizationId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<IngredientCatalogScreen> createState() =>
      _IngredientCatalogScreenState();
}

class _IngredientCatalogScreenState
    extends ConsumerState<IngredientCatalogScreen> {
  List<Ingredient>? _ingredients;
  String? _error;
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  InventoryUnit _selectedUnit = InventoryUnit.gram;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ingredients = await ref
        .read(ingredientRepositoryProvider)
        .findByOrganizationId(widget.organizationId);
    if (!mounted) return;
    setState(() => _ingredients = ingredients);
  }

  Future<void> _create() async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Malzeme adı gerekli.');
      return;
    }
    try {
      await CreateIngredient(
        authorizationPolicy: policy,
        idGenerator: ref.read(ingredientIdGeneratorProvider),
        repository: ref.read(ingredientRepositoryProvider),
        auditRepository: ref.read(inventoryAuditEntryRepositoryProvider),
      )(
        organizationId: widget.organizationId,
        name: name,
        category: _categoryController.text.trim().isEmpty
            ? null
            : _categoryController.text.trim(),
        baseUnit: _selectedUnit,
        performedByStaffId: widget.performedByStaffId,
        performedAt: DateTime.now(),
      );
      _nameController.clear();
      _categoryController.clear();
      setState(() => _error = null);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ingredients = _ingredients;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Malzeme Kataloğu'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Yeni Malzeme',
                        style: AppTypography.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Ad'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _categoryController,
                      decoration: const InputDecoration(
                          labelText: 'Kategori (opsiyonel)'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonFormField<InventoryUnit>(
                      initialValue: _selectedUnit,
                      decoration:
                          const InputDecoration(labelText: 'Temel Birim'),
                      items: [
                        for (final unit in InventoryUnit.builtIn)
                          DropdownMenuItem(
                            value: unit,
                            child: Text(unit.displayName),
                          ),
                      ],
                      onChanged: (unit) {
                        if (unit != null) {
                          setState(() => _selectedUnit = unit);
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (_error != null) ...[
                      Text(_error!,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.error)),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    OutlinedButton(
                      onPressed: _create,
                      child: const Text('Malzeme Ekle'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ingredients == null
                  ? const LoadingView(message: 'Malzemeler yükleniyor...')
                  : ingredients.isEmpty
                      ? const EmptyView(
                          icon: Icons.egg_outlined,
                          message: 'Henüz malzeme eklenmedi.',
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg),
                          children: [
                            for (final ingredient in ingredients)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm),
                                child: AppCard(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(ingredient.name,
                                          style: AppTypography.titleMedium),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        '${ingredient.category ?? 'Kategorisiz'} · '
                                        '${ingredient.baseUnit.displayName}',
                                        style: AppTypography.bodySmall.copyWith(
                                            color: AppColors.textSecondary),
                                      ),
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
