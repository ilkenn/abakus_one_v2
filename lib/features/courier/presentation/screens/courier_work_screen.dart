import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../data/courier_work_repository.dart';
import '../../domain/work/courier_contact_plan.dart';
import '../../domain/work/courier_work_models.dart';
import '../providers/courier_work_providers.dart';
import '../widgets/courier_earnings_tab.dart';

/// 2026-11-12 (Faz 3b) — "Kurye Ekranım", the server-backed courier app
/// (ADR-077). Opens for a signed-in staff account whose active role is
/// courier.
///
/// - **Görevlerim** — the courier's own orders, live: "Yola Çıktım",
///   "Teslim Ettim" (with the method the customer really paid) and "Ara"
///   (the customer phone is shown only until delivery — KVKK).
/// - **Havuz** / **Taleplerim** — external (`pool`) couriers only: open
///   packages of their districts ("Talep Oluştur") and their own requests.
/// - **Kazancım** — ADR-085 stage 5: own rate, shift and earnings.
class CourierWorkScreen extends ConsumerWidget {
  const CourierWorkScreen({super.key, required this.uid, this.onSignOut});

  final String uid;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(courierWorkAccountProvider(uid));
    return accountAsync.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (_, __) => _Shell(
        onSignOut: onSignOut,
        body: const ErrorView(message: 'Kurye bilgileri yüklenemedi.'),
      ),
      data: (account) {
        if (account == null) {
          return _Shell(
            onSignOut: onSignOut,
            body: const EmptyView(
              key: Key('courierNotLinked'),
              icon: Icons.link_off_rounded,
              message: 'Hesabınız henüz bir kurye kaydına bağlı değil. '
                  'Şube müdürünüzden, POS\'taki kurye kaydınıza bu '
                  'hesabın e-postasını bağlamasını isteyin.',
            ),
          );
        }
        if (!account.isActive) {
          return _Shell(
            onSignOut: onSignOut,
            body: const EmptyView(
              key: Key('courierInactive'),
              icon: Icons.block_rounded,
              message: 'Kurye kaydınız şu anda pasif.',
            ),
          );
        }
        return _CourierWorkTabs(account: account, onSignOut: onSignOut);
      },
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.body, this.onSignOut, this.bottom});

  final Widget body;
  final VoidCallback? onSignOut;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kurye Ekranım'),
        bottom: bottom,
        actions: [
          if (onSignOut != null)
            IconButton(
              key: const Key('courierSignOut'),
              tooltip: 'Çıkış Yap',
              icon: const Icon(Icons.logout_rounded),
              onPressed: onSignOut,
            ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}

class _CourierWorkTabs extends StatelessWidget {
  const _CourierWorkTabs({required this.account, this.onSignOut});

  final CourierWorkAccount account;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final scope = (uid: account.uid, organizationId: account.organizationId);
    final tabs = [
      const Tab(key: Key('tabMyOrders'), text: 'Görevlerim'),
      if (account.isExternal) ...[
        const Tab(key: Key('tabPool'), text: 'Havuz'),
        const Tab(key: Key('tabRequests'), text: 'Taleplerim'),
      ],
      // ADR-085 stage 5 — rate, shift and earnings.
      const Tab(key: Key('tabEarnings'), text: 'Kazancım'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: _Shell(
        onSignOut: onSignOut,
        bottom: TabBar(tabs: tabs),
        body: TabBarView(
          children: [
            Column(
              children: [
                if (account.cashLimitExceeded)
                  _CashLimitBanner(account: account),
                Expanded(child: _MyOrdersTab(scope: scope)),
              ],
            ),
            if (account.isExternal) ...[
              _PoolTab(account: account, scope: scope),
              _RequestsTab(scope: scope),
            ],
            const CourierEarningsTab(),
          ],
        ),
      ),
    );
  }
}

/// ADR-085 stage 6C-1 — the courier passed the branch's cash limit.
class _CashLimitBanner extends StatelessWidget {
  const _CashLimitBanner({required this.account});

  final CourierWorkAccount account;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('courierCashLimitBanner'),
      width: double.infinity,
      color: AppColors.error,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Text(
        'Nakit limitiniz doldu, kasaya teslim yapın. Üzerinizdeki nakit: '
        '${formatCourierAmount(account.carriedCashMinorUnits)}'
        '${account.cashLimitMinorUnits == null ? '' : ' (limit ${formatCourierAmount(account.cashLimitMinorUnits!)})'}',
        style: AppTypography.bodyMedium
            .copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.bold),
      ),
    );
  }
}

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

String _errorText(CourierWorkException error) => switch (error.detailCode) {
      'courierDelivery/slip-required' =>
        'Kart veya yemek kartı tahsilatında slip fotoğrafı zorunlu.',
      'courierDelivery/slip-expired' ||
      'courierDelivery/slip-used' ||
      'courierDelivery/slip-invalid' =>
        'Slip fotoğrafı geçersiz ya da eski; yeniden çekin.',
      'courierDelivery/slip-missing' =>
        'Slip fotoğrafı yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.',
      'courierDelivery/online-payment-locked' =>
        'Online ödenmiş siparişin ödeme yöntemi değiştirilemez.',
      'courierDelivery/invalid-method' =>
        'Yalnızca kapıda ödeme yöntemleri seçilebilir.',
      'courierCancellation/already-pending' =>
        'Bu sipariş için iptal talebiniz zaten müdür onayında.',
      'courierCancellation/already-delivered' =>
        'Teslim edilmiş sipariş için iptal talebi gönderilemez.',
      'courierCancellation/invalid-reason' =>
        'Gerekçe en az 5 karakter olmalı.',
      'courierPool/not-handed-over' =>
        'Paketi önce kasadan teslim alın (Eksiksiz Hazırlandı onayı).',
      _ => _errorTextByCode(error),
    };

String _errorTextByCode(CourierWorkException error) => switch (error.code) {
      'permission-denied' ||
      'permission_denied' =>
        'Bu işlem için yetkiniz yok (sipariş size atanmamış olabilir).',
      'failed-precondition' ||
      'failed_precondition' =>
        'İşlem yapılamadı: paket artık uygun değil (başka kuryeye verilmiş, '
            'havuzdan alınmış ya da henüz yola çıkmaya hazır değil).',
      'not-found' || 'not_found' => 'Paket bulunamadı.',
      _ => 'İşlem gerçekleştirilemedi. Lütfen tekrar deneyin.',
    };

class _MyOrdersTab extends ConsumerStatefulWidget {
  const _MyOrdersTab({required this.scope});

  final CourierWorkScope scope;

  @override
  ConsumerState<_MyOrdersTab> createState() => _MyOrdersTabState();
}

class _MyOrdersTabState extends ConsumerState<_MyOrdersTab> {
  String? _busyOrderId;

  Future<void> _run(
      String orderId, Future<void> Function() action, String success) async {
    if (_busyOrderId != null) return;
    setState(() => _busyOrderId = orderId);
    try {
      await action();
      if (mounted) _snack(context, success);
    } on CourierWorkException catch (error) {
      if (mounted) _snack(context, _errorText(error));
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  /// "Yola Çıktım". A card-at-the-door order first asks the courier to
  /// confirm it has the POS device (ADR-085 stage 5 follow-up).
  Future<void> _departed(CourierWorkOrder order) async {
    if (courierNeedsPosDevice(order.plannedPaymentMethodId)) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PosDeviceCheckDialog(order: order),
      );
      if (confirmed != true || !mounted) return;
    }
    await _run(
      order.orderId,
      () => ref.read(courierWorkGatewayProvider).markDeparted(order.orderId),
      '${order.orderNumber}: yola çıktınız.',
    );
  }

  Future<void> _reportDelivered(CourierWorkOrder order) async {
    final result = await showModalBottomSheet<_DeliveryReport>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PaymentMethodSheet(order: order),
    );
    if (result == null || !mounted) return;
    final method = result.method;
    await _run(
      order.orderId,
      () => ref
          .read(courierWorkGatewayProvider)
          .reportDelivered(order.orderId, method, slipPhoto: result.slip),
      method == null
          ? '${order.orderNumber} teslim edildi (online ödendi).'
          : '${order.orderNumber} teslim edildi '
              '(${courierPaymentMethodLabel(method)}).',
    );
  }

  /// ADR-085 stage 6B — "İptal Talebi Gönder": a reason, then the Onay
  /// Kutusu decides (a courier never cancels itself).
  Future<void> _requestCancellation(CourierWorkOrder order) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancellationReasonDialog(order: order),
    );
    if (reason == null || !mounted) return;
    await _run(
      order.orderId,
      () => ref
          .read(courierWorkGatewayProvider)
          .requestCancellation(order.orderId, reason),
      '${order.orderNumber}: iptal talebiniz müdür onayına gönderildi.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(courierWorkOrdersProvider(widget.scope));
    return ordersAsync.when(
      loading: () => const LoadingView(),
      error: (_, __) => const ErrorView(message: 'Görevler yüklenemedi.'),
      data: (orders) {
        if (orders.isEmpty) {
          return const EmptyView(
            key: Key('noCourierOrders'),
            icon: Icons.delivery_dining_outlined,
            message: 'Şu anda size atanmış paket yok.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: orders.length,
          itemBuilder: (_, i) => _OrderCard(
            order: orders[i],
            busy: _busyOrderId == orders[i].orderId,
            onDeparted: () => _departed(orders[i]),
            onDelivered: () => _reportDelivered(orders[i]),
            onRequestCancellation: () => _requestCancellation(orders[i]),
            onOpen: (uri) => ref.read(courierUriLauncherProvider)(uri),
          ),
        );
      },
    );
  }
}

/// "POS Cihazı Kontrolü": the departure waits until the courier ticks
/// "POS cihazını yanıma aldım".
class _PosDeviceCheckDialog extends StatefulWidget {
  const _PosDeviceCheckDialog({required this.order});

  final CourierWorkOrder order;

  @override
  State<_PosDeviceCheckDialog> createState() => _PosDeviceCheckDialogState();
}

class _PosDeviceCheckDialogState extends State<_PosDeviceCheckDialog> {
  bool _taken = false;

  @override
  Widget build(BuildContext context) {
    final method =
        courierPaymentMethodLabel(widget.order.plannedPaymentMethodId);
    return AlertDialog(
      key: const Key('posDeviceCheckDialog'),
      icon: const Icon(Icons.point_of_sale_rounded, color: AppColors.warning),
      title: const Text('POS Cihazı Kontrolü'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bu sipariş KAPIDA POS ile ödenecektir ($method). '
            'Yola çıkmadan POS cihazını yanınıza alın.',
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          CheckboxListTile(
            key: const Key('posDeviceTaken'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _taken,
            onChanged: (value) => setState(() => _taken = value ?? false),
            title: const Text('POS cihazını yanıma aldım'),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('posDeviceCancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          key: const Key('posDeviceConfirmDepart'),
          onPressed: _taken ? () => Navigator.of(context).pop(true) : null,
          child: const Text("POS'u Aldım, Yola Çık"),
        ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.busy,
    required this.onDeparted,
    required this.onDelivered,
    required this.onRequestCancellation,
    required this.onOpen,
  });

  final CourierWorkOrder order;
  final bool busy;
  final VoidCallback onDeparted;
  final VoidCallback onDelivered;
  final VoidCallback onRequestCancellation;
  final Future<void> Function(Uri uri) onOpen;

  /// ADR-085 stage 4 — "Konuma Git": pick Google, Apple or Yandex.
  Future<void> _chooseNavigation(
    BuildContext context,
    List<CourierNavigationOption> options,
  ) async {
    final chosen = await showModalBottomSheet<CourierNavigationOption>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              ListTile(
                key: Key('navigateWith-${option.label}'),
                leading: const Icon(Icons.map_outlined),
                title: Text(option.label),
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) await onOpen(chosen.uri);
  }

  @override
  Widget build(BuildContext context) {
    final (String statusText, Color statusColor) = switch (order.status) {
      CourierWorkOrderStatus.reserved => (
          'Size ayrıldı — mutfakta hazırlanıyor',
          AppColors.info
        ),
      CourierWorkOrderStatus.assigned => ('Teslim alınacak', AppColors.primary),
      CourierWorkOrderStatus.departed => ('Yolda', AppColors.success),
      CourierWorkOrderStatus.deliveredAwaitingSettlement => (
          'Teslim Edildi — Mutabakat Bekliyor',
          AppColors.warning
        ),
    };
    // ADR-085 stage 2 (KVKK) — the server already strips name, phone, open
    // address and note at "Teslim Ettim"; the card never shows them for a
    // delivered order either, even from a stale cached copy.
    final delivered =
        order.status == CourierWorkOrderStatus.deliveredAwaitingSettlement;
    final callPlan = courierCallPlan(order);
    final navigation = courierNavigationOptions(order);
    final late = order.lateMinutesAt(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        key: Key('courierOrder-${order.orderId}'),
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
                Text(formatCourierAmount(order.amountDueMinorUnits),
                    style: AppTypography.titleMedium.copyWith(
                        color: AppColors.primary, fontWeight: FontWeight.bold)),
              ],
            ),
            Text(statusText,
                key: Key('courierOrderStatus-${order.orderId}'),
                style: AppTypography.bodySmall
                    .copyWith(color: statusColor, fontWeight: FontWeight.bold)),
            if (late != null)
              Container(
                key: Key('courierLate-${order.orderId}'),
                margin: const EdgeInsets.only(top: AppSpacing.xs),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: const BoxDecoration(
                    color: AppColors.error, borderRadius: AppRadius.kSmall),
                child: Text('GECİKTİ · $late dk',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.onPrimary)),
              ),
            if (!order.handedOver && !delivered)
              Text(
                'Paketi kasadan teslim alın — kontrol onayından sonra yola '
                'çıkabilirsiniz.',
                key: Key('courierNotHandedOver-${order.orderId}'),
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.warning),
              ),
            const SizedBox(height: AppSpacing.xs),
            if (order.branchName.isNotEmpty)
              Text('Alış: ${order.branchName}', style: AppTypography.bodySmall),
            if (!delivered && order.customerName.isNotEmpty)
              Text(order.customerName, style: AppTypography.bodyMedium),
            Text(
              [order.neighborhoodName, if (!delivered) order.addressLine]
                  .where((p) => p.isNotEmpty)
                  .join(' · '),
              style: AppTypography.bodyMedium,
            ),
            if (delivered)
              Text(
                'Müşteri bilgileri teslimattan sonra kaldırıldı (KVKK).',
                key: Key('courierPiiRemoved-${order.orderId}'),
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
            if (!delivered && order.courierNote.trim().isNotEmpty)
              Text('Not: ${order.courierNote.trim()}',
                  style: AppTypography.bodySmall.copyWith(
                      color: AppColors.warning, fontWeight: FontWeight.bold)),
            Text(
              order.status == CourierWorkOrderStatus.deliveredAwaitingSettlement
                  ? 'Tahsilat: ${courierPaymentMethodLabel(order.reportedPaymentMethodId)}'
                  : 'Ödeme: ${courierPaymentMethodLabel(order.plannedPaymentMethodId)}',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (navigation.isNotEmpty)
                  OutlinedButton.icon(
                    key: Key('navigate-${order.orderId}'),
                    icon: const Icon(Icons.near_me_rounded),
                    label: const Text('Konuma Git'),
                    onPressed: () => _chooseNavigation(context, navigation),
                  ),
                if (callPlan != null)
                  OutlinedButton.icon(
                    key: Key('callCustomer-${order.orderId}'),
                    icon: const Icon(Icons.phone_rounded),
                    label: Text(callPlan.label),
                    onPressed: () => onOpen(callPlan.uri),
                  ),
                if (order.status == CourierWorkOrderStatus.assigned &&
                    order.handedOver)
                  FilledButton.icon(
                    key: Key('departed-${order.orderId}'),
                    icon: const Icon(Icons.two_wheeler_rounded),
                    label: const Text('Yola Çıktım'),
                    onPressed: busy ? null : onDeparted,
                  ),
                if (order.status == CourierWorkOrderStatus.assigned ||
                    order.status == CourierWorkOrderStatus.departed)
                  FilledButton.icon(
                    key: Key('delivered-${order.orderId}'),
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Teslim Ettim'),
                    onPressed: busy ? null : onDelivered,
                  ),
                if ((order.status == CourierWorkOrderStatus.assigned ||
                        order.status == CourierWorkOrderStatus.departed) &&
                    order.cancellationRequestStatus != 'pending')
                  TextButton.icon(
                    key: Key('requestCancel-${order.orderId}'),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('İptal Talebi Gönder'),
                    onPressed: busy ? null : onRequestCancellation,
                  ),
              ],
            ),
            if (order.cancellationRequestStatus == 'pending')
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'İptal talebiniz müdür onayında — paketi şimdilik '
                  'yanınızda tutun.',
                  key: Key('cancelPending-${order.orderId}'),
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.warning),
                ),
              ),
            if (order.cancellationRequestStatus == 'rejected')
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'İptal talebiniz reddedildi — teslimata devam edin.',
                  key: Key('cancelRejected-${order.orderId}'),
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What "Teslim Ettim" sends: the method (`null` = paid online) and, for a
/// card or meal card, the slip photo.
typedef _DeliveryReport = ({String? method, Uint8List? slip});

/// "Müşteri nasıl ödedi?" — ADR-085 stage 6B: only pay-on-delivery methods
/// (an order paid online asks nothing), and a card or meal card needs a
/// camera photo of the slip before "Teslim Ettim" is enabled.
class _PaymentMethodSheet extends ConsumerStatefulWidget {
  const _PaymentMethodSheet({required this.order});

  final CourierWorkOrder order;

  @override
  ConsumerState<_PaymentMethodSheet> createState() =>
      _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends ConsumerState<_PaymentMethodSheet> {
  late final bool _paidOnline =
      !courierIsPayOnDelivery(widget.order.plannedPaymentMethodId);
  late String _method = courierDeliveryPaymentMethods
          .any((m) => m.id == widget.order.plannedPaymentMethodId)
      ? widget.order.plannedPaymentMethodId!
      : 'cash';
  Uint8List? _slip;
  bool _capturing = false;

  bool get _needsSlip => !_paidOnline && courierNeedsPosDevice(_method);

  bool get _changed =>
      widget.order.plannedPaymentMethodId != null &&
      widget.order.plannedPaymentMethodId != _method;

  Future<void> _capture() async {
    setState(() => _capturing = true);
    try {
      final photo = await ref.read(courierSlipCameraProvider)();
      if (photo != null && mounted) setState(() => _slip = photo);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _paidOnline || !_needsSlip || _slip != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_paidOnline ? 'Teslimatı onaylayın' : 'Müşteri nasıl ödedi?',
                  style: AppTypography.titleMedium),
              Text(
                  '${widget.order.orderNumber} · '
                  '${formatCourierAmount(widget.order.amountDueMinorUnits)}',
                  style: AppTypography.bodySmall),
              const SizedBox(height: AppSpacing.md),
              if (_paidOnline)
                const Text(
                  'Bu sipariş online ödendi; kapıda tahsilat yok ve ödeme '
                  'yöntemi değiştirilemez.',
                  key: Key('deliveryPaidOnline'),
                  style: AppTypography.bodyMedium,
                )
              else
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final m in courierDeliveryPaymentMethods)
                      ChoiceChip(
                        key: Key('deliveryMethod-${m.id}'),
                        label: Text(m.label),
                        selected: _method == m.id,
                        onSelected: (_) => setState(() {
                          _method = m.id;
                          _slip = null; // the photo belongs to one method
                        }),
                      ),
                  ],
                ),
              if (!_paidOnline && _changed) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Ödeme yöntemi değişti: '
                  '${courierPaymentMethodLabel(widget.order.plannedPaymentMethodId)}'
                  ' → ${courierPaymentMethodLabel(_method)}. Müdüre bildirilecek.',
                  key: const Key('deliveryMethodChanged'),
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.warning),
                ),
              ],
              if (_needsSlip) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'POS slipinin ya da yemek kartı onay ekranının fotoğrafını '
                  'çekin (galeriden seçilemez).',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  key: const Key('slipCapture'),
                  onPressed: _capturing ? null : _capture,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(_slip == null
                      ? 'Slip Fotoğrafı Çek'
                      : 'Fotoğraf çekildi — Yeniden Çek'),
                ),
                if (_slip != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: AppRadius.kSmall,
                    child: Image.memory(
                      _slip!,
                      key: const Key('slipPreview'),
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.image_outlined),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                key: const Key('confirmDelivered'),
                onPressed: canConfirm
                    ? () => Navigator.of(context).pop((
                          method: _paidOnline ? null : _method,
                          slip: _needsSlip ? _slip : null,
                        ))
                    : null,
                child: const Text('Teslim Ettim'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CancellationReasonDialog extends StatefulWidget {
  const _CancellationReasonDialog({required this.order});

  final CourierWorkOrder order;

  @override
  State<_CancellationReasonDialog> createState() =>
      _CancellationReasonDialogState();
}

class _CancellationReasonDialogState extends State<_CancellationReasonDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.order.orderNumber} — İptal Talebi'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Siparişi siz iptal edemezsiniz; talebiniz müdür veya yöneticinin '
            'onayına gider. Neden teslim edemediğinizi yazın.',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          TextField(
            key: const Key('cancelReason'),
            controller: _reason,
            maxLength: 300,
            maxLines: 3,
            minLines: 2,
            decoration: InputDecoration(
              labelText: 'Gerekçe',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          key: const Key('cancelReasonSend'),
          onPressed: () {
            final text = _reason.text.trim();
            if (text.length < 5) {
              setState(() => _error = 'En az 5 karakterlik bir gerekçe yazın');
              return;
            }
            Navigator.of(context).pop(text);
          },
          child: const Text('İptal Talebi Gönder'),
        ),
      ],
    );
  }
}

class _PoolTab extends ConsumerStatefulWidget {
  const _PoolTab({required this.account, required this.scope});

  final CourierWorkAccount account;
  final CourierWorkScope scope;

  @override
  ConsumerState<_PoolTab> createState() => _PoolTabState();
}

class _PoolTabState extends ConsumerState<_PoolTab> {
  String? _busyOrderId;

  Future<void> _request(CourierPoolPackage package) async {
    if (_busyOrderId != null) return;
    setState(() => _busyOrderId = package.orderId);
    try {
      await ref
          .read(courierWorkGatewayProvider)
          .requestPoolOrder(package.orderId);
      if (mounted) {
        _snack(
            context, '${package.orderNumber} için talebiniz şubeye iletildi.');
      }
    } on CourierWorkException catch (error) {
      if (mounted) _snack(context, _errorText(error));
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final packagesAsync = ref.watch(courierPoolPackagesProvider((
      organizationId: widget.account.organizationId,
      districtKey: widget.account.serviceDistrictIds.join(','),
    )));
    final pendingOrderIds = {
      for (final r
          in ref.watch(courierOwnRequestsProvider(widget.scope)).valueOrNull ??
              const <CourierOwnPoolRequest>[])
        if (r.status == CourierOwnRequestStatus.pending) r.orderId,
    };
    return packagesAsync.when(
      loading: () => const LoadingView(),
      error: (_, __) => const ErrorView(message: 'Havuz yüklenemedi.'),
      data: (packages) {
        if (packages.isEmpty) {
          return const EmptyView(
            key: Key('emptyPool'),
            icon: Icons.inventory_2_outlined,
            message: 'Bölgenizde şu anda havuzda paket yok.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: packages.length,
          itemBuilder: (_, i) {
            final p = packages[i];
            final requested = pendingOrderIds.contains(p.orderId);
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: AppCard(
                key: Key('poolPackage-${p.orderId}'),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(p.neighborhoodName,
                              style: AppTypography.titleMedium
                                  .copyWith(fontWeight: FontWeight.bold)),
                        ),
                        Text(formatCourierAmount(p.amountDueMinorUnits),
                            style: AppTypography.titleMedium.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    if (p.addressLine.isNotEmpty)
                      Text(p.addressLine, style: AppTypography.bodyMedium),
                    Text(
                      [
                        if (p.branchName.isNotEmpty) 'Alış: ${p.branchName}',
                        'Ödeme: ${courierPaymentMethodLabel(p.plannedPaymentMethodId)}',
                      ].join(' · '),
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        key: Key('requestPackage-${p.orderId}'),
                        icon: Icon(requested
                            ? Icons.hourglass_top_rounded
                            : Icons.front_hand_rounded),
                        label: Text(
                            requested ? 'Talep gönderildi' : 'Talep Oluştur'),
                        onPressed: requested || _busyOrderId != null
                            ? null
                            : () => _request(p),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab({required this.scope});

  final CourierWorkScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(courierOwnRequestsProvider(scope));
    return requestsAsync.when(
      loading: () => const LoadingView(),
      error: (_, __) => const ErrorView(message: 'Talepler yüklenemedi.'),
      data: (requests) {
        if (requests.isEmpty) {
          return const EmptyView(
            key: Key('noOwnRequests'),
            icon: Icons.inbox_outlined,
            message: 'Henüz bir talebiniz yok.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: requests.length,
          itemBuilder: (_, i) {
            final r = requests[i];
            final color = switch (r.status) {
              CourierOwnRequestStatus.pending => AppColors.info,
              CourierOwnRequestStatus.approved => AppColors.success,
              CourierOwnRequestStatus.rejected => AppColors.textSecondary,
            };
            return ListTile(
              key: Key('ownRequest-${r.requestId}'),
              title: Text('${r.orderNumber} · ${r.neighborhoodName}'),
              subtitle: Text(formatCourierAmount(r.amountDueMinorUnits)),
              trailing: Text(r.statusLabel,
                  style: AppTypography.bodySmall
                      .copyWith(color: color, fontWeight: FontWeight.bold)),
            );
          },
        );
      },
    );
  }
}
