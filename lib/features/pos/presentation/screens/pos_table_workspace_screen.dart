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
import '../../../admin/data/tenant_customer_directory_gateway.dart';
import '../../../admin/domain/approval/approval_request.dart';
import '../../../admin/presentation/providers/admin_dependencies_provider.dart';
import '../../../admin/presentation/screens/approval_inbox_screen.dart';
import '../../../admin/presentation/screens/trusted_device_status_screen.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../menu/presentation/providers/menu_catalog_provider.dart';
import '../../data/pos_action_gateway.dart';
import '../../data/pos_operational_view_gateway.dart';
import '../providers/actor_session_provider.dart';
import '../providers/pos_workspace_providers.dart';
import '../widgets/pos_operational_rail.dart';
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

    final centerPane = _CenterPane(
      organizationId: ctx.organizationId,
      view: view,
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
      onStaffEntry: (subAccountSelection, productId, quantity) => _runAction(
        () => ref.read(posActionGatewayProvider).submitStaffEntryOrder(
          ctx: ctx,
          tableId: tableId,
          subAccountSelection: subAccountSelection,
          items: [
            {
              'kind': 'product',
              'productId': productId,
              'quantity': quantity,
              'selectedModifiers': <Map<String, String>>[],
              'note': '',
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
    );

    final checkPanel = _CheckPanel(
      ctx: ctx,
      view: view,
      checkId: _openedCheckId,
      busy: _busy,
      actionError: _actionError,
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

    // Phone-width devices (AP-3 physical-device finding): the canonical
    // side-by-side 3:2 split assumes POS-hardware/tablet width and produces
    // unreadably narrow columns (character-per-line text wrap) below
    // [AppBreakpoints.tablet] — stack the two panes instead, each full-width
    // and independently scrollable. Tablet/desktop/POS-hardware keeps the
    // original side-by-side layout unchanged.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppBreakpoints.tablet) {
          return Column(
            children: [
              Expanded(child: centerPane),
              Container(height: 1, color: AppColors.border),
              Expanded(child: checkPanel),
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 3, child: centerPane),
            Container(width: 1, color: AppColors.border),
            Expanded(flex: 2, child: checkPanel),
          ],
        );
      },
    );
  }
}

typedef _AcceptRejectFn = Future<void> Function(
    String orderId, int lineIndex, bool accept);
typedef _ProposeFn = Future<void> Function(String orderId, int lineIndex,
    String productId, int quantity, String reasonCode, String reasonMessage);
typedef _StaffEntryFn = Future<String?> Function(
    Map<String, dynamic> subAccountSelection, String productId, int quantity);
typedef _CancelLineFn = Future<void> Function(
    String orderId, int lineIndex, String reasonCode, String reasonMessage);

const _subAccountFilterAllSentinel = '__all__';

class _CenterPane extends StatefulWidget {
  const _CenterPane({
    required this.organizationId,
    required this.view,
    required this.busy,
    required this.actionError,
    required this.onAcceptReject,
    required this.onPropose,
    required this.onStaffEntry,
    required this.onCancelRequest,
  });

  final String organizationId;
  final PosTableOperationalView view;
  final bool busy;
  final String? actionError;
  final _AcceptRejectFn onAcceptReject;
  final _ProposeFn onPropose;
  final _StaffEntryFn onStaffEntry;
  final _CancelLineFn onCancelRequest;

  @override
  State<_CenterPane> createState() => _CenterPaneState();
}

class _CenterPaneState extends State<_CenterPane> {
  String _filterSubAccountId = _subAccountFilterAllSentinel;

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final filteredOrders = _filterSubAccountId == _subAccountFilterAllSentinel
        ? view.orders
        : [
            for (final order in view.orders)
              if (order.subAccountId == _filterSubAccountId) order,
          ];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          'Masa · ${view.status}',
          style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
        ),
        if (widget.actionError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(widget.actionError!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
        ],
        const SizedBox(height: AppSpacing.md),
        if (!view.hasActiveSession)
          const Text('Bu masada aktif oturum yok.',
              style: AppTypography.bodyMedium)
        else ...[
          if (view.subAccounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: DropdownButtonFormField<String>(
                key: const Key('subAccountFilterDropdown'),
                initialValue: _filterSubAccountId,
                decoration:
                    const InputDecoration(labelText: 'Hesaba Göre Filtrele'),
                items: [
                  const DropdownMenuItem(
                    value: _subAccountFilterAllSentinel,
                    child: Text('Tümü'),
                  ),
                  for (final sub in view.subAccounts)
                    DropdownMenuItem(
                      value: sub['id'] as String,
                      child: Text(sub['displayName'] as String? ?? 'Misafir'),
                    ),
                ],
                onChanged: (value) => setState(() => _filterSubAccountId =
                    value ?? _subAccountFilterAllSentinel),
              ),
            ),
          for (final order in filteredOrders)
            _OrderCard(
              order: order,
              busy: widget.busy,
              onAcceptReject: widget.onAcceptReject,
              onPropose: widget.onPropose,
              onCancelRequest: widget.onCancelRequest,
            ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: widget.busy
                ? null
                : () => _showStaffEntryDialog(
                    context, widget.organizationId, view, widget.onStaffEntry),
            icon: const Icon(Icons.add_shopping_cart_outlined),
            label: const Text('Ürün Ekle (Personel)'),
          ),
        ],
      ],
    );
  }

  Future<void> _showStaffEntryDialog(
    BuildContext context,
    String organizationId,
    PosTableOperationalView view,
    _StaffEntryFn onStaffEntry,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _StaffEntryDialog(
        organizationId: organizationId,
        view: view,
        onSubmit: onStaffEntry,
      ),
    );
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
            Text(
              order.mode == 'staffEntry'
                  ? 'Personel Girişi'
                  : 'Misafir Siparişi',
              style: AppTypography.labelLarge,
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

class _StaffEntryDialog extends StatefulWidget {
  const _StaffEntryDialog({
    required this.organizationId,
    required this.view,
    required this.onSubmit,
  });
  final String organizationId;
  final PosTableOperationalView view;
  final _StaffEntryFn onSubmit;

  @override
  State<_StaffEntryDialog> createState() => _StaffEntryDialogState();
}

const _staffEntryTableGeneralSentinel = '__table_general__';
const _staffEntryWalkInSentinel = '__named_walk_in__';
const _staffEntryExistingCustomerSentinel = '__existing_customer__';

class _StaffEntryDialogState extends State<_StaffEntryDialog> {
  String? _selection;
  final _walkInNameController = TextEditingController();
  final _customerSearchController = TextEditingController();
  MenuProduct? _selectedProduct;
  int _quantity = 1;
  List<TenantCustomerSearchResult> _customerSearchResults = const [];
  bool _searchingCustomers = false;
  TenantCustomerSearchResult? _linkedCustomer;

  bool get _useWalkIn => _selection == _staffEntryWalkInSentinel;
  bool get _useTableGeneral => _selection == _staffEntryTableGeneralSentinel;
  bool get _useExistingCustomer =>
      _selection == _staffEntryExistingCustomerSentinel;
  String? get _selectedSubAccountId => (_selection != null &&
          !_useWalkIn &&
          !_useTableGeneral &&
          !_useExistingCustomer)
      ? _selection
      : null;

  @override
  void dispose() {
    _walkInNameController.dispose();
    _customerSearchController.dispose();
    super.dispose();
  }

  static final _phoneLikeQuery = RegExp(r'^[+\d][\d\s]*$');

  Future<void> _searchCustomers(WidgetRef ref) async {
    final query = _customerSearchController.text.trim();
    if (query.isEmpty) return;
    final isPhoneLike = _phoneLikeQuery.hasMatch(query);
    setState(() => _searchingCustomers = true);
    try {
      final results =
          await ref.read(tenantCustomerDirectoryGatewayProvider).search(
                organizationId: widget.organizationId,
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

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final products = ref.watch(menuProductsProvider);
      return AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.kLarge),
        title: const Text('Personel Ürün Girişi'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Hesap', style: AppTypography.labelLarge),
              RadioGroup<String>(
                groupValue: _selection,
                onChanged: (value) => setState(() => _selection = value),
                child: Column(
                  children: [
                    for (final subAccount in widget.view.subAccounts)
                      RadioListTile<String>(
                        value: subAccount['id'] as String? ?? '',
                        title: Text(
                            subAccount['displayName'] as String? ?? 'Misafir'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    const RadioListTile<String>(
                      value: _staffEntryTableGeneralSentinel,
                      title: Text('Masa Geneli'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const RadioListTile<String>(
                      value: _staffEntryWalkInSentinel,
                      title: Text('Yeni İsimli Misafir'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const RadioListTile<String>(
                      value: _staffEntryExistingCustomerSentinel,
                      title: Text('Mevcut Müşteri Ara ve Bağla'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              if (_useWalkIn)
                TextField(
                  key: const Key('walkInNameField'),
                  controller: _walkInNameController,
                  decoration: const InputDecoration(labelText: 'Misafir Adı'),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      onPressed: _searchingCustomers
                          ? null
                          : () => _searchCustomers(ref),
                    ),
                  ],
                ),
                if (_linkedCustomer != null)
                  Text(
                    'Bağlanacak müşteri: ${_linkedCustomer!.displayName} '
                    '(${_linkedCustomer!.phoneMasked})',
                    style: AppTypography.bodySmall.copyWith(
                        color: AppColors.primary, fontWeight: FontWeight.bold),
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
              const Text('Ürün', style: AppTypography.labelLarge),
              DropdownButtonFormField<MenuProduct>(
                key: const Key('staffEntryProductDropdown'),
                initialValue: _selectedProduct,
                items: [
                  for (final product in products)
                    DropdownMenuItem(value: product, child: Text(product.name)),
                ],
                onChanged: (value) => setState(() => _selectedProduct = value),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: _quantity > 1
                        ? () => setState(() => _quantity--)
                        : null,
                  ),
                  Text('$_quantity'),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => setState(() => _quantity++),
                  ),
                ],
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
            onPressed: () {
              final product = _selectedProduct;
              if (product == null) return;
              Map<String, dynamic> selection;
              if (_useTableGeneral) {
                selection = {'mode': 'staffGeneral'};
              } else if (_useWalkIn) {
                final name = _walkInNameController.text.trim();
                if (name.isEmpty) return;
                selection = {'mode': 'namedWalkIn', 'displayName': name};
              } else if (_useExistingCustomer) {
                final customer = _linkedCustomer;
                if (customer == null) return;
                selection = {
                  'mode': 'existingCustomer',
                  'customerId': customer.id
                };
              } else if (_selectedSubAccountId != null) {
                selection = {
                  'mode': 'existingSubAccount',
                  'subAccountId': _selectedSubAccountId,
                };
              } else {
                return;
              }
              widget.onSubmit(selection, product.id, _quantity);
              Navigator.of(context).pop();
            },
            child: const Text('Ekle'),
          ),
        ],
      );
    });
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

class _CheckPanel extends StatelessWidget {
  const _CheckPanel({
    required this.ctx,
    required this.view,
    required this.checkId,
    required this.busy,
    required this.actionError,
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

  /// The open check's own real server status (`open`/`readyForPayment`/
  /// `paid`/`cancelled`) — AP-4 Wave D. Read directly from [view].checks,
  /// never independently tracked, so it can never drift from what
  /// `finalizeCheckReadyForPayment`/the payment engine actually did.
  String? get _currentCheckStatus {
    if (checkId == null) return null;
    for (final check in view.checks) {
      if ((check['id'] ?? check['checkId']) == checkId) {
        return check['status'] as String?;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ListView(
        children: [
          Text('Hesap',
              style: AppTypography.titleMedium
                  .copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.sm),
          _PendingApprovalBanner(
              organizationId: ctx.organizationId, branchId: ctx.branchId),
          const SizedBox(height: AppSpacing.sm),
          if (checkId == null)
            ElevatedButton(
              onPressed: view.hasActiveSession && !busy ? onOpenCheck : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
              ),
              child: const Text('Hesap Aç'),
            )
          else ...[
            Text('Hesap No: $checkId', style: AppTypography.bodySmall),
            const SizedBox(height: AppSpacing.md),
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
                                onPressed: busy
                                    ? null
                                    : () => onSplit(
                                          subAccount['id'] as String,
                                          order.orderId,
                                          i,
                                          'product',
                                        ),
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.person_outline, size: 18),
                                tooltip: 'Kişiye Göre Böl',
                                onPressed: busy
                                    ? null
                                    : () => onSplit(
                                          subAccount['id'] as String,
                                          order.orderId,
                                          i,
                                          'customer',
                                        ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.pin_outlined, size: 18),
                                tooltip: 'Adete Göre Böl',
                                onPressed: busy
                                    ? null
                                    : () => _showQuantitySplitDialog(
                                          context,
                                          subAccount['id'] as String,
                                          order.orderId,
                                          i,
                                          order.lines[i].quantity,
                                          onQuantitySplit,
                                        ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.payments_outlined,
                                    size: 18),
                                tooltip: 'Serbest Tutara Göre Böl',
                                onPressed: busy
                                    ? null
                                    : () => _showFreeAmountSplitDialog(
                                          context,
                                          subAccount['id'] as String,
                                          order.orderId,
                                          i,
                                          onFreeAmountSplit,
                                        ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: busy || view.subAccounts.length < 2
                  ? null
                  : () => _showHeadcountSplitDialog(
                      context, view, onHeadcountSplit),
              child: const Text('Eşit Böl (Kişi Sayısına Göre)'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => _showAdjustmentDialog(
                      context, view, checkId!, onRequestAdjustment),
              child: const Text('Fiyat Düzeltmesi Talep Et'),
            ),
            const Divider(),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => _showTransferDialog(
                      context, onTransfer, 'Masa Transferi'),
              child: const Text('Masa Transfer Et'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () =>
                      _showTransferDialog(context, onMerge, 'Masa Birleştir'),
              child: const Text('Masa Birleştir'),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_currentCheckStatus == 'readyForPayment' ||
                _currentCheckStatus == 'paid')
              ElevatedButton.icon(
                onPressed: busy ? null : onOpenCheckout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                ),
                icon: const Icon(Icons.point_of_sale_outlined),
                label: Text(_currentCheckStatus == 'paid'
                    ? 'Ödeme Detayı'
                    : 'Ödemeye Git'),
              )
            else
              ElevatedButton(
                onPressed: busy ? null : onFinalize,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                ),
                child: const Text('Ödemeye Hazır'),
              ),
          ],
          if (actionError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(actionError!,
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.error)),
          ],
        ],
      ),
    );
  }

  Future<void> _showQuantitySplitDialog(
    BuildContext context,
    String subAccountId,
    String sourceOrderId,
    int sourceLineIndex,
    int maxQuantity,
    _QuantitySplitFn onQuantitySplit,
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
      await onQuantitySplit(
          subAccountId, sourceOrderId, sourceLineIndex, result);
    }
  }

  Future<void> _showFreeAmountSplitDialog(
    BuildContext context,
    String subAccountId,
    String sourceOrderId,
    int sourceLineIndex,
    _FreeAmountSplitFn onFreeAmountSplit,
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
      await onFreeAmountSplit(
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
    _HeadcountSplitFn onHeadcountSplit,
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
      await onHeadcountSplit(result);
    }
  }

  Future<void> _showAdjustmentDialog(
    BuildContext context,
    PosTableOperationalView view,
    String checkId,
    _AdjustmentFn onRequestAdjustment,
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
            onRequestAdjustment(
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
}

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
