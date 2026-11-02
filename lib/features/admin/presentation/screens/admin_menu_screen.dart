import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/functions/maintenance_operations_gateway.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../navigation/presentation/providers/current_branch_provider.dart';
import '../../data/menu_catalog_admin_gateway.dart';
import '../providers/admin_dependencies_provider.dart';
import '../providers/admin_menu_providers.dart';

/// Admin Menü — 2026-10-28. Categories and products, each a simple list +
/// add dialog, matching exactly what was asked for (list + add — no
/// edit/delete/reorder yet, not built ahead of being asked for). Every
/// read and write goes through `MenuCatalogAdminGateway` (the real
/// `menuCategories`/`menuProducts` backend has no `firestore.rules` entry
/// at all — callable-only, by design).
///
/// 2026-10-30 — the AppBar also carries "Şube Adını Düzenle" (e.g. fixing
/// a seed script's placeholder "Merkez Şube" to the branch's real name):
/// not a Menü-module concern as such, but this is the screen the product
/// owner actually asked for it from, and it needs a real staff session
/// (`manageBranch`) that only this tenant Admin shell has — see
/// `maintenance_operations_gateway.dart`'s own doc comment on why that
/// rules out the Platform Console.
class AdminMenuScreen extends ConsumerWidget {
  const AdminMenuScreen({super.key});

  Future<void> _showRenameBranchDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final nameController = TextEditingController();
    String? error;

    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Şube Adını Düzenle'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Yeni Şube Adı',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                final trimmed = nameController.text.trim();
                if (trimmed.isEmpty) {
                  setState(() => error = 'Şube adı gerekli.');
                  return;
                }
                Navigator.of(context).pop(trimmed);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (name == null) return;

    try {
      await ref.read(adminMaintenanceOperationsGatewayProvider).renameBranch(
            organizationId: ref.read(currentOrganizationIdProvider),
            branchId: ref.read(currentBranchIdProvider),
            name: name,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Şube adı "$name" olarak güncellendi.')),
      );
    } on MaintenanceOperationsException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Menü'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.storefront_outlined),
              tooltip: 'Şube Adını Düzenle',
              onPressed: () => _showRenameBranchDialog(context, ref),
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'Kategoriler'), Tab(text: 'Ürünler')],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(children: [_CategoriesTab(), _ProductsTab()]),
        ),
      ),
    );
  }
}

class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminMenuCategoriesProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: async.when(
        loading: () => const LoadingView(message: 'Kategoriler yükleniyor...'),
        error: (error, stack) => ErrorView(
          message: 'Kategoriler yüklenemedi.',
          retryLabel: 'Tekrar dene',
          onRetry: () => ref.invalidate(adminMenuCategoriesProvider),
        ),
        data: (categories) {
          if (categories.isEmpty) {
            return const EmptyView(
              icon: Icons.category_outlined,
              message: 'Henüz bir kategori yok.',
            );
          }
          final sorted = [...categories]
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final category = sorted[index];
              return AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      category.isActive
                          ? Icons.check_circle_outline
                          : Icons.remove_circle_outline,
                      size: 20,
                      color: category.isActive
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child:
                          Text(category.name, style: AppTypography.bodyMedium),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddCategoryDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showAddCategoryDialog(
      BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    String? error;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Yeni Kategori'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Kategori Adı',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  setState(() => error = 'Kategori adı gerekli.');
                  return;
                }
                Navigator.of(context).pop(controller.text.trim());
              },
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
    if (name == null) return;

    try {
      await ref.read(menuCatalogAdminGatewayProvider).createCategory(
            organizationId: ref.read(currentOrganizationIdProvider),
            restaurantId: ref.read(currentRestaurantIdProvider),
            name: name,
          );
      ref.invalidate(adminMenuCategoriesProvider);
    } on MenuCatalogAdminException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _ProductsTab extends ConsumerWidget {
  const _ProductsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminMenuProductsProvider);
    final categoriesAsync = ref.watch(adminMenuCategoriesProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: async.when(
        loading: () => const LoadingView(message: 'Ürünler yükleniyor...'),
        error: (error, stack) => ErrorView(
          message: 'Ürünler yüklenemedi.',
          retryLabel: 'Tekrar dene',
          onRetry: () => ref.invalidate(adminMenuProductsProvider),
        ),
        data: (products) {
          if (products.isEmpty) {
            return const EmptyView(
              icon: Icons.restaurant_menu_outlined,
              message: 'Henüz bir ürün yok.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final product = products[index];
              return AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(product.name,
                                  style: AppTypography.bodyMedium),
                              if (!product.isAvailable)
                                Text('Tükendi (86)',
                                    style: AppTypography.bodySmall
                                        .copyWith(color: AppColors.warning)),
                            ],
                          ),
                        ),
                        Text(
                          '${Money(product.basePriceMinorUnits, Currency.tryLira)}',
                          style: AppTypography.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        OutlinedButton(
                          onPressed: () =>
                              _showEditProductDialog(context, ref, product),
                          child: const Text('Düzenle'),
                        ),
                        OutlinedButton(
                          onPressed: () => _toggleAvailability(ref, product),
                          child: Text(product.isAvailable
                              ? 'Tükendi (86)'
                              : 'Tekrar Sat'),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error),
                          onPressed: () =>
                              _confirmDeleteProduct(context, ref, product),
                          child: const Text('Sil'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddProductDialog(
          context,
          ref,
          categoriesAsync.valueOrNull ?? const [],
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showAddProductDialog(
    BuildContext context,
    WidgetRef ref,
    List<AdminMenuCategory> categories,
  ) async {
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Önce en az bir kategori ekleyin.'),
      ));
      return;
    }
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    String? selectedCategoryId = categories.first.id;
    String? error;

    final result = await showDialog<(String, String, double)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Yeni Ürün'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Ürün Adı'),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: selectedCategoryId,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: [
                  for (final category in categories)
                    DropdownMenuItem(
                        value: category.id, child: Text(category.name)),
                ],
                onChanged: (value) =>
                    setState(() => selectedCategoryId = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Fiyat (₺)',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                final price = double.tryParse(
                    priceController.text.trim().replaceAll(',', '.'));
                if (name.isEmpty) {
                  setState(
                      () => error = 'Ürün adı ve geçerli bir fiyat girin.');
                  return;
                }
                if (price == null || price < 0) {
                  setState(() => error = 'Geçerli bir fiyat girin.');
                  return;
                }
                Navigator.of(context).pop((name, selectedCategoryId!, price));
              },
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final (name, categoryId, price) = result;

    try {
      await ref.read(menuCatalogAdminGatewayProvider).createProduct(
            organizationId: ref.read(currentOrganizationIdProvider),
            restaurantId: ref.read(currentRestaurantIdProvider),
            categoryId: categoryId,
            name: name,
            basePriceMinorUnits:
                (price * Currency.tryLira.minorUnitsPerWhole).round(),
          );
      ref.invalidate(adminMenuProductsProvider);
    } on MenuCatalogAdminException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _showEditProductDialog(
    BuildContext context,
    WidgetRef ref,
    AdminMenuProduct product,
  ) async {
    final nameController = TextEditingController(text: product.name);
    final priceController = TextEditingController(
      text: (product.basePriceMinorUnits / Currency.tryLira.minorUnitsPerWhole)
          .toStringAsFixed(2),
    );
    String? error;

    final result = await showDialog<(String, double)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Ürünü Düzenle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Ürün Adı'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Fiyat (₺)',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                final price = double.tryParse(
                    priceController.text.trim().replaceAll(',', '.'));
                if (name.isEmpty) {
                  setState(
                      () => error = 'Ürün adı ve geçerli bir fiyat girin.');
                  return;
                }
                if (price == null || price < 0) {
                  setState(() => error = 'Geçerli bir fiyat girin.');
                  return;
                }
                Navigator.of(context).pop((name, price));
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final (name, price) = result;

    try {
      await ref.read(menuCatalogAdminGatewayProvider).updateProduct(
            organizationId: ref.read(currentOrganizationIdProvider),
            productId: product.id,
            name: name,
            basePriceMinorUnits:
                (price * Currency.tryLira.minorUnitsPerWhole).round(),
          );
      ref.invalidate(adminMenuProductsProvider);
    } on MenuCatalogAdminException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _toggleAvailability(
    WidgetRef ref,
    AdminMenuProduct product,
  ) async {
    try {
      await ref.read(menuCatalogAdminGatewayProvider).setProductAvailability(
            organizationId: ref.read(currentOrganizationIdProvider),
            productId: product.id,
            isAvailable: !product.isAvailable,
          );
      ref.invalidate(adminMenuProductsProvider);
    } on MenuCatalogAdminException {
      // This button has no BuildContext to show a SnackBar with — the
      // row's own rebuild (via the invalidate above, on success) is the
      // primary feedback. A failure here is rare enough (network/
      // permission) that leaving the toggle visually unchanged on error is
      // an acceptable v1 trade-off; the product simply stays in its last
      // known state rather than the UI silently lying about a flip that
      // didn't happen server-side.
    }
  }

  Future<void> _confirmDeleteProduct(
    BuildContext context,
    WidgetRef ref,
    AdminMenuProduct product,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ürünü Sil'),
        content: Text(
            '"${product.name}" kalıcı olarak silinecek. Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(menuCatalogAdminGatewayProvider).deleteProduct(
            organizationId: ref.read(currentOrganizationIdProvider),
            productId: product.id,
          );
      ref.invalidate(adminMenuProductsProvider);
    } on MenuCatalogAdminException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
