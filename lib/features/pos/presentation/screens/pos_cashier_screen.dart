import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/money.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/cards/option_selection_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../../shared/widgets/images/product_image.dart';
import '../../../../shared/widgets/layout/app_section_header.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../menu/domain/models/modifier_group.dart';
import '../../../menu/domain/models/selected_modifier.dart';
import '../../../menu/presentation/providers/menu_catalog_provider.dart';
import '../../../orders/domain/discounts/discount.dart';
import '../../../orders/domain/models/order.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../orders/domain/receipt/foreign_currency_equivalent.dart';
import '../../domain/models/discount_preset.dart';
import '../../domain/models/discount_preset_seed_data.dart';
import '../../domain/models/pos_order_session.dart';
import '../providers/pos_foreign_currency_equivalents_provider.dart';
import '../providers/pos_order_session_provider.dart';
import 'pos_payment_screen.dart';

/// The first functional cashier order flow — standalone this sprint (see
/// `docs/decisions.md`): not registered with `go_router`, not reachable
/// from `MainNavigationScreen`, no staff-auth gate. Directly constructible
/// for tests and for a future staff-shell integration to push.
///
/// Every identity value ([sessionId]/[branchId]/[openedByStaffId]/
/// [restaurantId]) is a required constructor parameter — this screen
/// never generates one itself, matching this sprint's "no ID generation
/// outside `OrderIdentityProvider`" rule extended to session identity too.
class PosCashierScreen extends ConsumerStatefulWidget {
  const PosCashierScreen({
    super.key,
    required this.sessionId,
    required this.branchId,
    required this.openedByStaffId,
    required this.restaurantId,
    this.channel = OrderChannel.dineInStaff,
  });

  final String sessionId;
  final String branchId;
  final String openedByStaffId;
  final String restaurantId;
  final OrderChannel channel;

  @override
  ConsumerState<PosCashierScreen> createState() => _PosCashierScreenState();
}

class _PosCashierScreenState extends ConsumerState<PosCashierScreen> {
  final _customerNoteController = TextEditingController();
  final _kitchenNoteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSession());
  }

  void _startSession() {
    ref.read(posOrderSessionProvider.notifier).startSession(
          sessionId: widget.sessionId,
          branchId: widget.branchId,
          openedByStaffId: widget.openedByStaffId,
          channel: widget.channel,
        );
  }

  @override
  void dispose() {
    _customerNoteController.dispose();
    _kitchenNoteController.dispose();
    super.dispose();
  }

  /// The moment a submission succeeds, this screen pushes
  /// [PosPaymentScreen] for the resulting `Order` — per the approved
  /// architecture, payment collection always starts after a real `Order`/
  /// `OrderId` exists, never before (`docs/decisions.md` ADR-012).
  /// `PosCashierScreen` itself has no route/consumer anywhere in this app
  /// (confirmed before wiring this — see ADR-012's risk note), so pushing
  /// directly here is local and safe: no `go_router`/`MainNavigationScreen`
  /// change involved. `_SubmittedOrderView` remains as the screen shown if
  /// the cashier navigates back from the payment screen (e.g. via the
  /// system back gesture), rather than leaving a blank/idle screen behind.
  ///
  /// The payment session's own id is deterministically derived from the
  /// order id (`'<orderId>-payment'`) — never a timestamp/random value/
  /// UUID, matching `SubmitPosOrder`'s own `auditEntryId` precedent. A
  /// second payment session for the same order (a reopen scenario) is
  /// `ReopenClosedOrder`'s concern, not this screen's.
  void _openPaymentScreen(Order order) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PosPaymentScreen(
          sessionId: '${order.id.value}-payment',
          order: order,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posOrderSessionProvider);

    ref.listen<PosOrderSessionState>(posOrderSessionProvider, (previous, next) {
      final justSubmitted = previous?.status != PosOrderSessionStatus.submitted &&
          next.status == PosOrderSessionStatus.submitted &&
          next.submittedOrder != null;
      if (justSubmitted) {
        _openPaymentScreen(next.submittedOrder!);
      }
    });

    // Keep the note fields in sync with the session without fighting the
    // user's own cursor position — only overwrite when the underlying
    // value actually differs (e.g. after starting a new session).
    final session = state.session;
    if (session != null) {
      if (_customerNoteController.text != session.customerNote) {
        _customerNoteController.text = session.customerNote;
      }
      if (_kitchenNoteController.text != session.kitchenNote) {
        _kitchenNoteController.text = session.kitchenNote;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kasa (POS)'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: switch (state.status) {
          PosOrderSessionStatus.idle => const LoadingView(
              message: 'Sipariş oturumu başlatılıyor...',
            ),
          PosOrderSessionStatus.submitted => _SubmittedOrderView(
              order: state.submittedOrder!,
              onStartNewOrder: _startSession,
            ),
          PosOrderSessionStatus.editing ||
          PosOrderSessionStatus.submitting ||
          PosOrderSessionStatus.failure =>
            _EditingLayout(
              session: session,
              isSubmitting: state.status == PosOrderSessionStatus.submitting,
              errorMessage: state.status == PosOrderSessionStatus.failure
                  ? state.error?.description
                  : null,
              customerNoteController: _customerNoteController,
              kitchenNoteController: _kitchenNoteController,
              restaurantId: widget.restaurantId,
            ),
        },
      ),
    );
  }
}

class _SubmittedOrderView extends StatelessWidget {
  const _SubmittedOrderView({required this.order, required this.onStartNewOrder});

  final Order order;
  final VoidCallback onStartNewOrder;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 72,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Sipariş oluşturuldu',
              style: AppTypography.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${order.orderNumber} — ${order.pricing.grandTotal}',
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton(
              onPressed: onStartNewOrder,
              child: const Text('Yeni Sipariş Başlat'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditingLayout extends ConsumerWidget {
  const _EditingLayout({
    required this.session,
    required this.isSubmitting,
    required this.errorMessage,
    required this.customerNoteController,
    required this.kitchenNoteController,
    required this.restaurantId,
  });

  final PosOrderSession? session;
  final bool isSubmitting;
  final String? errorMessage;
  final TextEditingController customerNoteController;
  final TextEditingController kitchenNoteController;
  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (session == null) {
      return const LoadingView();
    }

    final productPanel = _ProductPanel(session: session!);
    final orderPanel = _OrderPanel(
      session: session!,
      isSubmitting: isSubmitting,
      errorMessage: errorMessage,
      customerNoteController: customerNoteController,
      kitchenNoteController: kitchenNoteController,
      restaurantId: restaurantId,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= AppBreakpoints.tablet;
        if (isWide) {
          return Row(
            children: [
              Expanded(flex: 3, child: productPanel),
              const VerticalDivider(width: 1, color: AppColors.border),
              Expanded(flex: 2, child: orderPanel),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: productPanel),
            const Divider(height: 1, color: AppColors.border),
            Expanded(child: orderPanel),
          ],
        );
      },
    );
  }
}

class _ProductPanel extends ConsumerStatefulWidget {
  const _ProductPanel({required this.session});

  final PosOrderSession session;

  @override
  ConsumerState<_ProductPanel> createState() => _ProductPanelState();
}

class _ProductPanelState extends ConsumerState<_ProductPanel> {
  String? _selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(menuCategoriesProvider);
    final products = ref.watch(menuProductsProvider);
    final visibleProducts = _selectedCategoryId == null
        ? products
        : products
            .where((product) => product.categoryId == _selectedCategoryId)
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            0,
          ),
          child: AppSectionHeader(title: 'Ürünler'),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            children: [
              _CategoryChip(
                label: 'Tümü',
                isSelected: _selectedCategoryId == null,
                onTap: () => setState(() => _selectedCategoryId = null),
              ),
              for (final category in categories)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: _CategoryChip(
                    label: category.name,
                    isSelected: _selectedCategoryId == category.id,
                    onTap: () =>
                        setState(() => _selectedCategoryId = category.id),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: visibleProducts.isEmpty
              ? const EmptyView(
                  icon: Icons.restaurant_menu_rounded,
                  message: 'Bu kategoride ürün yok',
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: AppBreakpoints.columnsForWidth(
                      MediaQuery.sizeOf(context).width,
                    ),
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: visibleProducts.length,
                  itemBuilder: (context, index) {
                    final product = visibleProducts[index];
                    return _ProductTile(product: product, session: widget.session);
                  },
                ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primaryExtraLight,
      labelStyle: AppTypography.bodyMedium.copyWith(
        color: isSelected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.product, required this.session});

  final MenuProduct product;
  final PosOrderSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: AppRadius.kMedium,
      onTap: !product.isAvailable
          ? null
          : () => _handleTap(context, ref),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ProductImage(imageKey: product.imageKey, width: double.infinity),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              product.name,
              style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${product.basePrice.toStringAsFixed(0)} TL',
              style: AppTypography.bodySmall.copyWith(color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    if (product.modifierGroups.isEmpty) {
      ref.read(posOrderSessionProvider.notifier).addProduct(product: product);
      return;
    }
    final selected = await showModalBottomSheet<List<SelectedModifier>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ModifierSelectionSheet(product: product),
    );
    if (selected != null) {
      ref.read(posOrderSessionProvider.notifier).addProduct(
            product: product,
            selectedModifiers: selected,
          );
    }
  }
}

class _ModifierSelectionSheet extends StatefulWidget {
  const _ModifierSelectionSheet({required this.product});

  final MenuProduct product;

  @override
  State<_ModifierSelectionSheet> createState() =>
      _ModifierSelectionSheetState();
}

class _ModifierSelectionSheetState extends State<_ModifierSelectionSheet> {
  final Map<String, Set<String>> _selectionsByGroup = {};

  void _toggle(ModifierGroup group, String optionId) {
    setState(() {
      final current = _selectionsByGroup.putIfAbsent(group.id, () => {});
      if (group.selectionType == ModifierSelectionType.single) {
        current
          ..clear()
          ..add(optionId);
      } else {
        if (current.contains(optionId)) {
          current.remove(optionId);
        } else {
          current.add(optionId);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.product.name, style: AppTypography.titleMedium),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final group in widget.product.modifierGroups) ...[
                        Text(group.name, style: AppTypography.bodyLarge),
                        const SizedBox(height: AppSpacing.xs),
                        for (final option in group.options)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: OptionSelectionCard(
                              name: option.name,
                              extraPrice: option.extraPrice,
                              isSelected: _selectionsByGroup[group.id]
                                      ?.contains(option.id) ??
                                  false,
                              onTap: !option.isAvailable
                                  ? () {}
                                  : () => _toggle(group, option.id),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(_buildSelections()),
                child: const Text('Siparişe Ekle'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<SelectedModifier> _buildSelections() {
    final result = <SelectedModifier>[];
    for (final group in widget.product.modifierGroups) {
      final selectedOptionIds = _selectionsByGroup[group.id] ?? const {};
      for (final option in group.options) {
        if (selectedOptionIds.contains(option.id)) {
          result.add(
            SelectedModifier(
              groupId: group.id,
              groupName: group.name,
              optionId: option.id,
              optionName: option.name,
              extraPrice: option.extraPrice,
            ),
          );
        }
      }
    }
    return result;
  }
}

class _OrderPanel extends ConsumerStatefulWidget {
  const _OrderPanel({
    required this.session,
    required this.isSubmitting,
    required this.errorMessage,
    required this.customerNoteController,
    required this.kitchenNoteController,
    required this.restaurantId,
  });

  final PosOrderSession session;
  final bool isSubmitting;
  final String? errorMessage;
  final TextEditingController customerNoteController;
  final TextEditingController kitchenNoteController;
  final String restaurantId;

  @override
  ConsumerState<_OrderPanel> createState() => _OrderPanelState();
}

class _OrderPanelState extends ConsumerState<_OrderPanel> {
  /// Which line quick-discount presets currently target — UI-only
  /// selection state, not part of `PosOrderSession` itself.
  String? _selectedLineId;

  @override
  void didUpdateWidget(covariant _OrderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the selected line was removed, clear the selection rather than
    // silently pointing quick-discount presets at a line that no longer
    // exists.
    if (_selectedLineId != null &&
        !widget.session.lines.any((draft) => draft.id == _selectedLineId)) {
      _selectedLineId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(posOrderSessionProvider.notifier);
    final session = widget.session;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            0,
          ),
          child: AppSectionHeader(title: 'Mevcut Sipariş'),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (session.lines.isEmpty)
                  const EmptyView(
                    icon: Icons.shopping_basket_outlined,
                    message: 'Siparişe henüz ürün eklenmedi',
                  )
                else
                  for (final draft in session.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _CartLineTile(
                        name: draft.item.name,
                        quantity: draft.item.quantity,
                        lineTotal: draft.item.totalRowPrice,
                        isSelected: draft.id == _selectedLineId,
                        discountLabel: _activeLineDiscountLabel(session, draft.id),
                        onTap: () => setState(() {
                          _selectedLineId =
                              _selectedLineId == draft.id ? null : draft.id;
                        }),
                        onIncrement: () => notifier.updateLine(
                          orderLineDraftId: draft.id,
                          quantity: draft.item.quantity + 1,
                        ),
                        onDecrement: draft.item.quantity > 1
                            ? () => notifier.updateLine(
                                  orderLineDraftId: draft.id,
                                  quantity: draft.item.quantity - 1,
                                )
                            : null,
                        onRemove: () => notifier.removeLine(draft.id),
                      ),
                    ),
                if (session.lines.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _QuickDiscountBar(
                    enabled: _selectedLineId != null,
                    hasActiveDiscount: _selectedLineId != null &&
                        _activeLineDiscountLabel(session, _selectedLineId!) !=
                            null,
                    onPresetTap: (preset) => notifier.setDiscount(
                      scope: DiscountScope.line,
                      targetOrderLineId: _selectedLineId,
                      preset: preset,
                      appliedByStaffId: session.openedByStaffId,
                    ),
                    onClearTap: () => notifier.setDiscount(
                      scope: DiscountScope.line,
                      targetOrderLineId: _selectedLineId,
                      preset: null,
                      appliedByStaffId: session.openedByStaffId,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: widget.customerNoteController,
                  decoration: const InputDecoration(labelText: 'Müşteri Notu'),
                  onChanged: (value) =>
                      notifier.updateNotes(customerNote: value),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: widget.kitchenNoteController,
                  decoration: const InputDecoration(labelText: 'Mutfak Notu'),
                  onChanged: (value) =>
                      notifier.updateNotes(kitchenNote: value),
                ),
                const SizedBox(height: AppSpacing.md),
                _PriceSummary(session: session),
                if (widget.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: ErrorView(message: widget.errorMessage!),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      widget.isSubmitting ? null : notifier.cancelSession,
                  child: const Text('Siparişi Temizle'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: widget.isSubmitting || session.lines.isEmpty
                      ? null
                      : () => notifier.submit(restaurantId: widget.restaurantId),
                  child: widget.isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : const Text('Siparişi Gönder'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Reads (never computes) the already-frozen discount amount for
  /// [orderLineDraftId], if any — all financial math happens in
  /// `SetPosDiscount`, never here.
  String? _activeLineDiscountLabel(PosOrderSession session, String orderLineDraftId) {
    for (final discount in session.discounts) {
      if (discount.scope == DiscountScope.line &&
          discount.targetOrderLineId == orderLineDraftId) {
        return '${discount.discountName} indirim: -${discount.discountAmount}';
      }
    }
    return null;
  }
}

class _QuickDiscountBar extends StatelessWidget {
  const _QuickDiscountBar({
    required this.enabled,
    required this.hasActiveDiscount,
    required this.onPresetTap,
    required this.onClearTap,
  });

  final bool enabled;
  final bool hasActiveDiscount;
  final ValueChanged<DiscountPreset> onPresetTap;
  final VoidCallback onClearTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          enabled
              ? 'Hızlı indirim (seçili ürüne uygulanır)'
              : 'Hızlı indirim uygulamak için önce bir ürün seçin',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            for (final preset in DiscountPresetSeedData.all)
              OutlinedButton(
                onPressed: enabled ? () => onPresetTap(preset) : null,
                child: Text(preset.name),
              ),
            if (hasActiveDiscount)
              TextButton(
                onPressed: enabled ? onClearTap : null,
                child: const Text('İndirimi Kaldır'),
              ),
          ],
        ),
      ],
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.name,
    required this.quantity,
    required this.lineTotal,
    required this.isSelected,
    required this.discountLabel,
    required this.onTap,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  final String name;
  final int quantity;
  final double lineTotal;
  final bool isSelected;
  final String? discountLabel;
  final VoidCallback onTap;
  final VoidCallback onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.kMedium,
      onTap: onTap,
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        borderColor: isSelected ? AppColors.primary : null,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppTypography.bodyLarge),
                  Text(
                    '${lineTotal.toStringAsFixed(2)} TL',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (discountLabel != null)
                    Text(
                      discountLabel!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: onDecrement,
            ),
            Text('$quantity', style: AppTypography.bodyLarge),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: onIncrement,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceSummary extends ConsumerWidget {
  const _PriceSummary({required this.session});

  final PosOrderSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pricing = session.pricing;
    final equivalents = ref.watch(posForeignCurrencyEquivalentsProvider);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryRow(label: 'Ara Toplam', amount: pricing.grossSubtotal),
          _SummaryRow(label: 'İndirim', amount: pricing.discount, isNegative: true),
          _SummaryRow(label: 'Hizmet Bedeli', amount: pricing.serviceFee),
          _SummaryRow(label: 'Bahşiş', amount: pricing.tip),
          _SummaryRow(label: 'KDV', amount: pricing.vatAmount),
          const Divider(color: AppColors.border),
          _SummaryRow(
            label: 'Genel Toplam',
            amount: pricing.grandTotal,
            isTotal: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          equivalents.when(
            data: (values) => values.isEmpty
                ? Text(
                    'Döviz kuru şu anda kullanılamıyor',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final equivalent in values)
                        _ForeignEquivalentRow(equivalent: equivalent),
                    ],
                  ),
            loading: () => Text(
              'Döviz kuru hesaplanıyor...',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            error: (error, stackTrace) => Text(
              'Döviz kuru şu anda kullanılamıyor',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.amount,
    this.isTotal = false,
    this.isNegative = false,
  });

  final String label;
  final Money amount;
  final bool isTotal;
  final bool isNegative;

  @override
  Widget build(BuildContext context) {
    final style = isTotal
        ? AppTypography.titleMedium
        : AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary);
    final sign = isNegative && amount.isPositive ? '-' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label, style: style, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('$sign$amount', style: style),
        ],
      ),
    );
  }
}

class _ForeignEquivalentRow extends StatelessWidget {
  const _ForeignEquivalentRow({required this.equivalent});

  final ForeignCurrencyEquivalent equivalent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Yaklaşık ${equivalent.currency.isoCode}',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            '${equivalent.currency.symbol}${(equivalent.amount.minorUnits / equivalent.currency.minorUnitsPerWhole).toStringAsFixed(2)}',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
