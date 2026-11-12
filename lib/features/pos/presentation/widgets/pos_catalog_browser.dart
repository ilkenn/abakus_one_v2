import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../../shared/widgets/images/product_image.dart';
import '../../../menu/domain/models/menu_category.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../menu/domain/models/sale_unit.dart';
import '../../../menu/domain/models/selected_modifier.dart';
import '../../../menu/domain/pricing/channel_price_resolver.dart';
import '../../../menu/domain/pricing/channel_pricing_policy.dart';
import '../../../menu/presentation/providers/channel_price_display_provider.dart';
import '../../../menu/presentation/providers/menu_catalog_provider.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../../shared/models/money.dart';
import '../../data/pos_action_gateway.dart' show PosDeviceContext;
import '../providers/pos_workspace_providers.dart';
import 'pos_product_customization_dialog.dart';
import 'weight_entry_dialog.dart';

/// What one tap in [PosCatalogBrowser] adds: a product, already configured
/// through the customization or weight dialog when it needed one.
class PosCatalogSelection {
  const PosCatalogSelection({
    required this.product,
    this.selectedModifiers = const [],
    this.excludedIngredients = const [],
    this.note = '',
    this.quantity = 1,
    this.weightGrams,
  });

  final MenuProduct product;
  final List<SelectedModifier> selectedModifiers;
  final List<String> excludedIngredients;
  final String note;
  final int quantity;

  /// ADR-067 — set for a product sold by weight (one line, never merged).
  final int? weightGrams;
}

/// The touch-POS catalog shared by the table workspace and the takeaway /
/// delivery order screen (2026-11-11, product owner: one reusable catalog,
/// no duplicate). Category rail ("Çok Tercih Edilenler" first, then every
/// category with its products' photos) → product-card grid, with a name
/// search that also accepts a USB barcode scanner, and the product
/// customization (required modifiers / removable ingredients) and weight
/// dialogs. It owns only what is being browsed; every chosen product goes to
/// [onAdd], and the caller owns its cart.
///
/// [wide] lays the rail out vertically beside the grid; narrow screens get a
/// horizontal chip row above it.
class PosCatalogBrowser extends ConsumerStatefulWidget {
  const PosCatalogBrowser({
    super.key,
    required this.ctx,
    required this.onAdd,
    required this.wide,
    this.priceChannel,
    this.allowWeighedProducts = true,
  });

  final PosDeviceContext ctx;
  final ValueChanged<PosCatalogSelection> onAdd;
  final bool wide;

  /// 2026-11-11 — when set, cards, the customization dialog and every
  /// selection carry that channel's prices (Gel-Al +20 TL; Paket Servis
  /// ×1.35, nearest 5 TL — product and each paid modifier); `null` = the
  /// Masa (dine-in) price. Display only: the server prices every order
  /// itself.
  final OrderChannel? priceChannel;

  /// ADR-067 — products sold by weight are dine-in only for now; `false`
  /// refuses them with an explanation instead of opening the weight dialog.
  final bool allowWeighedProducts;

  @override
  ConsumerState<PosCatalogBrowser> createState() => _PosCatalogBrowserState();
}

/// 2026-11-03 — product owner, BR-POS-001: "Çok Tercih Edilenler" (Top 20
/// best-sellers) is the default tab — see `topSellingProductsProvider`.
const _topSellersSentinel = '__top_sellers__';

/// Fixed "Çok Tercih Edilenler" showcase (2026-11-03, product owner
/// decision) — one curated id per catalog group, used only when the real
/// sales aggregation errors or genuinely has no history yet. Every id was
/// matched against `abakus_menu_catalog.dart` by hand; none are guessed.
const List<String> _topSellersFallbackProductIds = [
  // Bowl
  'prod_bowl2_tatli_eksi_tavuk',
  'prod_bowl2_citir_tavuk',
  'prod_bowl2_somon_fume',
  'prod_bowl2_izgara_anne_koftesi',
  // Burger
  'prod_burger2_double_chicken',
  'prod_burger2_tripoli',
  'prod_burger2_steak',
  // Tava
  'prod_tava_citir_tavuk',
  'prod_tava_kremali_pestolu_tavuk',
  'prod_tava_tatli_eksi_tavuk',
  // Kahvaltı & Ekmek
  'prod_kahvalti_clasico',
  'prod_kahvalti_steak',
  'prod_kahvalti_salmon',
  // Wrap
  'prod_wrap2_citir_tavuk',
  'prod_wrap2_asian_chicken',
  'prod_wrap2_kofte',
  // Salata & Makarna
  'prod_salata2_crispy_caesar',
  'prod_makarna2_fettuccine_chicken_alfredo',
  'prod_makarna2_citir_tavuk_fettuccine',
];

class _PosCatalogBrowserState extends ConsumerState<PosCatalogBrowser> {
  String _categoryFilter = _topSellersSentinel;

  /// Live product-grid search (2026-11-03) — filters by name as the staff
  /// types; a non-empty search covers every category.
  final _searchController = TextEditingController();
  String _searchQuery = '';

  /// Adım 4 (2026-11-07) — set when a USB barkod okuyucu submits a code
  /// that matches no [MenuProduct.barcode]; cleared on the next keystroke
  /// or successful match.
  String? _barcodeNotFoundMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Every catalog product carries the optional "Ekstra Sos" cross-sell
  /// group, so "has modifier groups" would open the dialog for every drink;
  /// the real signal is a *required* group (Bowl's carb/salad, Burger/Wrap's
  /// fries) or a removable-ingredients list.
  bool _needsCustomization(MenuProduct product) =>
      product.modifierGroups.any((group) => group.isRequired) ||
      product.removableIngredients.isNotEmpty;

  /// A product with nothing worth configuring (drinks, simple sides) is
  /// added directly, one tap. A Bowl/Burger/Wrap-style product opens
  /// [PosProductCustomizationDialog] first, a sold-by-weight product the
  /// weight dialog — dismissing either adds nothing.
  Future<void> _onProductTap(MenuProduct product) async {
    if (product.saleUnit == SaleUnit.kilogram && !widget.allowWeighedProducts) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content:
              Text('Tartılı ürünler şimdilik yalnızca masada satılabilir.'),
        ));
      return;
    }
    if (product.saleUnit == SaleUnit.kilogram) {
      final grams = await WeightEntryDialog.show(context, product);
      if (grams == null || !mounted) return;
      widget.onAdd(PosCatalogSelection(product: product, weightGrams: grams));
      return;
    }
    if (!_needsCustomization(product)) {
      widget.onAdd(PosCatalogSelection(product: product));
      return;
    }
    final result = await PosProductCustomizationDialog.show(context, product);
    if (result == null || !mounted) return;
    widget.onAdd(PosCatalogSelection(
      product: product,
      selectedModifiers: result.selectedModifiers,
      excludedIngredients: result.excludedIngredients,
      note: result.note,
      quantity: result.quantity,
    ));
  }

  List<MenuProduct> _productsIn(String categoryId, List<MenuProduct> products) {
    return [
      for (final product in products)
        if (product.categoryId == categoryId) product,
    ];
  }

  List<MenuProduct> _resolveTopSellersFallback(List<MenuProduct> allProducts) {
    final productById = {for (final p in allProducts) p.id: p};
    return [
      for (final id in _topSellersFallbackProductIds)
        if (productById[id] != null) productById[id]!,
    ];
  }

  Widget _buildCategoryRail(
      List<MenuCategory> categories, List<MenuProduct> allProducts) {
    if (!widget.wide) {
      final chips = [
        ChoiceChip(
          label: const Text('Çok Tercih Edilenler'),
          selected: _categoryFilter == _topSellersSentinel,
          onSelected: (_) =>
              setState(() => _categoryFilter = _topSellersSentinel),
        ),
        for (final category in categories)
          ChoiceChip(
            label: Text(category.name),
            selected: _categoryFilter == category.id,
            onSelected: (_) => setState(() => _categoryFilter = category.id),
          ),
      ];
      return SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          itemCount: chips.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, index) => chips[index],
        ),
      );
    }
    return SizedBox(
      width: 112,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          _CategoryCard(
            label: 'Çok Tercih Edilenler',
            icon: Icons.star_rounded,
            selected: _categoryFilter == _topSellersSentinel,
            onTap: () => setState(() => _categoryFilter = _topSellersSentinel),
          ),
          for (final category in categories)
            _CategoryCard(
              label: category.name,
              selected: _categoryFilter == category.id,
              onTap: () => setState(() => _categoryFilter = category.id),
              categoryId: category.id,
              previewImageKeys: [
                for (final product in _productsIn(category.id, allProducts))
                  product.imageKey,
              ],
            ),
        ],
      ),
    );
  }

  /// Adım 4 (2026-11-07) — a USB barkod okuyucu (HID keyboard emulator)
  /// types the barcode into the focused search field and sends Enter: an
  /// exact [MenuProduct.barcode] match adds it (through [_onProductTap], so
  /// a required-modifier product still opens its dialog); no match shows an
  /// inline error plus an alert sound.
  void _handleBarcodeSubmit(String rawValue, List<MenuProduct> allProducts) {
    final value = rawValue.trim();
    if (value.isEmpty) return;
    MenuProduct? match;
    for (final product in allProducts) {
      if (product.barcode == value) {
        match = product;
        break;
      }
    }
    if (match == null) {
      SystemSound.play(SystemSoundType.alert);
      setState(() => _barcodeNotFoundMessage = 'Barkod bulunamadı: $value');
      return;
    }
    SystemSound.play(SystemSoundType.click);
    setState(() {
      _barcodeNotFoundMessage = null;
      _searchController.clear();
      _searchQuery = '';
    });
    _onProductTap(match);
  }

  Widget _buildSearchField(List<MenuProduct> allProducts) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: TextField(
        key: const Key('productSearchField'),
        controller: _searchController,
        onChanged: (value) => setState(() {
          _searchQuery = value;
          _barcodeNotFoundMessage = null;
        }),
        onSubmitted: (value) => _handleBarcodeSubmit(value, allProducts),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Ürün ara veya barkod okut...',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          errorText: _barcodeNotFoundMessage,
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () => setState(() {
                    _searchController.clear();
                    _searchQuery = '';
                    _barcodeNotFoundMessage = null;
                  }),
                ),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          border: const OutlineInputBorder(
            borderRadius: AppRadius.kPill,
            borderSide: BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }

  Widget _buildProductGrid(List<MenuProduct> products,
      {String emptyMessage = 'Bu kategoride ürün yok.'}) {
    if (products.isEmpty) {
      return Center(
        child: Text(emptyMessage, style: AppTypography.bodyMedium),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.8,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return _ProductCard(
          product: product,
          onTap: () => _onProductTap(product),
        );
      },
    );
  }

  /// [product] with [channel]'s prices for itself and each paid option.
  static MenuProduct _pricedFor(
    MenuProduct product,
    OrderChannel channel,
    ChannelPricingPolicy policy,
  ) {
    double whole(Money money) => money.minorUnits / 100;
    return product.copyWith(
      basePrice: whole(ChannelPriceResolver.resolveProductUnitPrice(
        product: product,
        categoryId: product.categoryId,
        channel: channel,
        policy: policy,
      )),
      modifierGroups: [
        for (final group in product.modifierGroups)
          group.copyWith(options: [
            for (final option in group.options)
              option.copyWith(
                extraPrice:
                    whole(ChannelPriceResolver.resolveModifierExtraPrice(
                  extraPrice: Money.fromLegacyDoubleTry(option.extraPrice),
                  channel: channel,
                  policy: policy,
                )),
              ),
          ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(menuCategoriesProvider);
    final channel = widget.priceChannel;
    final policy = channel == null
        ? null
        : ref.watch(channelPricingPolicySnapshotProvider).valueOrNull;
    final allProducts = [
      for (final product in ref.watch(menuProductsProvider))
        if (product.isAvailable)
          channel == null || policy == null
              ? product
              : _pricedFor(product, channel, policy),
    ];

    // "Çok Tercih Edilenler" (BR-POS-001) resolves asynchronously (a real
    // backend aggregation); every other category is an in-memory list,
    // wrapped in `AsyncValue.data` so both share one loading/error/data path.
    // Product owner decision (2026-11-03): never a dead error screen or an
    // empty grid on day one — an error or no sales history falls back to the
    // fixed showcase.
    final categoryFilteredAsync = _categoryFilter == _topSellersSentinel
        ? ref.watch(topSellingProductsProvider(widget.ctx)).when(
              loading: () => const AsyncValue<List<MenuProduct>>.loading(),
              error: (error, stackTrace) => AsyncValue.data(
                _resolveTopSellersFallback(allProducts),
              ),
              data: (topSellers) {
                final productById = {for (final p in allProducts) p.id: p};
                final resolved = [
                  for (final entry in topSellers)
                    if (productById[entry.productId] != null)
                      productById[entry.productId]!,
                ];
                return AsyncValue.data(
                  resolved.isNotEmpty
                      ? resolved
                      : _resolveTopSellersFallback(allProducts),
                );
              },
            )
        : AsyncValue.data(
            allProducts.where((p) => p.categoryId == _categoryFilter).toList(),
          );
    final searchQuery = _searchQuery.trim().toLowerCase();
    final visibleProductsAsync = searchQuery.isNotEmpty
        ? AsyncValue.data(
            allProducts
                .where((p) => p.name.toLowerCase().contains(searchQuery))
                .toList(),
          )
        : categoryFilteredAsync;

    final grid = Column(
      children: [
        _buildSearchField(allProducts),
        Expanded(
          child: visibleProductsAsync.when(
            loading: () => const LoadingView(
                message: 'Çok tercih edilenler yükleniyor...'),
            error: (error, stackTrace) => ErrorView(
              message: 'Çok tercih edilenler yüklenemedi.',
              retryLabel: 'Yeniden Dene',
              onRetry: () =>
                  ref.invalidate(topSellingProductsProvider(widget.ctx)),
            ),
            data: (products) => _buildProductGrid(
              products,
              emptyMessage: _categoryFilter == _topSellersSentinel
                  ? 'Henüz yeterli satış verisi yok.'
                  : 'Bu kategoride ürün yok.',
            ),
          ),
        ),
      ],
    );
    final rail = _buildCategoryRail(categories, allProducts);
    if (!widget.wide) {
      return Column(children: [rail, Expanded(child: grid)]);
    }
    return Row(
      children: [
        rail,
        Container(width: 1, color: AppColors.border),
        Expanded(child: grid),
      ],
    );
  }
}

/// Vertical category-rail card (2026-11-02 touch-POS redesign) — a small
/// rounded preview image on top, the category name below, highlighted when
/// selected. The preview is the category's own products' real photos via
/// [ProductImage], tried in order via [previewImageKeys]; empty only for the
/// synthetic "Çok Tercih Edilenler" entry or a category with no products, in
/// which case [icon] is shown instead.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.label,
    required this.selected,
    required this.onTap,
    this.categoryId,
    this.previewImageKeys = const [],
    this.icon = Icons.restaurant_menu_rounded,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? categoryId;
  final List<String> previewImageKeys;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryExtraLight : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.small),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: previewImageKeys.isEmpty
                      ? Icon(icon, size: 28, color: AppColors.textSecondary)
                      : ProductImage(
                          imageKey: previewImageKeys.first,
                          additionalImageKeys:
                              previewImageKeys.skip(1).toList(),
                          categoryId: categoryId,
                          width: 56,
                          height: 56,
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single tappable product tile — a real photo via [ProductImage], name,
/// price and the nutrition/allergen badge. Tapping adds one unit; quantity
/// is adjusted in the caller's cart.
class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});
  final MenuProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // `LayoutBuilder` gives `ProductImage` the tile's real size
                // for its decode-size (cacheWidth/cacheHeight) optimization.
                child: LayoutBuilder(
                  builder: (context, constraints) => ProductImage(
                    imageKey: product.imageKey,
                    categoryId: product.categoryId,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                product.name,
                style: AppTypography.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${product.basePrice.toStringAsFixed(0)} TL',
                style: AppTypography.bodySmall.copyWith(
                    color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
              PosNutritionAllergenBadge(
                nutrition: product.nutrition,
                allergens: product.allergens,
                dense: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
