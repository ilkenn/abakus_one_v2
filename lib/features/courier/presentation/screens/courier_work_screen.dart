import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../data/courier_work_repository.dart';
import '../../domain/work/courier_work_models.dart';
import '../providers/courier_work_providers.dart';

/// 2026-11-12 (Faz 3b) — "Kurye Ekranım", the server-backed courier app
/// (ADR-077). Opens for a signed-in staff account whose active role is
/// courier.
///
/// - **Görevlerim** — the courier's own orders, live: "Yola Çıktım",
///   "Teslim Ettim" (with the method the customer really paid) and "Ara"
///   (the customer phone is shown only until delivery — KVKK).
/// - **Havuz** / **Taleplerim** — external (`pool`) couriers only: open
///   packages of their districts ("Talep Oluştur") and their own requests.
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
    ];
    return DefaultTabController(
      length: tabs.length,
      child: _Shell(
        onSignOut: onSignOut,
        bottom: TabBar(tabs: tabs),
        body: TabBarView(
          children: [
            _MyOrdersTab(scope: scope),
            if (account.isExternal) ...[
              _PoolTab(account: account, scope: scope),
              _RequestsTab(scope: scope),
            ],
          ],
        ),
      ),
    );
  }
}

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

String _errorText(CourierWorkException error) => switch (error.code) {
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

  Future<void> _reportDelivered(CourierWorkOrder order) async {
    final method = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => _PaymentMethodSheet(order: order),
    );
    if (method == null || !mounted) return;
    await _run(
      order.orderId,
      () => ref
          .read(courierWorkGatewayProvider)
          .reportDelivered(order.orderId, method),
      '${order.orderNumber} teslim edildi (${courierPaymentMethodLabel(method)}).',
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
            onDeparted: () => _run(
              orders[i].orderId,
              () => ref
                  .read(courierWorkGatewayProvider)
                  .markDeparted(orders[i].orderId),
              '${orders[i].orderNumber}: yola çıktınız.',
            ),
            onDelivered: () => _reportDelivered(orders[i]),
            onCall: (phone) => ref.read(courierPhoneDialerProvider)(phone),
          ),
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.busy,
    required this.onDeparted,
    required this.onDelivered,
    required this.onCall,
  });

  final CourierWorkOrder order;
  final bool busy;
  final VoidCallback onDeparted;
  final VoidCallback onDelivered;
  final void Function(String phone) onCall;

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
    final phone = delivered ? null : order.customerPhone;
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
                if (phone != null && phone.isNotEmpty)
                  OutlinedButton.icon(
                    key: Key('callCustomer-${order.orderId}'),
                    icon: const Icon(Icons.phone_rounded),
                    label: const Text('Ara'),
                    onPressed: () => onCall(phone),
                  ),
                if (order.status == CourierWorkOrderStatus.assigned)
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodSheet extends StatefulWidget {
  const _PaymentMethodSheet({required this.order});

  final CourierWorkOrder order;

  @override
  State<_PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends State<_PaymentMethodSheet> {
  late String _method = courierDeliveryPaymentMethods
          .any((m) => m.id == widget.order.plannedPaymentMethodId)
      ? widget.order.plannedPaymentMethodId!
      : 'cash';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Müşteri nasıl ödedi?',
                style: AppTypography.titleMedium),
            Text(
                '${widget.order.orderNumber} · '
                '${formatCourierAmount(widget.order.amountDueMinorUnits)}',
                style: AppTypography.bodySmall),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final m in courierDeliveryPaymentMethods)
                  ChoiceChip(
                    key: Key('deliveryMethod-${m.id}'),
                    label: Text(m.label),
                    selected: _method == m.id,
                    onSelected: (_) => setState(() => _method = m.id),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              key: const Key('confirmDelivered'),
              onPressed: () => Navigator.of(context).pop(_method),
              child: const Text('Teslim Ettim'),
            ),
          ],
        ),
      ),
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
