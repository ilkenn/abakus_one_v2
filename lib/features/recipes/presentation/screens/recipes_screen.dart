import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../inventory/domain/inventory_unit.dart';
import '../../../inventory/domain/quantity.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/create_recipe.dart';
import '../../domain/portion_definition.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_line.dart';
import '../../domain/yield.dart';
import '../providers/recipe_dependencies_provider.dart';

/// Recipe Catalog — Phase 7 (`docs/decisions.md` ADR-024). Lists this
/// organization's [Recipe]s and lets a manager create a new one with a
/// single ingredient line — a deliberately minimal creation form
/// (multi-line/sub-recipe composition, version history browsing, and
/// confidentiality toggling are left to a richer future screen; this
/// is a real, working entry point, not a placeholder).
class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({
    super.key,
    required this.organizationId,
    this.authorizationPolicy,
    this.performedByStaffId = '',
  });

  final String organizationId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  List<Recipe>? _recipes;
  String? _error;
  final _nameController = TextEditingController();
  final _ingredientIdController = TextEditingController();
  final _quantityController = TextEditingController(text: '100');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ingredientIdController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final recipes = await ref
        .read(recipeRepositoryProvider)
        .findByOrganizationId(widget.organizationId);
    if (!mounted) return;
    setState(() => _recipes = recipes);
  }

  Future<void> _create() async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    final name = _nameController.text.trim();
    final ingredientId = _ingredientIdController.text.trim();
    final quantity = int.tryParse(_quantityController.text.trim());
    if (name.isEmpty ||
        ingredientId.isEmpty ||
        quantity == null ||
        quantity <= 0) {
      setState(() => _error = 'Ad, malzeme ve geçerli bir miktar gerekli.');
      return;
    }

    try {
      await CreateRecipe(
        authorizationPolicy: policy,
        idGenerator: ref.read(recipeIdGeneratorProvider),
        versionIdGenerator: ref.read(recipeVersionIdGeneratorProvider),
        repository: ref.read(recipeRepositoryProvider),
        versionRepository: ref.read(recipeVersionRepositoryProvider),
        auditRepository: ref.read(recipeAuditEntryRepositoryProvider),
      )(
        organizationId: widget.organizationId,
        name: name,
        lines: [
          RecipeLine(
            id: '${name}_line_1',
            ingredientId: ingredientId,
            quantity: Quantity.fromWhole(quantity, InventoryUnit.gram),
          ),
        ],
        portionDefinition: PortionDefinition(
          quantity: Quantity.fromWhole(1, InventoryUnit.portion),
        ),
        yieldInfo: Yield(
          totalQuantity: Quantity.fromWhole(quantity, InventoryUnit.gram),
          portionCount: 1,
        ),
        performedByStaffId: widget.performedByStaffId,
        performedAt: DateTime.now(),
      );
      _nameController.clear();
      _ingredientIdController.clear();
      setState(() => _error = null);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipes = _recipes;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Tarifler'),
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
                    const Text('Yeni Tarif (tek malzeme ile)',
                        style: AppTypography.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Tarif Adı'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _ingredientIdController,
                      decoration: const InputDecoration(
                          labelText: 'Malzeme Kimliği (Ingredient ID)'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _quantityController,
                      decoration:
                          const InputDecoration(labelText: 'Miktar (gram)'),
                      keyboardType: TextInputType.number,
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
                      child: const Text('Tarif Oluştur'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: recipes == null
                  ? const LoadingView(message: 'Tarifler yükleniyor...')
                  : recipes.isEmpty
                      ? const EmptyView(
                          icon: Icons.menu_book_outlined,
                          message: 'Henüz tarif eklenmedi.',
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg),
                          children: [
                            for (final recipe in recipes)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm),
                                child: AppCard(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(recipe.name,
                                          style: AppTypography.titleMedium),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        'v${recipe.revision}'
                                        '${recipe.isConfidential ? ' · Gizli' : ''}',
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
