import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../data/cash_register_gateway.dart';
import '../../data/courier_settlement_gateway.dart';
import '../../data/kitchen_action_gateway.dart';
import '../../data/pos_action_gateway.dart' show PosDeviceContext;
import '../providers/kds_dependencies_provider.dart';
import '../providers/pos_workspace_providers.dart';
import '../widgets/kitchen_order_cancel_dialog.dart';

/// The pay-on-delivery methods a courier can bring back — the server's
/// `STAFF_DELIVERY_PAYMENT_METHOD_IDS`.
const posCollectionMethods = [
  (id: 'cash', label: 'Nakit'),
  (id: 'credit_card', label: 'POS'),
  (id: 'pluxee', label: 'Pluxee'),
  (id: 'multinet', label: 'Multinet'),
  (id: 'setcard', label: 'Setcard'),
  (id: 'edenred', label: 'Edenred'),
];

/// 2026-11-11 (Faz 2b) — "Kurye Döndü — Hesap Kapat" for one courier
/// (product-owner decisions):
/// - every order on the courier closes in one go; each delivered order is
///   recorded with the method the customer really paid with (changeable
///   from the planned one — the server audits the change), with an optional
///   slip number for POS / meal cards;
/// - an undelivered order goes through the existing staff cancellation
///   (reason required) and is never collected;
/// - the cashier enters the cash the courier handed over; a difference can
///   only be closed by a manager with a reason (enforced by the server —
///   this screen asks for the reason and explains a refusal);
/// - the cash enters this till's active cash session; the Z report adds
///   every collection to its tender line ("Paket Servis Tahsilatı",
///   "Kurye Farkı");
/// - tips are out of scope: the amount is the order total.
class PosCourierSettlementScreen extends ConsumerStatefulWidget {
  const PosCourierSettlementScreen({
    super.key,
    required this.ctx,
    required this.courierId,
  });

  final PosDeviceContext ctx;
  final String courierId;

  @override
  ConsumerState<PosCourierSettlementScreen> createState() =>
      _PosCourierSettlementScreenState();
}

class _PosCourierSettlementScreenState
    extends ConsumerState<PosCourierSettlementScreen> {
  CourierSettlementPreview? _preview;
  Object? _loadError;
  String? _cashSessionId;
  bool _cashSessionMissing = false;

  final Map<String, String> _methodByOrderId = {};
  final Map<String, TextEditingController> _slipByOrderId = {};
  final _receivedCashController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _receivedCashEdited = false;
  bool _busy = false;
  String? _error;

  /// Kept across retries so a resend never books the cash twice.
  String? _settlementKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final controller in _slipByOrderId.values) {
      controller.dispose();
    }
    _receivedCashController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _error = null;
    });
    try {
      final preview = await ref
          .read(courierSettlementGatewayProvider)
          .preview(ctx: widget.ctx, courierId: widget.courierId);
      final drawers = await ref
          .read(cashRegisterGatewayProvider)
          .listCashDrawers(ctx: widget.ctx);
      final active = drawers
          .map((d) => d.openSession)
          .whereType<CashOpenSessionSummary>()
          .where((s) => s.status == 'active')
          .firstOrNull;
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _cashSessionId = active?.sessionId;
        _cashSessionMissing = active == null;
        for (final order in preview.orders) {
          _methodByOrderId.putIfAbsent(
              order.orderId,
              // Faz 3a — what the courier reported at "Teslim Ettim" comes
              // first (still editable; a change is audited server-side).
              () => _isKnownMethod(order.courierReportedPaymentMethodId)
                  ? order.courierReportedPaymentMethodId!
                  : _isKnownMethod(order.plannedPaymentMethodId)
                      ? order.plannedPaymentMethodId!
                      : 'cash');
          _slipByOrderId.putIfAbsent(
              order.orderId, () => TextEditingController());
        }
        if (!_receivedCashEdited) {
          _receivedCashController.text =
              (_expectedCashMinorUnits ~/ 100).toString();
        }
      });
    } on CourierSettlementException catch (e) {
      if (mounted) setState(() => _loadError = e);
    } on CashRegisterGatewayException catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  static bool _isKnownMethod(String? id) =>
      posCollectionMethods.any((m) => m.id == id);

  List<CourierSettlementOrder> get _openOrders =>
      _preview?.orders.where((o) => o.isOpen).toList() ?? const [];

  int get _expectedCashMinorUnits => _openOrders
      .where((o) => _methodByOrderId[o.orderId] == 'cash')
      .fold(0, (sum, o) => sum + o.amountDueMinorUnits);

  int? get _receivedCashMinorUnits {
    final text = _receivedCashController.text.trim().replaceAll(',', '.');
    if (text.isEmpty) return 0;
    final value = double.tryParse(text);
    if (value == null || value < 0) return null;
    return (value * 100).round();
  }

  int? get _differenceMinorUnits {
    final received = _receivedCashMinorUnits;
    return received == null ? null : received - _expectedCashMinorUnits;
  }

  Future<void> _markUndelivered(CourierSettlementOrder order) async {
    final reason = await showKitchenOrderCancelDialog(
      context,
      channel: OrderChannel.delivery,
    );
    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(kitchenActionGatewayProvider).cancelOrder(
            orderId: order.orderId,
            channel: 'delivery',
            reasonCode: reason,
          );
      _settlementKey = null;
      await _load();
    } on KitchenActionException catch (e) {
      if (mounted) {
        setState(() => _error = switch (e.code) {
              'permission-denied' ||
              'permission_denied' =>
                'Yoldaki siparişi iptal etmek yönetici yetkisi ister.',
              _ => 'Sipariş iptal edilemedi. Lütfen tekrar deneyin.',
            });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _settle() async {
    final cashSessionId = _cashSessionId;
    final received = _receivedCashMinorUnits;
    final difference = _differenceMinorUnits;
    if (cashSessionId == null) return;
    if (received == null || difference == null) {
      setState(() => _error = 'Alınan nakit tutarını geçerli girin.');
      return;
    }
    if (difference != 0 && _reasonController.text.trim().isEmpty) {
      setState(() => _error = 'Fark var: fark açıklaması zorunludur.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _settlementKey ??= DateTime.now().microsecondsSinceEpoch.toString();
    try {
      final result = await ref.read(courierSettlementGatewayProvider).settle(
            ctx: widget.ctx,
            courierId: widget.courierId,
            cashSessionId: cashSessionId,
            settlementKey: _settlementKey!,
            deliveries: [
              for (final order in _openOrders)
                CourierSettlementDelivery(
                  orderId: order.orderId,
                  paymentMethodId: _methodByOrderId[order.orderId]!,
                  slipNumber: _methodByOrderId[order.orderId] == 'cash'
                      ? null
                      : _slipByOrderId[order.orderId]!.text,
                ),
            ],
            receivedCashMinorUnits: received,
            differenceReason:
                difference == 0 ? null : _reasonController.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${_preview?.courierName ?? 'Kurye'} hesabı kapatıldı: '
            '${_tl(result.totalCollectedMinorUnits)} tahsil edildi.'),
      ));
      Navigator.of(context).pop(true);
    } on CourierSettlementException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(e);
      });
    }
  }

  static String _messageFor(CourierSettlementException e) => switch (e.code) {
        'permission-denied' ||
        'permission_denied' =>
          'Kasa farkı var: hesabı yalnızca yönetici, açıklama girerek '
              'kapatabilir.',
        'failed-precondition' ||
        'failed_precondition' =>
          'Hesap kapatılamadı: kuryenin sipariş listesi değişmiş ya da kasa '
              'oturumu aktif değil. Ekranı yenileyip tekrar deneyin.',
        'invalid-argument' ||
        'invalid_argument' =>
          'Bilgiler geçersiz; fark açıklamasını ve tutarları kontrol edin.',
        _ => 'Hesap kapatılamadı. Lütfen tekrar deneyin.',
      };

  static String _tl(int minorUnits) {
    final whole = minorUnits ~/ 100;
    final kurus = (minorUnits % 100).abs();
    return kurus == 0
        ? '$whole TL'
        : '$whole,${kurus.toString().padLeft(2, '0')} TL';
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(preview == null
            ? 'Kurye Hesap Kapat'
            : 'Kurye Hesap Kapat — ${preview.courierName}'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: _loadError != null
            ? ErrorView(
                message: 'Kurye bilgisi yüklenemedi.',
                retryLabel: 'Tekrar Dene',
                onRetry: _load,
              )
            : preview == null
                ? const LoadingView(message: 'Kurye siparişleri yükleniyor...')
                : _buildContent(preview),
      ),
    );
  }

  Widget _buildContent(CourierSettlementPreview preview) {
    final open = _openOrders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_cashSessionMissing)
          Container(
            key: const Key('noCashSessionNotice'),
            margin: const EdgeInsets.all(AppSpacing.md),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: AppRadius.kMedium,
            ),
            child: const Text(
              'Bu kasada açık bir kasa oturumu yok. Önce Kasa ekranından '
              'kasayı açın; kurye tahsilatı açık oturuma işlenir.',
              style: AppTypography.bodyMedium,
            ),
          ),
        Expanded(
          child: open.isEmpty
              ? const Center(
                  child: Text(
                    'Bu kuryenin üzerinde açık sipariş yok. "Hesabı Kapat" '
                    'kuryeyi müsait yapar.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    for (final order in open) _buildOrderCard(order),
                  ],
                ),
        ),
        const Divider(height: 1, color: AppColors.border),
        _buildSummary(),
      ],
    );
  }

  static String _methodLabel(String id) =>
      posCollectionMethods.where((m) => m.id == id).firstOrNull?.label ?? id;

  Widget _buildOrderCard(CourierSettlementOrder order) {
    final method = _methodByOrderId[order.orderId] ?? 'cash';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        key: Key('settlementOrder-${order.orderId}'),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(order.orderNumber,
                      style: AppTypography.titleMedium
                          .copyWith(fontWeight: FontWeight.bold)),
                ),
                Text(_tl(order.amountDueMinorUnits),
                    style: AppTypography.titleMedium.copyWith(
                        color: AppColors.primary, fontWeight: FontWeight.bold)),
              ],
            ),
            Text(
              [order.customerName, order.addressSummary]
                  .where((p) => p.isNotEmpty)
                  .join(' · '),
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final m in posCollectionMethods)
                  ChoiceChip(
                    key: Key('method-${order.orderId}-${m.id}'),
                    label: Text(m.label),
                    selected: method == m.id,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                              _methodByOrderId[order.orderId] = m.id;
                              _settlementKey = null;
                              if (!_receivedCashEdited) {
                                _receivedCashController.text =
                                    (_expectedCashMinorUnits ~/ 100).toString();
                              }
                            }),
                  ),
              ],
            ),
            if (order.courierReportedPaymentMethodId != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  order.courierReportedPaymentMethodId == method
                      ? 'Kurye bildirdi: ${_methodLabel(method)}'
                      : 'Kurye bildirdi: '
                          '${_methodLabel(order.courierReportedPaymentMethodId!)}'
                          ' — kasiyer değiştirdi',
                  key: Key('courierReported-${order.orderId}'),
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.info),
                ),
              ),
            if (order.plannedPaymentMethodId != null &&
                order.plannedPaymentMethodId != method)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Siparişte planlanan yöntemden farklı — değişiklik kayda '
                  'geçer.',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.warning),
                ),
              ),
            if (method != 'cash')
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: TextField(
                  key: Key('slip-${order.orderId}'),
                  controller: _slipByOrderId[order.orderId],
                  maxLength: 64,
                  onChanged: (_) => _settlementKey = null,
                  decoration: const InputDecoration(
                    labelText: 'Slip No (isteğe bağlı)',
                    isDense: true,
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: AppRadius.kSmall),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('undelivered-${order.orderId}'),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Teslim Edilemedi'),
                onPressed: _busy ? null : () => _markUndelivered(order),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final difference = _differenceMinorUnits;
    final canSettle = !_busy && _cashSessionId != null && difference != null;
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('Kuryeden beklenen nakit',
                      style: AppTypography.bodyLarge)),
              Text(_tl(_expectedCashMinorUnits),
                  key: const Key('expectedCash'),
                  style: AppTypography.titleMedium
                      .copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('receivedCashField'),
            controller: _receivedCashController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {
              _receivedCashEdited = true;
              _settlementKey = null;
            }),
            decoration: const InputDecoration(
              labelText: 'Kuryeden alınan nakit (TL)',
              isDense: true,
              border: OutlineInputBorder(borderRadius: AppRadius.kSmall),
            ),
          ),
          if (difference != null && difference != 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Kurye Farkı: ${difference > 0 ? '+' : ''}${_tl(difference)} — '
              'yalnızca yönetici, açıklama girerek kapatabilir.',
              key: const Key('differenceNotice'),
              style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.error, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              key: const Key('differenceReasonField'),
              controller: _reasonController,
              maxLength: 300,
              onChanged: (_) => _settlementKey = null,
              decoration: const InputDecoration(
                labelText: 'Fark açıklaması',
                isDense: true,
                counterText: '',
                border: OutlineInputBorder(borderRadius: AppRadius.kSmall),
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(_error!,
                  key: const Key('settlementError'),
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error)),
            ),
          const SizedBox(height: AppSpacing.sm),
          ElevatedButton.icon(
            key: const Key('settleCourierButton'),
            onPressed: canSettle ? _settle : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size.fromHeight(56),
              textStyle: AppTypography.titleMedium
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            icon: _busy
                ? const SizedBox.square(
                    dimension: AppSpacing.md,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.task_alt_rounded),
            label: const Text('Hesabı Kapat'),
          ),
        ],
      ),
    );
  }
}
