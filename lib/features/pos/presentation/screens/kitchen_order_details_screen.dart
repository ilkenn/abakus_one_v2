import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/services/logging/log_level.dart';
import '../../../../core/services/logging/logging_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/advance_kitchen_order.dart';
import '../../application/use_cases/record_kitchen_event.dart';
import '../../application/use_cases/transition_kitchen_work_item.dart';
import '../../data/kitchen_action_gateway.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/kds/kitchen_line_status.dart';
import '../../domain/kds/kitchen_order_action_policy.dart';
import '../../domain/kds/kitchen_order_view.dart';
import '../../domain/kds/kitchen_work_item.dart';
import '../../domain/kitchen/kitchen_ticket.dart';
import '../../domain/kitchen/kitchen_ticket_line.dart';
import '../providers/kds_dependencies_provider.dart';
import '../providers/kitchen_ticket_dependencies_provider.dart';
import '../widgets/kitchen_order_cancel_dialog.dart';
import 'kitchen_display_board_screen.dart' show KitchenOrderCard;

/// Full detail view of one [KitchenTicket]'s [KitchenWorkItem]s — every
/// line-level action (acknowledge/start/ready/cancel/recall/resume), the
/// derived [KitchenOrderView] readiness, allergy warnings, and
/// preparation notes at a larger, more deliberate scale than the board's
/// compact card (`KitchenOrderCard`, reused there for the summary tile
/// shape only — the constant/label maps live alongside it).
class KitchenOrderDetailsScreen extends ConsumerStatefulWidget {
  const KitchenOrderDetailsScreen({
    super.key,
    required this.kitchenTicketId,
    this.authorizationPolicy,
    this.deviceId,
    this.performedByStaffId = 'staff-1',
  });

  final String kitchenTicketId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String? deviceId;
  final String performedByStaffId;

  @override
  ConsumerState<KitchenOrderDetailsScreen> createState() =>
      _KitchenOrderDetailsScreenState();
}

class _KitchenOrderDetailsScreenState
    extends ConsumerState<KitchenOrderDetailsScreen> {
  KitchenTicket? _ticket;
  List<KitchenWorkItem>? _workItems;
  String? _message;

  /// 2026-10-29 — distinguishes "still loading" from "load finished, but
  /// nothing was found" or "load failed/timed out". Previously absent: a
  /// `null` ticket after a *completed* load rendered the exact same
  /// `LoadingView` as a load still in flight, so a genuinely-missing
  /// ticket (a stale/mismatched `kitchenTicketId`, or a slow/failing
  /// `kitchenTicketRepositoryProvider` read) looked identical to "still
  /// loading" forever — the real cause of the reported "Detaylar
  /// yükleniyor..." infinite spinner.
  bool _loadAttempted = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loadAttempted = false;
      _loadError = null;
    });
    try {
      final ticket = await ref
          .read(kitchenTicketRepositoryProvider)
          .findById(widget.kitchenTicketId)
          .timeout(const Duration(seconds: 15));
      final allItems = ticket == null
          ? <KitchenWorkItem>[]
          : await ref
              .read(kitchenProjectionRepositoryProvider)
              .findByOrderId(ticket.orderId)
              .timeout(const Duration(seconds: 15));
      final items = allItems
          .where((i) => i.kitchenTicketId == widget.kitchenTicketId)
          .toList();
      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _workItems = items;
        _loadAttempted = true;
        _loadError = ticket == null ? 'Sipariş bulunamadı.' : null;
      });
    } catch (error, stackTrace) {
      // 2026-11-11 — logged: this catch used to swallow the real cause
      // (a rules-denied kitchenWorkItems query) without a trace.
      ref.read(loggingServiceProvider).log(
        LogLevel.error,
        'KitchenOrderDetailsScreen._load failed',
        error: error,
        stackTrace: stackTrace,
        context: {'kitchenTicketId': widget.kitchenTicketId},
      );
      if (!mounted) return;
      setState(() {
        _loadAttempted = true;
        _loadError = 'Detaylar yüklenemedi. Lütfen tekrar dene.';
      });
    }
  }

  /// 2026-10-29 — once Firebase is ready, the real `transitionKitchenWorkItem`
  /// callable (`KitchenActionGateway`) is the only path a transition takes,
  /// mirroring `KitchenDisplayBoardScreen._advanceLine`'s exact reasoning
  /// (the old local `TransitionKitchenWorkItem` use case's `save()` is a
  /// deliberate no-op once Firestore-backed — see
  /// `FirestoreKitchenWorkItemRepository`'s own doc comment). Previously
  /// this screen always used the local use case regardless of environment,
  /// so a staff member acting from the detail screen instead of the board
  /// never actually reached the server, and never propagated to KDS/the
  /// customer's live order tracking.
  Future<void> _transition(KitchenWorkItem item, KitchenLineStatus to,
      {String? reason}) async {
    if (ref.read(firebaseReadyProvider)) {
      try {
        final gateway = ref.read(kitchenActionGatewayProvider);
        final result = await gateway.transitionWorkItem(
          workItemId: item.id,
          to: to,
          expectedRevision: item.revision,
          reason: reason,
        );
        // 2026-11-08 — keeps the order's own status in step with this
        // line (never the rejected `confirmed -> ready` skip); see
        // `AdvanceKitchenOrder.syncOrderAfterLineTransition`.
        final ticket = _ticket;
        if (ticket != null) {
          await AdvanceKitchenOrder(gateway: gateway)
              .syncOrderAfterLineTransition(
            orderId: ticket.orderId.value,
            channel: ticket.header.channel,
            currentStatus: ticket.header.orderStatus,
            lineTarget: to,
            allSiblingsReady: result.allSiblingsReady,
          );
        }
        if (!mounted) return;
        setState(() => _message = null);
        await _load();
      } on KitchenActionException catch (e) {
        if (!mounted) return;
        setState(() => _message = e.message);
      }
      return;
    }

    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _message = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await TransitionKitchenWorkItem(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        projectionRepository: ref.read(kitchenProjectionRepositoryProvider),
        auditRepository: ref.read(kitchenAuditEntryRepositoryProvider),
        recordKitchenEvent: RecordKitchenEvent(
          idGenerator: ref.read(kitchenEventIdGeneratorProvider),
          eventRepository: ref.read(kitchenEventRepositoryProvider),
          eventPublisher: ref.read(kitchenEventPublisherProvider),
        ),
      )(
        workItemId: item.id,
        to: to,
        expectedRevision: item.revision,
        performedByStaffId: widget.performedByStaffId,
        deviceId: widget.deviceId,
        reason: reason,
      );
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  /// 2026-10-29 — the user-requested whole-order "İptal Et" action, next to
  /// the ready-progress summary (this screen's own "Hazır/Tamamla"
  /// indicator). 2026-11-08: no longer `dineInQr`-only — every channel
  /// with a staff cancellation callable (`KitchenOrderActionPolicy
  /// .canCancel`), dispatched by `KitchenActionGateway.cancelOrder`.
  Future<void> _cancelWholeOrder(KitchenTicket ticket) async {
    final reason = await showKitchenOrderCancelDialog(
      context,
      channel: ticket.header.channel,
    );
    if (reason == null || !mounted) return;

    try {
      await AdvanceKitchenOrder(
        gateway: ref.read(kitchenActionGatewayProvider),
      ).cancel(
        orderId: ticket.orderId.value,
        channel: ticket.header.channel,
        reasonCode: reason,
      );
      if (!mounted) return;
      setState(() => _message = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sipariş iptal edildi.')),
      );
      await _load();
    } on KitchenActionException catch (e) {
      if (!mounted) return;
      setState(() => _message = e.message);
    }
  }

  Future<void> _promptReasonThenTransition(
      KitchenWorkItem item, KitchenLineStatus to, String title) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Sebep'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
    if (reason == null) return;
    await _transition(item, to, reason: reason);
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;
    final items = _workItems;
    final view = ticket == null || items == null
        ? null
        : KitchenOrderView.build(
            orderId: ticket.orderId,
            kitchenTicketId: ticket.id,
            workItems: items,
          );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(ticket?.header.orderNumber ?? 'Sipariş Detayı'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: !_loadAttempted
            ? const LoadingView(message: 'Detaylar yükleniyor...')
            : (ticket == null || items == null || view == null)
                ? EmptyView(
                    icon: Icons.receipt_long_outlined,
                    message: _loadError ?? 'Sipariş bulunamadı.',
                  )
                : _loadError != null
                    ? ErrorView(
                        message: _loadError!,
                        retryLabel: 'Tekrar Dene',
                        onRetry: _load,
                      )
                    : ListView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        children: [
                          Text(ticket.header.channelLabel,
                              style: AppTypography.bodyMedium
                                  .copyWith(color: AppColors.textSecondary)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                view.isFullyReady
                                    ? 'Sipariş hazır'
                                    : '${items.where((i) => i.status == KitchenLineStatus.ready).length}/${items.length} hazır',
                                style: AppTypography.bodyLarge.copyWith(
                                  color: view.isFullyReady
                                      ? AppColors.success
                                      : AppColors.textPrimary,
                                ),
                              ),
                              if (KitchenOrderActionPolicy.canCancel(
                                  ticket.header.channel,
                                  ticket.header.orderStatus))
                                OutlinedButton(
                                  onPressed: () => _cancelWholeOrder(ticket),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    side: const BorderSide(
                                        color: AppColors.error),
                                  ),
                                  child: const Text('Siparişi İptal Et'),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          if (_message != null)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: Text(_message!,
                                  style: AppTypography.bodySmall
                                      .copyWith(color: AppColors.error)),
                            ),
                          for (final item in items)
                            _WorkItemDetailCard(
                              item: item,
                              line: ticket.lines.firstWhere(
                                (l) => l.id == item.kitchenTicketLineId,
                                orElse: () => KitchenTicketLine(
                                  id: item.kitchenTicketLineId,
                                  productName: '(bilinmiyor)',
                                  quantity: item.quantity,
                                ),
                              ),
                              nextStatus:
                                  KitchenOrderCard.nextStatus(item.status),
                              onAdvance: (to) => _transition(item, to),
                              onCancel: () => _promptReasonThenTransition(
                                  item,
                                  KitchenLineStatus.cancelled,
                                  'Satırı İptal Et'),
                              onRecall: item.status == KitchenLineStatus.ready
                                  ? () => _promptReasonThenTransition(item,
                                      KitchenLineStatus.recalled, 'Geri Çağır')
                                  : null,
                            ),
                        ],
                      ),
      ),
    );
  }
}

class _WorkItemDetailCard extends StatelessWidget {
  const _WorkItemDetailCard({
    required this.item,
    required this.line,
    required this.nextStatus,
    required this.onAdvance,
    required this.onCancel,
    this.onRecall,
  });

  final KitchenWorkItem item;
  final KitchenTicketLine line;
  final KitchenLineStatus? nextStatus;
  final ValueChanged<KitchenLineStatus> onAdvance;
  final VoidCallback onCancel;
  final VoidCallback? onRecall;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${line.quantityLabel} ${line.productName}',
              style: AppTypography.bodyLarge),
          for (final ingredient in line.ingredientSummary)
            Text('- $ingredient',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
          for (final warning in line.warnings)
            Text('⚠ $warning',
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.error)),
          if (line.note.isNotEmpty)
            Text(line.note,
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.warning)),
          const SizedBox(height: AppSpacing.sm),
          Text(
              'Durum: ${item.status.name} (${item.readyQuantity}/${item.quantity})',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              if (nextStatus != null)
                ElevatedButton(
                  onPressed: () => onAdvance(nextStatus!),
                  child: Text(nextStatus == KitchenLineStatus.ready
                      ? 'Hazır'
                      : 'İlerlet'),
                ),
              if (item.status != KitchenLineStatus.cancelled &&
                  item.status != KitchenLineStatus.unavailable &&
                  item.status != KitchenLineStatus.ready)
                OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('İptal Et'),
                ),
              if (onRecall != null)
                OutlinedButton(
                  onPressed: onRecall,
                  child: const Text('Geri Çağır'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
