import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../inventory/domain/inventory_unit.dart';
import '../../../inventory/domain/quantity.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../smart_import/presentation/providers/smart_import_dependencies_provider.dart';
import '../../data/recipe_ingredient_link_gateway.dart';
import '../../domain/recipe_ingredient_link.dart';
import '../providers/recipe_dependencies_provider.dart';

/// AP-5 Sprint 6 — the management surface for [RecipeIngredientLink]
/// (Sprint 2's flattened product-to-inventory-item stock-consumption
/// binding), which had no UI at all before this: `setRecipeIngredientLink`
/// existed only as a callable with no Dart caller
/// (`recipe_dependencies_provider.dart`'s own prior doc comment). Lists
/// [MenuProduct]s (via the existing, shared `menuProductRepositoryProvider`
/// — the same catalog Smart Import writes to) and each product's current
/// link status; tapping a product opens the editing form.
///
/// **Deliberately its own screen, not folded into [RecipesScreen]**:
/// `Recipe`/`RecipeLine` (that screen's own domain) and
/// `RecipeIngredientLink` are two real, distinct concepts in this
/// codebase (see [RecipeIngredientLink]'s own doc comment) — conflating
/// them into one screen would misrepresent that split.
class RecipeIngredientLinksScreen extends ConsumerStatefulWidget {
  const RecipeIngredientLinksScreen({
    super.key,
    required this.organizationId,
  });

  final String organizationId;

  @override
  ConsumerState<RecipeIngredientLinksScreen> createState() =>
      _RecipeIngredientLinksScreenState();
}

class _RecipeIngredientLinksScreenState
    extends ConsumerState<RecipeIngredientLinksScreen> {
  List<MenuProduct>? _products;
  Map<String, RecipeIngredientLink> _linksByProductId = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final products = await ref.read(menuProductRepositoryProvider).findAll();
      final linkRepository = ref.read(recipeIngredientLinkRepositoryProvider);
      final links = <String, RecipeIngredientLink>{};
      for (final product in products) {
        final link = await linkRepository.findByProductId(product.id);
        if (link != null) links[product.id] = link;
      }
      if (!mounted) return;
      setState(() {
        _products = products;
        _linksByProductId = links;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _openForm(MenuProduct product) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _RecipeIngredientLinkFormScreen(
          organizationId: widget.organizationId,
          product: product,
          existingLink: _linksByProductId[product.id],
        ),
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reçete-Malzeme Bağlantıları'),
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
              child: products == null
                  ? const LoadingView(message: 'Ürünler yükleniyor...')
                  : products.isEmpty
                      ? const EmptyView(
                          icon: Icons.restaurant_menu_outlined,
                          message: 'Kayıtlı ürün yok.',
                        )
                      : ListView(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          children: [
                            for (final product in products)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm),
                                child: InkWell(
                                  onTap: () => _openForm(product),
                                  child: AppCard(
                                    padding:
                                        const EdgeInsets.all(AppSpacing.md),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(product.name,
                                                  style: AppTypography
                                                      .titleMedium),
                                              const SizedBox(
                                                  height: AppSpacing.xs),
                                              _LinkStatusBadge(
                                                link: _linksByProductId[
                                                    product.id],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.chevron_right,
                                            color: AppColors.textSecondary),
                                      ],
                                    ),
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

class _LinkStatusBadge extends StatelessWidget {
  const _LinkStatusBadge({required this.link});

  final RecipeIngredientLink? link;

  @override
  Widget build(BuildContext context) {
    final linked = link != null;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: linked ? AppColors.success : AppColors.textDisabled,
        borderRadius: AppRadius.kPill,
      ),
      child: Text(
        linked
            ? '${link!.ingredients.length} malzeme bağlı'
            : 'Bağlantı yok',
        style: AppTypography.labelMedium
            .copyWith(color: AppColors.onPrimary, letterSpacing: 0),
      ),
    );
  }
}

class _IngredientLineDraft {
  _IngredientLineDraft({
    String inventoryItemId = '',
    String quantity = '',
    this.unit = InventoryUnit.gram,
  })  : inventoryItemIdController = TextEditingController(text: inventoryItemId),
        quantityController = TextEditingController(text: quantity);

  final TextEditingController inventoryItemIdController;
  final TextEditingController quantityController;
  InventoryUnit unit;

  void dispose() {
    inventoryItemIdController.dispose();
    quantityController.dispose();
  }
}

/// The editing form for one [MenuProduct]'s [RecipeIngredientLink] — a
/// repeatable ingredient-line list (inventory item id + quantity + unit,
/// mirroring `RecipesScreen`'s own plain-text-field precedent for
/// ingredient identity, since no real `InventoryItem` picker data source
/// exists yet — `inventoryItemRepositoryProvider` is in-memory-only and
/// no Cloud Function writes real `InventoryItem` catalog data either).
class _RecipeIngredientLinkFormScreen extends ConsumerStatefulWidget {
  const _RecipeIngredientLinkFormScreen({
    required this.organizationId,
    required this.product,
    required this.existingLink,
  });

  final String organizationId;
  final MenuProduct product;
  final RecipeIngredientLink? existingLink;

  @override
  ConsumerState<_RecipeIngredientLinkFormScreen> createState() =>
      _RecipeIngredientLinkFormScreenState();
}

class _RecipeIngredientLinkFormScreenState
    extends ConsumerState<_RecipeIngredientLinkFormScreen> {
  late final TextEditingController _recipeVersionIdController;
  late List<_IngredientLineDraft> _lines;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingLink;
    _recipeVersionIdController =
        TextEditingController(text: existing?.recipeVersionId ?? '');
    _lines = existing == null
        ? [_IngredientLineDraft()]
        : [
            for (final line in existing.ingredients)
              _IngredientLineDraft(
                inventoryItemId: line.inventoryItemId,
                quantity: (line.quantity.smallestUnits /
                        line.quantity.unit.smallestUnitsPerWhole)
                    .toString(),
                unit: line.quantity.unit,
              ),
          ];
  }

  @override
  void dispose() {
    _recipeVersionIdController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _addLine() => setState(() => _lines.add(_IngredientLineDraft()));

  void _removeLine(int index) {
    setState(() {
      _lines.removeAt(index).dispose();
    });
  }

  Future<void> _save() async {
    final recipeVersionId = _recipeVersionIdController.text.trim();
    if (recipeVersionId.isEmpty) {
      setState(() => _error = 'Reçete versiyon kimliği gerekli.');
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _error = 'En az bir malzeme satırı gerekli.');
      return;
    }

    final ingredients = <RecipeIngredientLinkLineInput>[];
    for (final line in _lines) {
      final inventoryItemId = line.inventoryItemIdController.text.trim();
      final wholeQuantity =
          double.tryParse(line.quantityController.text.trim());
      if (inventoryItemId.isEmpty || wholeQuantity == null || wholeQuantity <= 0) {
        setState(() =>
            _error = 'Her satır için geçerli bir malzeme kimliği ve miktar girin.');
        return;
      }
      final smallestUnits =
          (wholeQuantity * line.unit.smallestUnitsPerWhole).round();
      ingredients.add(RecipeIngredientLinkLineInput(
        inventoryItemId: inventoryItemId,
        quantitySmallestUnits: smallestUnits,
        unitCode: line.unit.code,
      ));
    }

    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final result = await ref.read(recipeIngredientLinkGatewayProvider).setLink(
            organizationId: widget.organizationId,
            productId: widget.product.id,
            recipeVersionId: recipeVersionId,
            ingredients: ingredients,
          );
      // Mirror the just-saved link into the local repository so the list
      // screen reflects the change immediately without a server round
      // -trip re-read — the server callable stays the source of truth
      // (this is the same "local repo mirrors last-known-good" shape
      // already established elsewhere in this codebase).
      await ref.read(recipeIngredientLinkRepositoryProvider).save(
            RecipeIngredientLink(
              id: result.linkId,
              organizationId: widget.organizationId,
              productId: widget.product.id,
              recipeVersionId: recipeVersionId,
              ingredients: [
                for (var i = 0; i < ingredients.length; i++)
                  RecipeIngredientLinkLine(
                    inventoryItemId: ingredients[i].inventoryItemId,
                    quantity: Quantity(
                        ingredients[i].quantitySmallestUnits, _lines[i].unit),
                  ),
              ],
              createdAt: DateTime.now(),
              revision: result.revision,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on RecipeIngredientLinkException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.product.name),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            TextField(
              controller: _recipeVersionIdController,
              decoration: const InputDecoration(
                  labelText: 'Reçete Versiyon Kimliği'),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('Malzemeler', style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < _lines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _lines[i].inventoryItemIdController,
                        decoration: const InputDecoration(
                            labelText: 'Malzeme Kimliği (Inventory Item ID)'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _lines[i].quantityController,
                              decoration:
                                  const InputDecoration(labelText: 'Miktar'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          DropdownButton<InventoryUnit>(
                            value: _lines[i].unit,
                            items: [
                              for (final unit in InventoryUnit.builtIn)
                                DropdownMenuItem(
                                  value: unit,
                                  child: Text(unit.displayName),
                                ),
                            ],
                            onChanged: (unit) {
                              if (unit != null) {
                                setState(() => _lines[i].unit = unit);
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.error),
                            onPressed: _lines.length > 1
                                ? () => _removeLine(i)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _addLine,
              icon: const Icon(Icons.add),
              label: const Text('Malzeme Ekle'),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_error != null) ...[
              Text(_error!,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.error)),
              const SizedBox(height: AppSpacing.sm),
            ],
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}
