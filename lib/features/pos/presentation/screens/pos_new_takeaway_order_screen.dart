import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../menu/domain/models/selected_modifier.dart';
import '../../../menu/presentation/providers/menu_catalog_provider.dart';
import '../../../takeaway/data/submit_takeaway_order_gateway.dart';
import '../../../takeaway/presentation/providers/takeaway_dependencies_provider.dart';
import '../../data/pos_action_gateway.dart' show PosDeviceContext;
import '../widgets/pos_product_customization_dialog.dart';

/// Adım 5 (2026-11-07) — "Yeni Paket Sipariş": the staff-initiated takeaway
/// order creation flow `pos_takeaway_orders_screen.dart`'s FAB-equivalent
/// button opens. Deliberately a flat, searchable product list rather than
/// the full category-tabbed grid `pos_table_workspace_screen.dart`'s staff
/// entry uses — this flow is secondary/occasional (most takeaway orders
/// are still customer-initiated), matching the "temel arayüz" (basic
/// interface) scope the roadmap item asked for. Reuses
/// [PosProductCustomizationDialog] exactly as the table workspace does for
/// a product with required modifiers/removable ingredients.
class PosNewTakeawayOrderScreen extends ConsumerStatefulWidget {
  const PosNewTakeawayOrderScreen({super.key, required this.ctx});

  final PosDeviceContext ctx;

  @override
  ConsumerState<PosNewTakeawayOrderScreen> createState() =>
      _PosNewTakeawayOrderScreenState();
}

class _TakeawayCartLine {
  _TakeawayCartLine({
    required this.product,
    this.selectedModifiers = const [],
    this.excludedIngredients = const [],
    this.note = '',
  });

  final MenuProduct product;
  final List<SelectedModifier> selectedModifiers;
  final List<String> excludedIngredients;
  final String note;
  int quantity = 1;

  double get unitPrice =>
      product.basePrice +
      selectedModifiers.fold(0.0, (sum, m) => sum + m.extraPrice);

  double get totalRowPrice => unitPrice * quantity;
}

class _PosNewTakeawayOrderScreenState
    extends ConsumerState<PosNewTakeawayOrderScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _searchController = TextEditingController();
  String _search = '';
  final List<_TakeawayCartLine> _cartLines = [];
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _needsCustomization(MenuProduct product) =>
      product.modifierGroups.any((group) => group.isRequired) ||
      product.removableIngredients.isNotEmpty;

  Future<void> _addProduct(MenuProduct product) async {
    if (!_needsCustomization(product)) {
      setState(() => _cartLines.add(_TakeawayCartLine(product: product)));
      return;
    }
    final result = await PosProductCustomizationDialog.show(context, product);
    if (result == null || !mounted) return;
    setState(() {
      _cartLines.add(
        _TakeawayCartLine(
          product: product,
          selectedModifiers: result.selectedModifiers,
          excludedIngredients: result.excludedIngredients,
          note: result.note,
        )..quantity = result.quantity,
      );
    });
  }

  double get _total =>
      _cartLines.fold(0.0, (sum, line) => sum + line.totalRowPrice);

  Future<void> _submit() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final phone = _phoneController.text.trim();
    if (firstName.isEmpty || lastName.isEmpty || phone.isEmpty) {
      setState(() => _error = 'Ad, soyad ve telefon alanları zorunludur.');
      return;
    }
    if (_cartLines.isEmpty) {
      setState(() => _error = 'Sepete en az bir ürün eklemelisiniz.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(submitTakeawayOrderGatewayProvider).submitStaffEntryOrder(
        submissionKey: DateTime.now().microsecondsSinceEpoch.toString(),
        organizationId: widget.ctx.organizationId,
        branchId: widget.ctx.branchId,
        deviceId: widget.ctx.deviceId,
        deviceSessionId: widget.ctx.deviceSessionId,
        contactFirstName: firstName,
        contactLastName: lastName,
        contactPhone: phone,
        items: [
          for (final line in _cartLines)
            TakeawayProductItem(
              productId: line.product.id,
              quantity: line.quantity,
              selectedModifiers: [
                for (final modifier in line.selectedModifiers)
                  (groupId: modifier.groupId, optionId: modifier.optionId),
              ],
              note: line.note,
              excludedIngredients: line.excludedIngredients,
            ),
        ],
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SubmitTakeawayOrderException catch (e) {
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allProducts =
        ref.watch(menuProductsProvider).where((p) => p.isAvailable).toList();
    final query = _search.trim().toLowerCase();
    final visibleProducts = query.isEmpty
        ? allProducts
        : allProducts
            .where((p) => p.name.toLowerCase().contains(query))
            .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Paket Sipariş')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('takeawayFirstNameField'),
                        controller: _firstNameController,
                        decoration: const InputDecoration(labelText: 'Ad'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        key: const Key('takeawayLastNameField'),
                        controller: _lastNameController,
                        decoration: const InputDecoration(labelText: 'Soyad'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const Key('takeawayPhoneField'),
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Telefon'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: TextField(
                          key: const Key('takeawayProductSearchField'),
                          controller: _searchController,
                          onChanged: (value) => setState(() => _search = value),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Ürün ara...',
                            prefixIcon: Icon(Icons.search_rounded, size: 20),
                            border: OutlineInputBorder(
                                borderRadius: AppRadius.kPill),
                          ),
                        ),
                      ),
                      Expanded(
                        child: visibleProducts.isEmpty
                            ? const EmptyView(
                                icon: Icons.search_off_rounded,
                                message: 'Ürün bulunamadı.',
                              )
                            : ListView.builder(
                                itemCount: visibleProducts.length,
                                itemBuilder: (context, index) {
                                  final product = visibleProducts[index];
                                  return ListTile(
                                    key: Key('takeawayProduct_${product.id}'),
                                    title: Text(product.name),
                                    subtitle: Text(
                                        '${product.basePrice.toStringAsFixed(0)} TL'),
                                    trailing: IconButton(
                                      icon: const Icon(
                                          Icons.add_circle_outline_rounded),
                                      onPressed: () => _addProduct(product),
                                    ),
                                    onTap: () => _addProduct(product),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child:
                              Text('Sepet', style: AppTypography.titleMedium),
                        ),
                      ),
                      Expanded(
                        child: _cartLines.isEmpty
                            ? const EmptyView(
                                icon: Icons.shopping_basket_outlined,
                                message: 'Sepet boş.',
                              )
                            : ListView.builder(
                                itemCount: _cartLines.length,
                                itemBuilder: (context, index) {
                                  final line = _cartLines[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(line.product.name),
                                    subtitle: Text(
                                        '${line.quantity} x ${line.unitPrice.toStringAsFixed(0)} TL'),
                                    trailing: IconButton(
                                      icon: const Icon(
                                          Icons.delete_outline_rounded),
                                      onPressed: () => setState(
                                          () => _cartLines.removeAt(index)),
                                    ),
                                  );
                                },
                              ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md),
                          child: Text(_error!,
                              style: AppTypography.bodySmall
                                  .copyWith(color: AppColors.error)),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_total.toStringAsFixed(0)} TL',
                                style: AppTypography.titleMedium,
                              ),
                            ),
                            ElevatedButton(
                              key: const Key('submitNewTakeawayOrderButton'),
                              onPressed: _submitting ? null : _submit,
                              child: _submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Text('Siparişi Oluştur'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
