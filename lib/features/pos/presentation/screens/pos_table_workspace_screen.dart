import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../../shared/widgets/images/product_image.dart';
import '../../../admin/data/tenant_customer_directory_gateway.dart';
import '../../../admin/domain/approval/approval_request.dart';
import '../../../admin/presentation/providers/admin_dependencies_provider.dart';
import '../../../admin/presentation/screens/approval_inbox_screen.dart';
import '../../../admin/presentation/screens/trusted_device_status_screen.dart';
import '../../../menu/domain/models/menu_category.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../menu/domain/models/selected_modifier.dart';
import '../../../menu/presentation/providers/menu_catalog_provider.dart';
import '../../data/pos_action_gateway.dart';
import '../../data/pos_operational_view_gateway.dart';
import '../providers/actor_session_provider.dart';
import '../providers/kds_dependencies_provider.dart';
import '../providers/pos_workspace_providers.dart';
import '../widgets/pos_operational_rail.dart';
import '../widgets/pos_product_customization_dialog.dart';
import 'pos_cash_register_screen.dart';
import 'pos_checkout_screen.dart';

/// The real open-table three-pane POS workspace — AP-3 continuation
/// (`docs/decisions.md` ADR-041's own "no longer blocked" follow-up).
/// Center pane: table/order/sub-account view with per-line accept/reject/
/// propose-replacement and staff order entry. Right pane: check panel —
/// open, all five split modes, table transfer/merge, finalize to
/// `readyForPayment`. **AP-4 Wave D correction**: once a check reaches
/// `readyForPayment`/`paid`, `_CheckPanel` now shows a real "Ödemeye Git"
/// button pushing `PosCheckoutScreen` — the previous "payment unavailable,
/// AP-4 scope" dead-end no longer exists.
class PosTableWorkspaceScreen extends ConsumerStatefulWidget {
  const PosTableWorkspaceScreen({super.key});

  @override
  ConsumerState<PosTableWorkspaceScreen> createState() =>
      _PosTableWorkspaceScreenState();
}

class _PosTableWorkspaceScreenState
    extends ConsumerState<PosTableWorkspaceScreen> {
  PosTableOperationalView? _view;
  Object? _error;
  bool _busy = false;
  String? _actionError;
  String? _openedCheckId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String? get _tableId => ref.read(selectedPosTableIdProvider);

  Future<void> _load() async {
    final ctx = ref.read(posDeviceContextProvider);
    final tableId = _tableId;
    if (ctx == null || tableId == null) return;
    setState(() => _error = null);
    try {
      final view =
          await ref.read(posOperationalViewGatewayProvider).getTableView(
                organizationId: ctx.organizationId,
                branchId: ctx.branchId,
                tableId: tableId,
                deviceId: ctx.deviceId,
                deviceSessionId: ctx.deviceSessionId,
              );
      if (!mounted) return;
      setState(() {
        _view = view;
        final openCheck =
            view.checks.where((c) => c['status'] == 'open').toList();
        _openedCheckId = openCheck.isNotEmpty
            ? openCheck.first['id'] as String? ??
                openCheck.first['checkId'] as String?
            : _openedCheckId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<T?> _runAction<T>(Future<T> Function() action) async {
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      final result = await action();
      await _load();
      return result;
    } on PosActionException catch (e) {
      setState(() => _actionError = e.message);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = ref.watch(posDeviceContextProvider);
    if (ctx == null) {
      return const TrustedDeviceStatusScreen(capabilities: ['POS']);
    }
    final tableId = _tableId;
    if (tableId == null) {
      return const Scaffold(body: Center(child: Text('Masa seçilmedi.')));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            PosOperationalRail(
              onBack: () => Navigator.of(context).pop(),
              onCashRegister: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const PosCashRegisterScreen()),
              ),
            ),
            Expanded(child: _buildBody(ctx, tableId)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(PosDeviceContext ctx, String tableId) {
    final error = _error;
    final view = _view;
    if (error != null && view == null) {
      return ErrorView(
        message: 'Masa bilgisi yüklenirken bir sorun oluştu.',
        retryLabel: 'Tekrar Dene',
        onRetry: _load,
      );
    }
    if (view == null) {
      return const LoadingView(message: 'Masa yükleniyor...');
    }

    return _PosWorkbench(
      ctx: ctx,
      view: view,
      checkId: _openedCheckId,
      busy: _busy,
      actionError: _actionError,
      onAcceptReject: (orderId, lineIndex, accept) => _runAction(
        () => ref.read(posActionGatewayProvider).respondToOrderLines(
          orderId: orderId,
          decisions: [(lineIndex: lineIndex, accept: accept)],
        ),
      ),
      onPropose: (orderId, lineIndex, productId, quantity, reasonCode,
              reasonMessage) =>
          _runAction(
        () => ref.read(posActionGatewayProvider).proposeLineReplacement(
              ctx: ctx,
              orderId: orderId,
              lineIndex: lineIndex,
              proposedProductId: productId,
              proposedQuantity: quantity,
              reasonCode: reasonCode,
              reasonMessage: reasonMessage,
            ),
      ),
      onStaffEntry: (subAccountSelection, items) => _runAction(
        () => ref.read(posActionGatewayProvider).submitStaffEntryOrder(
          ctx: ctx,
          tableId: tableId,
          subAccountSelection: subAccountSelection,
          items: [
            for (final item in items)
              {
                'kind': 'product',
                'productId': item.productId,
                'quantity': item.quantity,
                'selectedModifiers': [
                  for (final modifier in item.selectedModifiers)
                    {
                      'groupId': modifier.groupId,
                      'optionId': modifier.optionId,
                    },
                ],
                'note': item.note,
                'excludedIngredients': item.excludedIngredients,
              },
          ],
        ),
      ),
      onCancelRequest: (orderId, lineIndex, reasonCode, reasonMessage) =>
          _runAction(
        () =>
            ref.read(posActionGatewayProvider).requestAcceptedLineCancellation(
                  ctx: ctx,
                  orderId: orderId,
                  lineIndex: lineIndex,
                  reasonCode: reasonCode,
                  reasonMessage: reasonMessage,
                ),
      ),
      onOpenCheck: () async {
        final tableSessionId = view.tableSessionId;
        if (tableSessionId == null) return;
        final checkId = await _runAction(
          () => ref.read(posActionGatewayProvider).openCheck(
                ctx: ctx,
                tableSessionId: tableSessionId,
              ),
        );
        if (checkId != null) setState(() => _openedCheckId = checkId);
      },
      onSplit: (subAccountId, sourceOrderId, sourceLineIndex, mode) async {
        final gateway = ref.read(posActionGatewayProvider);
        final checkId = _openedCheckId;
        if (checkId == null) return;
        await _runAction(() {
          switch (mode) {
            case 'product':
              return gateway.splitByProduct(
                ctx: ctx,
                checkId: checkId,
                subAccountId: subAccountId,
                sourceOrderId: sourceOrderId,
                sourceLineIndex: sourceLineIndex,
              );
            case 'customer':
              return gateway.splitByCustomer(
                ctx: ctx,
                checkId: checkId,
                subAccountId: subAccountId,
              );
            default:
              throw StateError('Unknown split mode $mode');
          }
        });
      },
      onQuantitySplit:
          (subAccountId, sourceOrderId, sourceLineIndex, quantity) async {
        final checkId = _openedCheckId;
        if (checkId == null) return;
        await _runAction(
          () => ref.read(posActionGatewayProvider).splitByQuantity(
                ctx: ctx,
                checkId: checkId,
                subAccountId: subAccountId,
                sourceOrderId: sourceOrderId,
                sourceLineIndex: sourceLineIndex,
                quantity: quantity,
              ),
        );
      },
      onFreeAmountSplit: (subAccountId, sourceOrderId, sourceLineIndex,
          amountMinorUnits) async {
        final checkId = _openedCheckId;
        if (checkId == null) return;
        await _runAction(
          () => ref.read(posActionGatewayProvider).splitFreeAmount(
                ctx: ctx,
                checkId: checkId,
                subAccountId: subAccountId,
                amountMinorUnits: amountMinorUnits,
                sourceOrderId: sourceOrderId,
                sourceLineIndex: sourceLineIndex,
              ),
        );
      },
      onHeadcountSplit: (subAccountIds) async {
        final checkId = _openedCheckId;
        if (checkId == null) return;
        await _runAction(
          () => ref.read(posActionGatewayProvider).splitEqualByHeadcount(
                ctx: ctx,
                checkId: checkId,
                subAccountIds: subAccountIds,
              ),
        );
      },
      onRequestAdjustment: ({
        required scope,
        allocationId,
        subAccountId,
        required adjustmentType,
        percentageBasisPoints,
        fixedAmountMinorUnits,
        required reasonCode,
        required reasonMessage,
      }) async {
        final checkId = _openedCheckId;
        if (checkId == null) return;
        await _runAction(
          () => ref
              .read(posActionGatewayProvider)
              .requestCheckFinancialAdjustment(
                ctx: ctx,
                checkId: checkId,
                scope: scope,
                allocationId: allocationId,
                subAccountId: subAccountId,
                adjustmentType: adjustmentType,
                percentageBasisPoints: percentageBasisPoints,
                fixedAmountMinorUnits: fixedAmountMinorUnits,
                reasonCode: reasonCode,
                reasonMessage: reasonMessage,
              ),
        );
      },
      onFinalize: () => _runAction(
        () {
          final checkId = _openedCheckId;
          if (checkId == null) return Future.value();
          return ref
              .read(posActionGatewayProvider)
              .finalizeCheckReadyForPayment(
                ctx: ctx,
                checkId: checkId,
              );
        },
      ),
      onTransfer: (targetTableId) => _runAction(
        () => ref.read(posActionGatewayProvider).transferTable(
              ctx: ctx,
              sourceTableId: tableId,
              targetTableId: targetTableId,
            ),
      ),
      onMerge: (targetTableId) => _runAction(
        () => ref.read(posActionGatewayProvider).mergeTables(
              ctx: ctx,
              sourceTableId: tableId,
              targetTableId: targetTableId,
            ),
      ),
      onOpenCheckout: () {
        final checkId = _openedCheckId;
        if (checkId == null) return;
        Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (_) => PosCheckoutScreen(
                ctx: ctx,
                checkId: checkId,
                view: view,
              ),
            ))
            .then((_) => _load());
      },
    );
  }
}

typedef _AcceptRejectFn = Future<void> Function(
    String orderId, int lineIndex, bool accept);
typedef _ProposeFn = Future<void> Function(String orderId, int lineIndex,
    String productId, int quantity, String reasonCode, String reasonMessage);
typedef _StaffEntryFn = Future<String?> Function(
    Map<String, dynamic> subAccountSelection,
    List<
            ({
              String productId,
              int quantity,
              List<SelectedModifier> selectedModifiers,
              List<String> excludedIngredients,
              String note,
            })>
        items);
typedef _CancelLineFn = Future<void> Function(
    String orderId, int lineIndex, String reasonCode, String reasonMessage);

/// The real industry-standard 3-column touch POS layout — 2026-10-31,
/// replacing the previous two-pane "review orders / manage check in a
/// separate modal" split and the `_StaffEntryScreen` full-screen dialog it
/// used for adding products. Category rail (left) → product grid (center,
/// tap-to-add) → "Adisyon" panel (right): accepted lines, a running
/// local cart of not-yet-sent taps, the real payment button, and two
/// on-demand surfaces for everything that doesn't belong inline in a
/// touch list — pending customer-line review (a badge, opens a sheet
/// reusing [_OrderCard] exactly as the old always-visible pane did) and
/// table-level tools (split/transfer/discount, an "İşlemler" sheet
/// reusing [_CheckPanel]'s old body verbatim). Every real action below —
/// accept/reject/propose/cancel-request, 5 split modes, financial
/// adjustment, transfer/merge, finalize, checkout — is the exact same
/// `PosActionGateway` call this screen already had; nothing here invents
/// a new backend capability. Whole-check cancellation does **not**
/// exist server-side (confirmed by audit, 2026-10-31) and is
/// deliberately not represented by any button here — only the real,
/// already-wired single-line cancellation request is.
class _PosWorkbench extends ConsumerStatefulWidget {
  const _PosWorkbench({
    required this.ctx,
    required this.view,
    required this.checkId,
    required this.busy,
    required this.actionError,
    required this.onAcceptReject,
    required this.onPropose,
    required this.onCancelRequest,
    required this.onStaffEntry,
    required this.onOpenCheck,
    required this.onSplit,
    required this.onQuantitySplit,
    required this.onFreeAmountSplit,
    required this.onHeadcountSplit,
    required this.onRequestAdjustment,
    required this.onFinalize,
    required this.onTransfer,
    required this.onMerge,
    required this.onOpenCheckout,
  });

  final PosDeviceContext ctx;
  final PosTableOperationalView view;
  final String? checkId;
  final bool busy;
  final String? actionError;
  final _AcceptRejectFn onAcceptReject;
  final _ProposeFn onPropose;
  final _CancelLineFn onCancelRequest;
  final _StaffEntryFn onStaffEntry;
  final VoidCallback onOpenCheck;
  final _SplitFn onSplit;
  final _QuantitySplitFn onQuantitySplit;
  final _FreeAmountSplitFn onFreeAmountSplit;
  final _HeadcountSplitFn onHeadcountSplit;
  final _AdjustmentFn onRequestAdjustment;
  final VoidCallback onFinalize;
  final _TransferMergeFn onTransfer;
  final _TransferMergeFn onMerge;
  final VoidCallback onOpenCheckout;

  @override
  ConsumerState<_PosWorkbench> createState() => _PosWorkbenchState();
}

class _PosWorkbenchState extends ConsumerState<_PosWorkbench> {
  String _categoryFilter = _staffEntryTopSellersSentinel;
  final List<_StaffEntryCartLine> _cartLines = [];
  bool _sendingCart = false;

  /// Live product-grid search (2026-11-03) — filters by name as the staff
  /// types, independent of and combined with [_categoryFilter].
  final _productSearchController = TextEditingController();
  String _productSearchQuery = '';

  String _accountSelection = _staffEntryTableGeneralSentinel;
  final _walkInNameController = TextEditingController();
  final _customerSearchController = TextEditingController();
  List<TenantCustomerSearchResult> _customerSearchResults = const [];
  bool _searchingCustomers = false;
  TenantCustomerSearchResult? _linkedCustomer;

  bool get _useWalkIn => _accountSelection == _staffEntryWalkInSentinel;
  bool get _useTableGeneral =>
      _accountSelection == _staffEntryTableGeneralSentinel;
  bool get _useExistingCustomer =>
      _accountSelection == _staffEntryExistingCustomerSentinel;
  String? get _selectedSubAccountId =>
      (!_useWalkIn && !_useTableGeneral && !_useExistingCustomer)
          ? _accountSelection
          : null;

  double get _cartTotal =>
      _cartLines.fold(0.0, (sum, line) => sum + line.totalRowPrice);

  @override
  void dispose() {
    _walkInNameController.dispose();
    _customerSearchController.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  static final _phoneLikeQuery = RegExp(r'^[+\d][\d\s]*$');

  Future<void> _searchCustomers() async {
    final query = _customerSearchController.text.trim();
    if (query.isEmpty) return;
    final isPhoneLike = _phoneLikeQuery.hasMatch(query);
    setState(() => _searchingCustomers = true);
    try {
      final results =
          await ref.read(tenantCustomerDirectoryGatewayProvider).search(
                organizationId: widget.ctx.organizationId,
                phoneNumber: isPhoneLike ? query : null,
                namePrefix: isPhoneLike ? null : query,
              );
      if (mounted) setState(() => _customerSearchResults = results);
    } on TenantCustomerDirectoryException {
      if (mounted) setState(() => _customerSearchResults = const []);
    } finally {
      if (mounted) setState(() => _searchingCustomers = false);
    }
  }

  /// `AbakusMenuCatalog.products` appends the optional, catalog-wide
  /// "Ekstra Sos" cross-sell group to *every* product (see
  /// `abakus_menu_catalog.dart`'s `products` getter) — so checking
  /// `modifierGroups.isEmpty` would open the customization modal for
  /// every single drink too. The actual "is there something worth
  /// configuring" signal is a *required* group (Bowl's carb/salad/pickle,
  /// Burger/Wrap's fries) or a removable-ingredients list; a product with
  /// only the optional sauce cross-sell keeps today's single-tap-add.
  bool _needsCustomization(MenuProduct product) =>
      product.modifierGroups.any((group) => group.isRequired) ||
      product.removableIngredients.isNotEmpty;

  /// A product with nothing worth configuring (drinks, simple sides) is
  /// added directly, one tap, exactly like before. A Bowl/Burger/Wrap-style
  /// product (see [_needsCustomization]) opens
  /// [PosProductCustomizationDialog] first — dismissing it (back button,
  /// tap outside) adds nothing.
  Future<void> _onProductTap(MenuProduct product) async {
    if (!_needsCustomization(product)) {
      _mergeOrAddLine(_StaffEntryCartLine(product: product));
      return;
    }
    final result = await PosProductCustomizationDialog.show(context, product);
    if (result == null || !mounted) return;
    _mergeOrAddLine(
      _StaffEntryCartLine(
        product: product,
        selectedModifiers: result.selectedModifiers,
        excludedIngredients: result.excludedIngredients,
        note: result.note,
      )..quantity = result.quantity,
    );
  }

  /// Merges into an existing line only when both the product *and* its
  /// exact configuration (`_StaffEntryCartLine.customizationKey`) match —
  /// two differently-customized orders of the same dish are always
  /// separate lines, never silently combined.
  void _mergeOrAddLine(_StaffEntryCartLine newLine) {
    setState(() {
      for (final line in _cartLines) {
        if (line.product.id == newLine.product.id &&
            line.customizationKey == newLine.customizationKey) {
          line.quantity += newLine.quantity;
          return;
        }
      }
      _cartLines.add(newLine);
    });
  }

  Future<void> _editLineNote(_StaffEntryCartLine line) async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _LineNoteDialog(initialNote: line.note),
    );
    if (result != null && mounted) setState(() => line.note = result);
  }

  void _incrementLine(_StaffEntryCartLine line) =>
      setState(() => line.quantity++);

  void _decrementLine(_StaffEntryCartLine line) => setState(() {
        if (line.quantity > 1) {
          line.quantity--;
        } else {
          _cartLines.remove(line);
        }
      });

  Map<String, dynamic>? _resolveAccountSelection() {
    if (_useTableGeneral) return {'mode': 'staffGeneral'};
    if (_useWalkIn) {
      final name = _walkInNameController.text.trim();
      if (name.isEmpty) return null;
      return {'mode': 'namedWalkIn', 'displayName': name};
    }
    if (_useExistingCustomer) {
      final customer = _linkedCustomer;
      if (customer == null) return null;
      return {'mode': 'existingCustomer', 'customerId': customer.id};
    }
    final subAccountId = _selectedSubAccountId;
    if (subAccountId != null) {
      return {'mode': 'existingSubAccount', 'subAccountId': subAccountId};
    }
    return null;
  }

  /// Sends the local, not-yet-real cart as one real `submitStaffEntryOrder`
  /// call (`widget.onStaffEntry`, which already wraps `_runAction` — same
  /// success/`null`-on-failure contract documented on the old
  /// `_StaffEntryScreenState._submit`). Only the local cart is cleared
  /// here; the resulting real, accepted order line appears once
  /// `_runAction`'s own `_load()` refreshes `widget.view` on the next
  /// build — never assumed synchronously.
  Future<void> _sendCart() async {
    final selection = _resolveAccountSelection();
    if (selection == null || _cartLines.isEmpty) return;
    setState(() => _sendingCart = true);
    await widget.onStaffEntry(selection, [
      for (final line in _cartLines)
        (
          productId: line.product.id,
          quantity: line.quantity,
          selectedModifiers: line.selectedModifiers,
          excludedIngredients: line.excludedIngredients,
          note: line.note,
        ),
    ]);
    if (!mounted) return;
    setState(() {
      _sendingCart = false;
      _cartLines.clear();
    });
  }

  List<MenuProduct> _productsIn(String categoryId, List<MenuProduct> products) {
    return [
      for (final product in products)
        if (product.categoryId == categoryId) product,
    ];
  }

  Widget _buildCategoryRail(List<MenuCategory> categories,
      List<MenuProduct> allProducts, bool scrollHorizontally) {
    if (scrollHorizontally) {
      final chips = [
        ChoiceChip(
          label: const Text('Çok Tercih Edilenler'),
          selected: _categoryFilter == _staffEntryTopSellersSentinel,
          onSelected: (_) =>
              setState(() => _categoryFilter = _staffEntryTopSellersSentinel),
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
            selected: _categoryFilter == _staffEntryTopSellersSentinel,
            onTap: () =>
                setState(() => _categoryFilter = _staffEntryTopSellersSentinel),
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

  Widget _buildProductSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: TextField(
        key: const Key('productSearchField'),
        controller: _productSearchController,
        onChanged: (value) => setState(() => _productSearchQuery = value),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Ürün ara...',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _productSearchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () => setState(() {
                    _productSearchController.clear();
                    _productSearchQuery = '';
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
        return _StaffEntryProductCard(
          product: product,
          onTap: () => _onProductTap(product),
        );
      },
    );
  }

  int get _pendingApprovalLineCount => [
        for (final order in widget.view.orders)
          for (final line in order.lines)
            if (line.status == 'pendingApproval') line,
      ].length;

  Future<void> _showCancelDialog(
      BuildContext context, String orderId, int lineIndex) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ReasonDialog(
        title: 'Ürünü İptal Et',
        confirmLabel: 'İptal Talebi Gönder',
        reasonCodes: const {
          'customerRequest': 'Müşteri Talebi',
          'kitchenError': 'Mutfak Hatası',
          'other': 'Diğer',
        },
        onSubmit: (reasonCode, reasonMessage) => widget.onCancelRequest(
            orderId, lineIndex, reasonCode, reasonMessage),
      ),
    );
  }

  /// The old always-visible order-review pane, relocated behind a badge
  /// (product owner's explicit choice, 2026-10-31) — reuses [_OrderCard]
  /// unchanged, so accept/reject/propose keep their exact existing
  /// behavior and backend calls.
  void _showPendingApprovalsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        expand: false,
        builder: (sheetContext, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const Text('Onay Bekleyen Siparişler',
                style: AppTypography.titleLarge),
            const SizedBox(height: AppSpacing.md),
            for (final order in widget.view.orders)
              _OrderCard(
                order: order,
                busy: widget.busy,
                onAcceptReject: widget.onAcceptReject,
                onPropose: widget.onPropose,
                onCancelRequest: widget.onCancelRequest,
              ),
          ],
        ),
      ),
    );
  }

  /// Table-level tools — splits (needs an accepted line + a sub-account
  /// to split from, same nested shape the old `_CheckPanel` already
  /// used), headcount-equal split, discount/"Fiyat Düzeltmesi", transfer,
  /// merge. Reuses every existing dialog unchanged; only the entry point
  /// moved from always-visible buttons into this on-demand sheet
  /// (product owner's explicit choice, 2026-10-31).
  void _showQuickToolsSheet(BuildContext context) {
    final view = widget.view;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        expand: false,
        builder: (sheetContext, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const Text('İşlemler', style: AppTypography.titleLarge),
            const SizedBox(height: AppSpacing.md),
            if (view.subAccounts.isNotEmpty) ...[
              const Text('Bölüştürme', style: AppTypography.labelLarge),
              for (final subAccount in view.subAccounts)
                for (final order in view.orders)
                  for (var i = 0; i < order.lines.length; i++)
                    if (order.lines[i].status == 'accepted')
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${order.lines[i].productName} → ${subAccount['displayName']}',
                              style: AppTypography.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Wrap(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.inventory_2_outlined,
                                      size: 18),
                                  tooltip: 'Ürüne Göre Böl',
                                  onPressed: widget.busy
                                      ? null
                                      : () => widget.onSplit(
                                            subAccount['id'] as String,
                                            order.orderId,
                                            i,
                                            'product',
                                          ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.person_outline,
                                      size: 18),
                                  tooltip: 'Kişiye Göre Böl',
                                  onPressed: widget.busy
                                      ? null
                                      : () => widget.onSplit(
                                            subAccount['id'] as String,
                                            order.orderId,
                                            i,
                                            'customer',
                                          ),
                                ),
                                IconButton(
                                  icon:
                                      const Icon(Icons.pin_outlined, size: 18),
                                  tooltip: 'Adete Göre Böl',
                                  onPressed: widget.busy
                                      ? null
                                      : () => _showQuantitySplitDialog(
                                            context,
                                            subAccount['id'] as String,
                                            order.orderId,
                                            i,
                                            order.lines[i].quantity,
                                          ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.payments_outlined,
                                      size: 18),
                                  tooltip: 'Serbest Tutara Göre Böl',
                                  onPressed: widget.busy
                                      ? null
                                      : () => _showFreeAmountSplitDialog(
                                            context,
                                            subAccount['id'] as String,
                                            order.orderId,
                                            i,
                                          ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: widget.busy || view.subAccounts.length < 2
                    ? null
                    : () => _showHeadcountSplitDialog(context, view),
                child: const Text('Eşit Böl (Kişi Sayısına Göre)'),
              ),
              const Divider(),
            ],
            OutlinedButton(
              onPressed: widget.busy || widget.checkId == null
                  ? null
                  : () => _showAdjustmentDialog(context, view, widget.checkId!),
              child: const Text('Fiyat Düzeltmesi Talep Et'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: widget.busy
                  ? null
                  : () => _showTransferDialog(
                      context, widget.onTransfer, 'Masa Transferi'),
              child: const Text('Masa Transfer Et'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: widget.busy
                  ? null
                  : () => _showTransferDialog(
                      context, widget.onMerge, 'Masa Birleştir'),
              child: const Text('Masa Birleştir'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showQuantitySplitDialog(
    BuildContext context,
    String subAccountId,
    String sourceOrderId,
    int sourceLineIndex,
    int maxQuantity,
  ) async {
    var quantity = 1;
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Adete Göre Böl'),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed:
                    quantity > 1 ? () => setState(() => quantity--) : null,
              ),
              Text('$quantity / $maxQuantity'),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: quantity < maxQuantity
                    ? () => setState(() => quantity++)
                    : null,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(quantity),
              child: const Text('Böl'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await widget.onQuantitySplit(
          subAccountId, sourceOrderId, sourceLineIndex, result);
    }
  }

  Future<void> _showFreeAmountSplitDialog(
    BuildContext context,
    String subAccountId,
    String sourceOrderId,
    int sourceLineIndex,
  ) async {
    final controller = TextEditingController();
    final amountText = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Serbest Tutara Göre Böl'),
        content: TextField(
          key: const Key('freeAmountField'),
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Tutar (TL)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Böl'),
          ),
        ],
      ),
    );
    final amountTl = double.tryParse((amountText ?? '').replaceAll(',', '.'));
    if (amountTl != null && amountTl > 0) {
      await widget.onFreeAmountSplit(
        subAccountId,
        sourceOrderId,
        sourceLineIndex,
        (amountTl * 100).round(),
      );
    }
  }

  Future<void> _showHeadcountSplitDialog(
    BuildContext context,
    PosTableOperationalView view,
  ) async {
    final selected = <String>{
      for (final sub in view.subAccounts) sub['id'] as String,
    };
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Kişi Sayısına Göre Eşit Böl'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final sub in view.subAccounts)
                CheckboxListTile(
                  value: selected.contains(sub['id']),
                  title: Text(sub['displayName'] as String? ?? 'Misafir'),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      selected.add(sub['id'] as String);
                    } else {
                      selected.remove(sub['id'] as String);
                    }
                  }),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: selected.length >= 2
                  ? () => Navigator.of(dialogContext).pop(selected.toList())
                  : null,
              child: const Text('Böl'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await widget.onHeadcountSplit(result);
    }
  }

  Future<void> _showAdjustmentDialog(
    BuildContext context,
    PosTableOperationalView view,
    String checkId,
  ) async {
    final activeAllocations =
        view.allocations.where((a) => a.status == 'active').toList();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _AdjustmentDialog(
        view: view,
        activeAllocations: activeAllocations,
        onSubmit: ({
          required scope,
          allocationId,
          subAccountId,
          required adjustmentType,
          percentageBasisPoints,
          fixedAmountMinorUnits,
          required reasonCode,
          required reasonMessage,
        }) =>
            widget.onRequestAdjustment(
          scope: scope,
          allocationId: allocationId,
          subAccountId: subAccountId,
          adjustmentType: adjustmentType,
          percentageBasisPoints: percentageBasisPoints,
          fixedAmountMinorUnits: fixedAmountMinorUnits,
          reasonCode: reasonCode,
          reasonMessage: reasonMessage,
        ),
      ),
    );
  }

  Future<void> _showTransferDialog(
    BuildContext context,
    _TransferMergeFn action,
    String title,
  ) async {
    final controller = TextEditingController();
    final targetTableId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('targetTableIdField'),
          controller: controller,
          decoration: const InputDecoration(labelText: 'Hedef Masa Kimliği'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
    if (targetTableId != null && targetTableId.isNotEmpty) {
      await action(targetTableId);
    }
  }

  /// `requestCheckFinancialAdjustment`'s own real server status
  /// (`open`/`readyForPayment`/`paid`/`cancelled`) — read directly from
  /// [PosTableOperationalView.checks], never independently tracked, same
  /// as the old `_CheckPanel._currentCheckStatus`.
  String? get _currentCheckStatus {
    final checkId = widget.checkId;
    if (checkId == null) return null;
    for (final check in widget.view.checks) {
      if ((check['id'] ?? check['checkId']) == checkId) {
        return check['status'] as String?;
      }
    }
    return null;
  }

  /// One always-prominent bottom button whose label/action is driven by
  /// the real check status — "Hesap Aç" → "Ödemeye Hazırla" → "Ödeme Al"
  /// — the exact same 3-state logic the old `_CheckPanel` already had
  /// (verbatim), just the single visually-dominant action this screen's
  /// "büyük 'Ödeme Al / Hesabı Kapat' butonu" spec asks for.
  Widget _buildPaymentButton() {
    final status = _currentCheckStatus;
    if (widget.checkId == null) {
      return ElevatedButton(
        onPressed: widget.view.hasActiveSession && !widget.busy
            ? widget.onOpenCheck
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size.fromHeight(48),
        ),
        child: const Text('Hesap Aç'),
      );
    }
    if (status == 'readyForPayment' || status == 'paid') {
      return ElevatedButton.icon(
        onPressed: widget.busy ? null : widget.onOpenCheckout,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size.fromHeight(48),
        ),
        icon: const Icon(Icons.point_of_sale_outlined),
        label: Text(status == 'paid' ? 'Ödeme Detayı' : 'Ödeme Al'),
      );
    }
    return ElevatedButton(
      onPressed: widget.busy ? null : widget.onFinalize,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        minimumSize: const Size.fromHeight(48),
      ),
      child: const Text('Ödemeye Hazırla'),
    );
  }

  Widget _buildAccountTargetSelector() {
    // `isExpanded: true` + an explicit `overflow` on every item's `Text` —
    // without both, a long label ("Mevcut Müşteri Ara ve Bağla") overflows
    // this dropdown's fixed width in the narrow cart column instead of
    // eliding, a real render overflow caught by the widget tests.
    return DropdownButtonFormField<String>(
      key: const Key('cartAccountTargetDropdown'),
      initialValue: _accountSelection,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Hesap', isDense: true),
      items: [
        for (final subAccount in widget.view.subAccounts)
          DropdownMenuItem(
            value: subAccount['id'] as String? ?? '',
            child: Text(
              subAccount['displayName'] as String? ?? 'Misafir',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const DropdownMenuItem(
          value: _staffEntryTableGeneralSentinel,
          child: Text('Masa Geneli', overflow: TextOverflow.ellipsis),
        ),
        const DropdownMenuItem(
          value: _staffEntryWalkInSentinel,
          child: Text('Yeni İsimli Misafir', overflow: TextOverflow.ellipsis),
        ),
        const DropdownMenuItem(
          value: _staffEntryExistingCustomerSentinel,
          child: Text('Mevcut Müşteri Ara ve Bağla',
              overflow: TextOverflow.ellipsis),
        ),
      ],
      onChanged: (value) =>
          setState(() => _accountSelection = value ?? _accountSelection),
    );
  }

  Widget _buildAdisyonPanel(BuildContext context) {
    final view = widget.view;
    final pendingCount = _pendingApprovalLineCount;
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Masa · ${view.status}',
                    style: AppTypography.titleMedium
                        .copyWith(fontWeight: FontWeight.bold)),
                if (widget.actionError != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(widget.actionError!,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.error)),
                ],
                const SizedBox(height: AppSpacing.sm),
                _PendingApprovalBanner(
                  organizationId: widget.ctx.organizationId,
                  branchId: widget.ctx.branchId,
                ),
                if (pendingCount > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.rate_review_outlined, size: 18),
                    label: Text('Onay Bekleyen Sipariş: $pendingCount'),
                    onPressed: widget.busy
                        ? null
                        : () => _showPendingApprovalsSheet(context),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: !view.hasActiveSession
                ? const Center(
                    child: Text('Bu masada aktif oturum yok.',
                        style: AppTypography.bodyMedium),
                  )
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      for (final order in view.orders)
                        if (order.lines.any((l) => l.status == 'accepted'))
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: _KitchenStatusBadge(
                                      orderId: order.orderId),
                                ),
                                for (var i = 0; i < order.lines.length; i++)
                                  if (order.lines[i].status == 'accepted')
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: AppSpacing.xs),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${order.lines[i].quantity}x ${order.lines[i].productName}',
                                              style: AppTypography.bodyMedium,
                                            ),
                                          ),
                                          Text(
                                            '${(order.lines[i].unitPriceMinorUnits * order.lines[i].quantity / 100).toStringAsFixed(0)} TL',
                                            style: AppTypography.bodySmall,
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                                Icons.remove_circle_outline,
                                                size: 18,
                                                color: AppColors.error),
                                            tooltip: 'İptal Talebi Gönder',
                                            onPressed: widget.busy
                                                ? null
                                                : () => _showCancelDialog(
                                                    context, order.orderId, i),
                                          ),
                                        ],
                                      ),
                                    ),
                              ],
                            ),
                          ),
                      if (_cartLines.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        const Text('Yeni Eklenenler (Gönderilmedi)',
                            style: AppTypography.labelLarge),
                        for (final line in _cartLines)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(line.product.name,
                                          style: AppTypography.bodyMedium),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.note_add_outlined,
                                          size: 18),
                                      tooltip: line.note.isEmpty
                                          ? 'Not Ekle'
                                          : 'Notu Düzenle',
                                      onPressed: () => _editLineNote(line),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.remove, size: 18),
                                      onPressed: () => _decrementLine(line),
                                    ),
                                    Text('${line.quantity}'),
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 18),
                                      onPressed: () => _incrementLine(line),
                                    ),
                                  ],
                                ),
                                if (line.summaryText.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: AppSpacing.sm),
                                    child: Text(
                                      line.summaryText,
                                      style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_cartLines.isNotEmpty) ...[
                  _buildAccountTargetSelector(),
                  if (_useWalkIn)
                    TextField(
                      key: const Key('walkInNameField'),
                      controller: _walkInNameController,
                      decoration:
                          const InputDecoration(labelText: 'Misafir Adı'),
                      onChanged: (_) => setState(() {}),
                    ),
                  if (_useExistingCustomer) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('customerSearchField'),
                            controller: _customerSearchController,
                            decoration: const InputDecoration(
                                labelText: 'Ad veya Telefon ile Ara'),
                          ),
                        ),
                        IconButton(
                          icon: _searchingCustomers
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.search),
                          onPressed:
                              _searchingCustomers ? null : _searchCustomers,
                        ),
                      ],
                    ),
                    if (_linkedCustomer != null)
                      Text(
                        'Bağlanacak müşteri: ${_linkedCustomer!.displayName}',
                        style: AppTypography.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold),
                      ),
                    for (final result in _customerSearchResults)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(result.displayName),
                        subtitle: Text(result.phoneMasked),
                        onTap: () => setState(() {
                          _linkedCustomer = result;
                          _customerSearchResults = const [];
                        }),
                      ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text('Yeni Ürünler Toplamı',
                            style: AppTypography.labelMedium,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        '${_cartTotal.toStringAsFixed(0)} TL',
                        key: const Key('staffEntryCartTotal'),
                        style: AppTypography.bodyMedium
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ElevatedButton(
                    onPressed:
                        !_sendingCart && _resolveAccountSelection() != null
                            ? _sendCart
                            : null,
                    child: _sendingCart
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Siparişi Mutfağa Gönder'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                OutlinedButton.icon(
                  icon: const Icon(Icons.more_horiz),
                  label: const Text('İşlemler'),
                  onPressed: widget.busy || widget.checkId == null
                      ? null
                      : () => _showQuickToolsSheet(context),
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildPaymentButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(menuCategoriesProvider);
    final allProducts =
        ref.watch(menuProductsProvider).where((p) => p.isAvailable).toList();

    // "Çok Tercih Edilenler" (2026-11-03, BR-POS-001) resolves asynchronously
    // (a real backend aggregation) — every other category is already an
    // in-memory list, wrapped in `AsyncValue.data` so both paths share one
    // explicit loading/error/data handling below instead of two.
    final categoryFilteredAsync = _categoryFilter ==
            _staffEntryTopSellersSentinel
        ? ref.watch(topSellingProductsProvider(widget.ctx)).whenData(
            (topSellers) {
              final productById = {for (final p in allProducts) p.id: p};
              return [
                for (final entry in topSellers)
                  if (productById[entry.productId] != null)
                    productById[entry.productId]!,
              ];
            },
          )
        : AsyncValue.data(
            allProducts.where((p) => p.categoryId == _categoryFilter).toList(),
          );
    final searchQuery = _productSearchQuery.trim().toLowerCase();
    // A non-empty search deliberately searches every product regardless of
    // the selected category/Top-20 filter — finding a specific product by
    // name shouldn't require first guessing which tab it's under, and it
    // never needs to wait on the Top-20 network call either.
    final visibleProductsAsync = searchQuery.isNotEmpty
        ? AsyncValue.data(
            allProducts
                .where((p) => p.name.toLowerCase().contains(searchQuery))
                .toList(),
          )
        : categoryFilteredAsync;

    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth >= AppBreakpoints.tablet;
      final grid = Column(
        children: [
          _buildProductSearchField(),
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
                emptyMessage: _categoryFilter == _staffEntryTopSellersSentinel
                    ? 'Henüz yeterli satış verisi yok.'
                    : 'Bu kategoride ürün yok.',
              ),
            ),
          ),
        ],
      );
      final adisyon = _buildAdisyonPanel(context);
      if (!isWide) {
        return Column(
          children: [
            _buildCategoryRail(categories, allProducts, true),
            Expanded(child: grid),
            Container(height: 1, color: AppColors.border),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: adisyon,
            ),
          ],
        );
      }
      return Row(
        children: [
          _buildCategoryRail(categories, allProducts, false),
          Container(width: 1, color: AppColors.border),
          Expanded(flex: 3, child: grid),
          Container(width: 1, color: AppColors.border),
          SizedBox(width: 340, child: adisyon),
        ],
      );
    });
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.busy,
    required this.onAcceptReject,
    required this.onPropose,
    required this.onCancelRequest,
  });

  final PosTableOrderSummary order;
  final bool busy;
  final _AcceptRejectFn onAcceptReject;
  final _ProposeFn onPropose;
  final _CancelLineFn onCancelRequest;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order.mode == 'staffEntry'
                      ? 'Personel Girişi'
                      : 'Misafir Siparişi',
                  style: AppTypography.labelLarge,
                ),
                _KitchenStatusBadge(orderId: order.orderId),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            for (var i = 0; i < order.lines.length; i++)
              _LineRow(
                line: order.lines[i],
                onAccept: order.lines[i].status == 'pendingApproval' && !busy
                    ? () => onAcceptReject(order.orderId, i, true)
                    : null,
                onReject: order.lines[i].status == 'pendingApproval' && !busy
                    ? () => onAcceptReject(order.orderId, i, false)
                    : null,
                onPropose: order.lines[i].status == 'pendingApproval' && !busy
                    ? () =>
                        _showProposeDialog(context, order.orderId, i, onPropose)
                    : null,
                onCancelRequest: order.lines[i].status == 'accepted' && !busy
                    ? () => _showCancelDialog(
                        context, order.orderId, i, onCancelRequest)
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProposeDialog(
    BuildContext context,
    String orderId,
    int lineIndex,
    _ProposeFn onPropose,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ProposeReplacementDialog(
        onSubmit: (productId, quantity, reasonCode, reasonMessage) => onPropose(
            orderId, lineIndex, productId, quantity, reasonCode, reasonMessage),
      ),
    );
  }

  Future<void> _showCancelDialog(
    BuildContext context,
    String orderId,
    int lineIndex,
    _CancelLineFn onCancelRequest,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ReasonDialog(
        title: 'Ürünü İptal Et',
        confirmLabel: 'İptal Talebi Gönder',
        reasonCodes: const {
          'customerRequest': 'Müşteri Talebi',
          'kitchenError': 'Mutfak Hatası',
          'other': 'Diğer',
        },
        onSubmit: (reasonCode, reasonMessage) =>
            onCancelRequest(orderId, lineIndex, reasonCode, reasonMessage),
      ),
    );
  }
}

/// A small reusable reason-code + free-text dialog — backs both the
/// accepted-line cancellation request and (via its own instance) the
/// financial-adjustment request, mirroring `remoteApproval.ts`'s uniform
/// "reasonCode + reasonMessage" shape across every remote-approval-gated
/// action.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.confirmLabel,
    required this.reasonCodes,
    required this.onSubmit,
  });

  final String title;
  final String confirmLabel;
  final Map<String, String> reasonCodes;
  final Future<void> Function(String reasonCode, String reasonMessage) onSubmit;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late String _reasonCode = widget.reasonCodes.keys.first;
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.kLarge),
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('reasonCodeDropdown'),
            initialValue: _reasonCode,
            decoration: const InputDecoration(labelText: 'Neden'),
            items: [
              for (final entry in widget.reasonCodes.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) =>
                setState(() => _reasonCode = value ?? _reasonCode),
          ),
          TextField(
            key: const Key('reasonMessageField'),
            controller: _messageController,
            decoration: const InputDecoration(labelText: 'Açıklama'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          onPressed: () async {
            final message = _messageController.text.trim();
            if (message.isEmpty) return;
            final navigator = Navigator.of(context);
            await widget.onSubmit(_reasonCode, message);
            navigator.pop();
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    this.onAccept,
    this.onReject,
    this.onPropose,
    this.onCancelRequest,
  });

  final PosOrderLineSummary line;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onPropose;
  final VoidCallback? onCancelRequest;

  Color get _statusColor => switch (line.status) {
        'pendingApproval' => AppColors.warning,
        'accepted' => AppColors.primary,
        'rejected' => AppColors.error,
        'proposedChange' => AppColors.accent,
        _ => AppColors.textSecondary,
      };

  String get _statusLabel => switch (line.status) {
        'pendingApproval' => 'Onay bekliyor',
        'accepted' => 'Kabul edildi',
        'rejected' => 'Reddedildi',
        'proposedChange' => 'Değişiklik önerildi',
        _ => line.status,
      };

  @override
  Widget build(BuildContext context) {
    final hasActions = onAccept != null ||
        onReject != null ||
        onPropose != null ||
        onCancelRequest != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${line.quantity}x ${line.productName}',
                    style: AppTypography.bodyMedium),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: AppRadius.kPill,
                ),
                child: Text(
                  _statusLabel,
                  style: AppTypography.bodySmall.copyWith(
                      color: _statusColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          // A narrow phone screen doesn't have room for up to four
          // IconButtons on the same row as the product name/status pill
          // (AP-3 physical-device finding — squeezed the name down to a
          // character-per-line wrap). A `Wrap` lets them flow onto their
          // own line instead, unlike the previous `Row`, which never
          // shrank them.
          if (hasActions)
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                if (onAccept != null)
                  IconButton(
                    icon: const Icon(Icons.check_circle_outline,
                        color: AppColors.primary),
                    tooltip: 'Kabul Et',
                    onPressed: onAccept,
                  ),
                if (onReject != null)
                  IconButton(
                    icon: const Icon(Icons.cancel_outlined,
                        color: AppColors.error),
                    tooltip: 'Reddet',
                    onPressed: onReject,
                  ),
                if (onPropose != null)
                  IconButton(
                    icon: const Icon(Icons.swap_horiz_rounded,
                        color: AppColors.accent),
                    tooltip: 'Değişiklik Öner',
                    onPressed: onPropose,
                  ),
                if (onCancelRequest != null)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: AppColors.error),
                    tooltip: 'İptal Talebi Gönder',
                    onPressed: onCancelRequest,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

const _staffEntryTableGeneralSentinel = '__table_general__';
const _staffEntryWalkInSentinel = '__named_walk_in__';
const _staffEntryExistingCustomerSentinel = '__existing_customer__';

/// 2026-11-03 — product owner, BR-POS-001: replaces the old "Tümü" (show
/// every category) default with "Çok Tercih Edilenler" (Top 20
/// best-sellers). The identifier keeps its old name's shape deliberately
/// unrenamed in call sites that were already using it as "the default
/// selection," but its *meaning* changed — see `topSellingProductsProvider`.
const _staffEntryTopSellersSentinel = '__top_sellers__';

/// The quick note-edit popup for a pending cart line. A dedicated
/// `StatefulWidget` (rather than a `TextEditingController` created and
/// disposed inline around `showDialog`) so the controller's lifetime is
/// tied to this widget's own `State` — disposed when Flutter actually
/// unmounts it (after the dialog's exit transition finishes), not
/// synchronously the instant `Navigator.pop` returns, which raced the
/// still-animating-out route and threw "a TextEditingController was used
/// after being disposed".
class _LineNoteDialog extends StatefulWidget {
  const _LineNoteDialog({required this.initialNote});

  final String initialNote;

  @override
  State<_LineNoteDialog> createState() => _LineNoteDialogState();
}

class _LineNoteDialogState extends State<_LineNoteDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.kLarge),
      title: const Text('Sipariş Notu'),
      content: TextField(
        key: const Key('lineNoteField'),
        controller: _controller,
        maxLength: 200,
        maxLines: 3,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Not ekleyin...'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

/// One accumulated line in the cart being built — mutable [quantity] only
/// (never a second [MenuProduct] for the same [product.id]; re-tapping a
/// card increments the existing line instead, see `_StaffEntryScreenState
/// ._addToCart`).
class _StaffEntryCartLine {
  _StaffEntryCartLine({
    required this.product,
    this.selectedModifiers = const [],
    this.excludedIngredients = const [],
    this.note = '',
  });

  final MenuProduct product;
  final List<SelectedModifier> selectedModifiers;
  final List<String> excludedIngredients;
  String note;
  int quantity = 1;

  double get unitPrice =>
      product.basePrice +
      selectedModifiers.fold(0.0, (sum, m) => sum + m.extraPrice);

  double get totalRowPrice => unitPrice * quantity;

  /// Distinguishes configurations of the same product, so two differently
  /// customized orders never silently merge quantities — see
  /// `_PosWorkbenchState._mergeOrAddLine`. Two lines with the same product
  /// and an empty, unconfigured cart line (no modifiers, no exclusions, no
  /// note) share the same key, matching the old merge-by-product-id-only
  /// behavior for products with no `ModifierGroup`s.
  String get customizationKey {
    final modifierIds = [for (final m in selectedModifiers) m.optionId]..sort();
    final excluded = List<String>.from(excludedIngredients)..sort();
    return '${modifierIds.join(',')}|${excluded.join(',')}|$note';
  }

  /// "Basmati, +Avokado, Çıkar: Mısır / Not: Sosu ayrı olsun" — the
  /// human-readable summary shown under this line in the pending-cart
  /// list. Empty when the line has no customization at all.
  String get summaryText {
    final parts = <String>[
      for (final m in selectedModifiers)
        m.extraPrice > 0 ? '+${m.optionName}' : m.optionName,
      for (final ingredient in excludedIngredients) 'Çıkar: $ingredient',
      if (note.isNotEmpty) 'Not: $note',
    ];
    return parts.join(' / ');
  }
}

/// Vertical category-rail card (2026-11-02 touch-POS redesign) — a small
/// rounded preview image on top, the category name below, with a
/// highlighted border/background when selected. Deliberately has no
/// dedicated category-icon asset convention: the preview is the
/// category's own products' real photos via [ProductImage], tried in
/// order via [previewImageKeys] (so a product with no working photo
/// falls through to the next product's, rather than dropping straight to
/// the generic placeholder) — empty only for the synthetic "Tümü" entry
/// or a category with no products, in which case [icon] is shown
/// instead.
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

/// A single tappable product tile in the staff order-entry grid — a real
/// photo via [ProductImage] (resolved from [MenuProduct.imageKey], with
/// its own built-in placeholder for a product that has none), name, and
/// price. Deliberately no quantity control on the card itself — tapping
/// adds one unit to the cart; the cart panel is where quantity is
/// adjusted, matching the "tap to add, adjust in the cart" convention a
/// touch POS grid is expected to have.
class _StaffEntryProductCard extends StatelessWidget {
  const _StaffEntryProductCard({required this.product, required this.onTap});
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
                child: ProductImage(
                  imageKey: product.imageKey,
                  categoryId: product.categoryId,
                  width: double.infinity,
                  height: double.infinity,
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

class _ProposeReplacementDialog extends StatefulWidget {
  const _ProposeReplacementDialog({required this.onSubmit});
  final Future<void> Function(String productId, int quantity, String reasonCode,
      String reasonMessage) onSubmit;

  @override
  State<_ProposeReplacementDialog> createState() =>
      _ProposeReplacementDialogState();
}

class _ProposeReplacementDialogState extends State<_ProposeReplacementDialog> {
  MenuProduct? _selectedProduct;
  final int _quantity = 1;
  String _reasonCode = 'outOfStock';
  final _reasonMessageController = TextEditingController();

  @override
  void dispose() {
    _reasonMessageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final products = ref.watch(menuProductsProvider);
      return AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.kLarge),
        title: const Text('Değişiklik Öner'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<MenuProduct>(
              key: const Key('proposeProductDropdown'),
              initialValue: _selectedProduct,
              decoration: const InputDecoration(labelText: 'Önerilen Ürün'),
              items: [
                for (final product in products)
                  DropdownMenuItem(value: product, child: Text(product.name)),
              ],
              onChanged: (value) => setState(() => _selectedProduct = value),
            ),
            DropdownButtonFormField<String>(
              initialValue: _reasonCode,
              decoration: const InputDecoration(labelText: 'Neden'),
              items: const [
                DropdownMenuItem(
                    value: 'outOfStock', child: Text('Stokta Yok')),
                DropdownMenuItem(
                    value: 'substitution', child: Text('Muadil Ürün')),
              ],
              onChanged: (value) =>
                  setState(() => _reasonCode = value ?? _reasonCode),
            ),
            TextField(
              key: const Key('proposeReasonMessageField'),
              controller: _reasonMessageController,
              decoration: const InputDecoration(labelText: 'Açıklama'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () {
              final product = _selectedProduct;
              final message = _reasonMessageController.text.trim();
              if (product == null || message.isEmpty) return;
              widget.onSubmit(product.id, _quantity, _reasonCode, message);
              Navigator.of(context).pop();
            },
            child: const Text('Öner'),
          ),
        ],
      );
    });
  }
}

typedef _SplitFn = Future<void> Function(String subAccountId,
    String sourceOrderId, int sourceLineIndex, String mode);
typedef _QuantitySplitFn = Future<void> Function(String subAccountId,
    String sourceOrderId, int sourceLineIndex, int quantity);
typedef _FreeAmountSplitFn = Future<void> Function(String subAccountId,
    String sourceOrderId, int sourceLineIndex, int amountMinorUnits);
typedef _HeadcountSplitFn = Future<void> Function(List<String> subAccountIds);
typedef _TransferMergeFn = Future<void> Function(String targetTableId);
typedef _AdjustmentFn = Future<void> Function({
  required String scope,
  String? allocationId,
  String? subAccountId,
  required String adjustmentType,
  int? percentageBasisPoints,
  int? fixedAmountMinorUnits,
  required String reasonCode,
  required String reasonMessage,
});

typedef _AdjustmentSubmitFn = Future<void> Function({
  required String scope,
  String? allocationId,
  String? subAccountId,
  required String adjustmentType,
  int? percentageBasisPoints,
  int? fixedAmountMinorUnits,
  required String reasonCode,
  required String reasonMessage,
});

/// `requestCheckFinancialAdjustment` (`functions/src
/// /checkFinancialAdjustments.ts`) request-side dialog — scope (whole
/// check / one active split allocation / one sub-account), adjustment
/// type (complimentary / percentage / fixed amount), and a mandatory
/// reason. The actual applied amount is never computed client-side — the
/// backend recomputes it fresh, live, once a manager approves.
class _AdjustmentDialog extends StatefulWidget {
  const _AdjustmentDialog({
    required this.view,
    required this.activeAllocations,
    required this.onSubmit,
  });

  final PosTableOperationalView view;
  final List<PosCheckAllocationSummary> activeAllocations;
  final _AdjustmentSubmitFn onSubmit;

  @override
  State<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<_AdjustmentDialog> {
  String _scope = 'check';
  String? _allocationId;
  String? _subAccountId;
  String _adjustmentType = 'complimentary';
  final _percentageController = TextEditingController(text: '10');
  final _fixedAmountController = TextEditingController();
  String _reasonCode = 'customerSatisfaction';
  final _reasonMessageController = TextEditingController();

  @override
  void dispose() {
    _percentageController.dispose();
    _fixedAmountController.dispose();
    _reasonMessageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.kLarge),
      title: const Text('Fiyat Düzeltmesi Talep Et'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Kapsam', style: AppTypography.labelLarge),
            RadioGroup<String>(
              groupValue: _scope,
              onChanged: (value) => setState(() {
                _scope = value ?? _scope;
                _allocationId = null;
                _subAccountId = null;
              }),
              child: const Column(
                children: [
                  RadioListTile<String>(
                    value: 'check',
                    title: Text('Tüm Hesap'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    value: 'product',
                    title: Text('Belirli Bir Ürün'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    value: 'subAccount',
                    title: Text('Belirli Bir Müşteri'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            if (_scope == 'product')
              DropdownButtonFormField<String>(
                key: const Key('adjustmentAllocationDropdown'),
                initialValue: _allocationId,
                decoration: const InputDecoration(labelText: 'Bölüşüm'),
                items: [
                  for (final allocation in widget.activeAllocations)
                    DropdownMenuItem(
                      value: allocation.id,
                      child: Text(
                        '${allocation.subAccountId} · ${(allocation.allocatedAmountMinorUnits / 100).toStringAsFixed(2)} TL',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _allocationId = value),
              ),
            if (_scope == 'subAccount')
              DropdownButtonFormField<String>(
                key: const Key('adjustmentSubAccountDropdown'),
                initialValue: _subAccountId,
                decoration: const InputDecoration(labelText: 'Müşteri'),
                items: [
                  for (final sub in widget.view.subAccounts)
                    DropdownMenuItem(
                      value: sub['id'] as String,
                      child: Text(sub['displayName'] as String? ?? 'Misafir'),
                    ),
                ],
                onChanged: (value) => setState(() => _subAccountId = value),
              ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Düzeltme Türü', style: AppTypography.labelLarge),
            RadioGroup<String>(
              groupValue: _adjustmentType,
              onChanged: (value) =>
                  setState(() => _adjustmentType = value ?? _adjustmentType),
              child: const Column(
                children: [
                  RadioListTile<String>(
                    value: 'complimentary',
                    title: Text('İkram (Tamamı)'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    value: 'percentage',
                    title: Text('Yüzde İndirim'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    value: 'fixedAmount',
                    title: Text('Sabit Tutar İndirim'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            if (_adjustmentType == 'percentage')
              TextField(
                key: const Key('adjustmentPercentageField'),
                controller: _percentageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Yüzde (%)'),
              ),
            if (_adjustmentType == 'fixedAmount')
              TextField(
                key: const Key('adjustmentFixedAmountField'),
                controller: _fixedAmountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Tutar (TL)'),
              ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _reasonCode,
              decoration: const InputDecoration(labelText: 'Neden'),
              items: const [
                DropdownMenuItem(
                    value: 'customerSatisfaction',
                    child: Text('Müşteri Memnuniyeti')),
                DropdownMenuItem(
                    value: 'serviceError', child: Text('Servis Hatası')),
                DropdownMenuItem(value: 'other', child: Text('Diğer')),
              ],
              onChanged: (value) =>
                  setState(() => _reasonCode = value ?? _reasonCode),
            ),
            TextField(
              key: const Key('adjustmentReasonMessageField'),
              controller: _reasonMessageController,
              decoration: const InputDecoration(labelText: 'Açıklama'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          onPressed: () async {
            final message = _reasonMessageController.text.trim();
            if (message.isEmpty) return;
            if (_scope == 'product' && _allocationId == null) return;
            if (_scope == 'subAccount' && _subAccountId == null) return;
            int? percentageBasisPoints;
            int? fixedAmountMinorUnits;
            if (_adjustmentType == 'percentage') {
              final percent =
                  double.tryParse(_percentageController.text.trim());
              if (percent == null || percent <= 0 || percent > 100) return;
              percentageBasisPoints = (percent * 100).round();
            } else if (_adjustmentType == 'fixedAmount') {
              final amount = double.tryParse(
                  _fixedAmountController.text.trim().replaceAll(',', '.'));
              if (amount == null || amount <= 0) return;
              fixedAmountMinorUnits = (amount * 100).round();
            }
            final navigator = Navigator.of(context);
            await widget.onSubmit(
              scope: _scope,
              allocationId: _allocationId,
              subAccountId: _subAccountId,
              adjustmentType: _adjustmentType,
              percentageBasisPoints: percentageBasisPoints,
              fixedAmountMinorUnits: fixedAmountMinorUnits,
              reasonCode: _reasonCode,
              reasonMessage: message,
            );
            navigator.pop();
          },
          child: const Text('Talep Gönder'),
        ),
      ],
    );
  }
}

/// A compact, requester-side live remote-approval indicator — reuses the
/// same [ApprovalRepository]/[ApprovalRequest] model the Admin Approval
/// Inbox (`approval_inbox_screen.dart`) already uses, rather than a
/// parallel read path. Shows nothing when there is no active staff
/// session or no pending request at this branch; tapping it opens the
/// real inbox (requester AND eligible-responder tabs), never a
/// POS-local duplicate of that screen.
class _PendingApprovalBanner extends ConsumerWidget {
  const _PendingApprovalBanner({
    required this.organizationId,
    required this.branchId,
  });

  final String organizationId;
  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(actorSessionProvider);
    final actorUid = session?.actorId;
    if (actorUid == null) return const SizedBox.shrink();
    final requestsAsync = ref.watch(_myPendingApprovalsProvider(actorUid));
    return requestsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (requests) {
        final pendingHere = requests
            .where((r) =>
                r.status == ApprovalStatus.pending &&
                r.organizationId == organizationId &&
                r.branchId == branchId)
            .length;
        if (pendingHere == 0) return const SizedBox.shrink();
        return OutlinedButton.icon(
          icon: const Icon(Icons.hourglass_top_outlined, size: 18),
          label: Text('$pendingHere onay bekleyen talebim var'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ApprovalInboxScreen()),
          ),
        );
      },
    );
  }
}

final _myPendingApprovalsProvider =
    StreamProvider.family<List<ApprovalRequest>, String>((ref, actorUid) {
  return ref
      .watch(approvalRepositoryProvider)
      .watchMyRequests(actorUid: actorUid);
});

/// A live, order-level kitchen-readiness badge — `"3/5 hazır"`/`"Hazır"` —
/// so staff can see prep status without walking to the physical KDS
/// screen. Order-level only, deliberately not per-line: `PosOrderLineSummary`
/// has no stable per-line id (ADR-013), while `KitchenTicketLine`/
/// `KitchenWorkItem` ids are derived from the fired ticket's line index —
/// a per-line badge could show the wrong line's status after a split/
/// propose-replacement reorders `order.lines`. Renders nothing while
/// loading, on error, or before any kitchen ticket exists for this order
/// (a normal state, not an error) — mirrors `_PendingApprovalBanner`'s
/// exact "only this sliver rebuilds on stream emission" isolation.
class _KitchenStatusBadge extends ConsumerWidget {
  const _KitchenStatusBadge({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewAsync = ref.watch(kdsOrderStatusProvider(orderId));
    return viewAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (view) {
        if (view == null || view.lines.isEmpty) {
          return const SizedBox.shrink();
        }
        final ready = view.lines.where((l) => l.isFullyReady).length;
        final total = view.lines.length;
        final color = view.isFullyReady ? AppColors.success : AppColors.info;
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: AppRadius.kPill,
          ),
          child: Text(
            view.isFullyReady ? 'Hazır' : '$ready/$total hazır',
            style: AppTypography.labelMedium.copyWith(color: color),
          ),
        );
      },
    );
  }
}
