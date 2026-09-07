import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/enqueue_kitchen_work_items.dart';
import '../../application/use_cases/record_kitchen_event.dart';
import '../../application/use_cases/transition_kitchen_work_item.dart';
import '../../data/kitchen_action_gateway.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/kds/kitchen_delay_state.dart';
import '../../domain/kds/kitchen_line_status.dart';
import '../../domain/kds/kitchen_station.dart';
import '../../domain/kds/kitchen_synchronization_state.dart';
import '../../domain/kds/kitchen_work_item.dart';
import '../../domain/kitchen/kitchen_ticket.dart';
import '../../domain/kitchen/kitchen_ticket_line.dart';
import '../providers/kds_dependencies_provider.dart';
import '../providers/kitchen_ticket_dependencies_provider.dart';
import '../../../printing/data/print_job_action_gateway.dart';
import '../../../printing/domain/print_job.dart';
import 'delayed_orders_screen.dart';
import 'kitchen_completed_history_screen.dart';
import 'kitchen_order_details_screen.dart';

/// The default Phase 4 delay thresholds — 10 minutes warning, 20 minutes
/// critical, no per-channel override. Branch-configurable in principle
/// (`KitchenDelayThresholds`); this is the seam's default value, not a
/// hardcoded business rule.
const _defaultThresholds = KitchenDelayThresholds(
  warningThreshold: Duration(minutes: 10),
  criticalThreshold: Duration(minutes: 20),
);

/// AP-5 Sprint 4 — the board's status filter tabs (Tümü/Bekleyen/
/// Hazırlanıyor/Geciken/Hazır), a second, additive filter dimension on top
/// of [_StationFilterBar]'s existing station chips — filtering happens
/// purely client-side over the already-fetched work items, the same way
/// the station filter already narrows what's visible once a ticket has no
/// matching items left (`_buildBoard`'s `visibleTickets`).
enum _KdsStatusFilter { all, pending, preparing, delayed, ready }

const _kdsStatusFilterLabels = {
  _KdsStatusFilter.all: 'Tümü',
  _KdsStatusFilter.pending: 'Bekleyen',
  _KdsStatusFilter.preparing: 'Hazırlanıyor',
  _KdsStatusFilter.delayed: 'Geciken',
  _KdsStatusFilter.ready: 'Hazır',
};

/// `HH:mm`, no `intl` dependency (none exists in `pubspec.yaml` yet) — a
/// tiny, local, presentation-only helper, not a central formatter, since
/// this is its only use site.
String _formatClockTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// The main real-time KDS board — every active [KitchenWorkItem] for a
/// branch, grouped by [KitchenTicket], with a functional station filter
/// (Phase 3 Sprint 3D shipped these chips permanently disabled; Phase 4
/// makes them real), a device sync/connection indicator, and a full-
/// screen second-monitor-mode toggle foundation.
///
/// [authorizationPolicy] is nullable, matching every other Phase 3/4
/// screen's precedent — actions check for one at call time.
class KitchenDisplayBoardScreen extends ConsumerStatefulWidget {
  const KitchenDisplayBoardScreen({
    super.key,
    required this.branchId,
    this.deviceId,
    this.authorizationPolicy,
    this.performedByStaffId = 'staff-1',
  });

  final String branchId;
  final String? deviceId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<KitchenDisplayBoardScreen> createState() =>
      _KitchenDisplayBoardScreenState();
}

class _KitchenDisplayBoardScreenState
    extends ConsumerState<KitchenDisplayBoardScreen> {
  List<KitchenTicket>? _tickets;
  Map<String, List<KitchenWorkItem>>? _workItemsByTicketId;
  KitchenSynchronizationState? _syncState;
  DateTime? _now;
  KitchenStation? _selectedStation;
  _KdsStatusFilter _statusFilter = _KdsStatusFilter.all;
  bool _isFullscreen = false;
  String? _message;
  StreamSubscription<List<KitchenTicket>>? _ticketSubscription;

  /// Faz R.3C.2 — set when the repository denies this staff member access
  /// to [widget.branchId] (`firestore.rules`' `hasBranchAccess`, not the
  /// client-side `branchId` filter — see `FirestoreKitchenTicketRepository`
  /// 's own doc comment). Fail-closed UX: the board never keeps trying to
  /// render stale/partial data once this is true.
  bool _accessDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    // Faz R.3C: subscribe to the repository's live ticket stream so a
    // reservation-preorder release (or any other order reaching a
    // kitchen-eligible status) refreshes the board with no manual
    // reload/app restart — `_load()`'s own enqueue step is idempotent per
    // (ticket, line), so a redundant emission is harmless, and this is the
    // one board-data reload path every existing action in this screen
    // already reuses, not a parallel one.
    _ticketSubscription = ref
        .read(kitchenTicketRepositoryProvider)
        .watchActiveByBranch(widget.branchId)
        .listen((_) => _load(), onError: _handleLoadError);
  }

  @override
  void dispose() {
    _ticketSubscription?.cancel();
    super.dispose();
  }

  void _handleLoadError(Object error) {
    if (!mounted) return;
    if (error is fs.FirebaseException && error.code == 'permission-denied') {
      setState(() {
        _accessDenied = true;
        _tickets = null;
        _workItemsByTicketId = null;
      });
      return;
    }
    setState(() => _message = 'Mutfak ekranı yüklenirken bir sorun oluştu.');
  }

  Future<void> _load() async {
    final clock = ref.read(clockProvider);
    final List<KitchenTicket> tickets;
    try {
      tickets = await ref
          .read(kitchenTicketRepositoryProvider)
          .findActiveByBranch(widget.branchId);
    } catch (error) {
      _handleLoadError(error);
      return;
    }

    final enqueue = EnqueueKitchenWorkItems(
      clock: clock,
      idGenerator: ref.read(kitchenWorkItemIdGeneratorProvider),
      projectionRepository: ref.read(kitchenProjectionRepositoryProvider),
      routingRuleRepository: ref.read(kitchenRoutingRuleRepositoryProvider),
      recordKitchenEvent: RecordKitchenEvent(
        idGenerator: ref.read(kitchenEventIdGeneratorProvider),
        eventRepository: ref.read(kitchenEventRepositoryProvider),
        eventPublisher: ref.read(kitchenEventPublisherProvider),
      ),
    );
    for (final ticket in tickets) {
      await enqueue(ticket: ticket);
    }

    final workItems =
        await ref.read(kitchenProjectionRepositoryProvider).findByBranch(
              branchId: widget.branchId,
              stationName: _selectedStation?.name,
            );
    final grouped = <String, List<KitchenWorkItem>>{};
    for (final item in workItems) {
      grouped.putIfAbsent(item.kitchenTicketId, () => []).add(item);
    }

    KitchenSynchronizationState? syncState;
    final deviceId = widget.deviceId;
    if (deviceId != null) {
      syncState = await ref
          .read(kitchenSynchronizationServiceProvider)
          .currentState(deviceId: deviceId, branchId: widget.branchId);
    }

    if (!mounted) return;
    setState(() {
      _accessDenied = false;
      _tickets = tickets;
      _workItemsByTicketId = grouped;
      _syncState = syncState;
      _now = clock.now();
    });
  }

  Future<void> _resync() async {
    final deviceId = widget.deviceId;
    if (deviceId == null) return;
    await ref.read(kitchenSynchronizationServiceProvider).synchronize(
          deviceId: deviceId,
          branchId: widget.branchId,
        );
    await _load();
  }

  /// AP-5 Sprint 4 — applies [_statusFilter] to one ticket's work items.
  /// `delayed` cuts across [KitchenLineStatus] values (any item currently
  /// warning/critical per [KitchenDelayState]) rather than being a status
  /// value itself, so it's computed here instead of matched against
  /// `item.status` like the other tabs.
  List<KitchenWorkItem> _filterItemsByStatus(
    KitchenTicket ticket,
    List<KitchenWorkItem> items,
    DateTime now,
  ) {
    if (_statusFilter == _KdsStatusFilter.all) return items;
    return items.where((item) {
      switch (_statusFilter) {
        case _KdsStatusFilter.all:
          return true;
        case _KdsStatusFilter.pending:
          return item.status == KitchenLineStatus.queued ||
              item.status == KitchenLineStatus.acknowledged;
        case _KdsStatusFilter.preparing:
          return item.status == KitchenLineStatus.preparing ||
              item.status == KitchenLineStatus.recalled;
        case _KdsStatusFilter.ready:
          return item.status == KitchenLineStatus.ready;
        case _KdsStatusFilter.delayed:
          final delay = KitchenDelayState.compute(
            workItemId: item.id,
            queuedAt: item.queuedAt,
            preparingStartedAt: item.preparingStartedAt,
            readyAt: item.readyAt,
            now: now,
            thresholds: _defaultThresholds,
            channelName: ticket.header.orderTypeLabel,
          );
          return delay.isWarning || delay.isCritical;
      }
    }).toList();
  }

  /// AP-5 Sprint 4 — "Fiş Yazdır / Tekrar Yazdır" from a kitchen card.
  /// Always the shared station (V1 default — see `acceptOrderLine.ts`'s
  /// `stationForLine`); [isCopy] is true only for an explicit reprint of an
  /// already-fired ticket, mirroring `KitchenTicket.isCopy`.
  Future<void> _requestPrint(KitchenTicket ticket, {bool isCopy = false}) async {
    if (!ref.read(firebaseReadyProvider)) {
      setState(() => _message = 'Yazdırma servisi şu anda kullanılamıyor.');
      return;
    }
    try {
      final result =
          await ref.read(printJobActionGatewayProvider).requestPrintJob(
                orderId: ticket.orderId.value,
                stationId: 'shared',
                isCopy: isCopy,
              );
      if (!mounted) return;
      setState(() {
        _message = result.status == PrintJobStatus.success
            ? 'Fiş yazdırıldı.'
            : 'Fiş yazdırılamadı — yazıcı bağlı değil.';
      });
    } on PrintJobActionException catch (e) {
      if (!mounted) return;
      setState(() => _message = e.message);
    }
  }

  /// AP-5 Sprint 1: once Firebase is ready, the real
  /// `transitionKitchenWorkItem` callable (`KitchenActionGateway`) is the
  /// only path a transition takes — `TransitionKitchenWorkItem`'s local
  /// use case now sits behind a Firestore-backed
  /// `kitchenProjectionRepositoryProvider` whose `save()` is a deliberate
  /// no-op (see `FirestoreKitchenWorkItemRepository`'s doc comment), so
  /// calling it directly here would silently stop persisting anything the
  /// moment Firebase becomes ready. When the callable reports
  /// `allSiblingsReady`, this also advances the canonical order's own
  /// status via the already-real, already-tested `advance*OrderStatus`
  /// callable for that order's channel — closing the confirmed AP-0/AP-1
  /// gap where the board never called it at all.
  Future<void> _advanceLine(KitchenWorkItem item, KitchenLineStatus to) async {
    if (ref.read(firebaseReadyProvider)) {
      try {
        final gateway = ref.read(kitchenActionGatewayProvider);
        final result = await gateway.transitionWorkItem(
          workItemId: item.id,
          to: to,
          expectedRevision: item.revision,
        );
        final orderId = result.orderId;
        final orderChannel = result.orderChannel;
        if (result.allSiblingsReady &&
            orderId != null &&
            orderChannel != null) {
          await gateway.advanceOrderStatus(
            orderId: orderId,
            channel: orderChannel,
            targetStatus: 'ready',
          );
        }
        setState(() => _message = null);
        await _load();
      } on KitchenActionException catch (e) {
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
      );
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tickets = _tickets;
    final grouped = _workItemsByTicketId;
    final now = _now ?? DateTime.now();

    final board = SafeArea(
      child: _accessDenied
          ? ErrorView(
              message: 'Bu şube için mutfak ekranı erişim yetkiniz yok.',
              retryLabel: 'Tekrar Dene',
              onRetry: _load,
            )
          : tickets == null || grouped == null
              ? const LoadingView(message: 'Mutfak ekranı yükleniyor...')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StationFilterBar(
                      selected: _selectedStation,
                      onSelected: (station) {
                        setState(() => _selectedStation = station);
                        _load();
                      },
                    ),
                    _StatusFilterBar(
                      selected: _statusFilter,
                      onSelected: (filter) =>
                          setState(() => _statusFilter = filter),
                    ),
                    if (widget.deviceId != null)
                      _SyncStatusBar(state: _syncState, onResync: _resync),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                        child: Text(_message!,
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.error)),
                      ),
                    Expanded(
                      child: _buildBoard(tickets, grouped, now),
                    ),
                  ],
                ),
    );

    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            board,
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: IconButton(
                icon: const Icon(Icons.fullscreen_exit),
                tooltip: 'Tam Ekrandan Çık',
                onPressed: () => setState(() => _isFullscreen = false),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mutfak Ekranı'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Tamamlanan Geçmişi',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    KitchenCompletedHistoryScreen(branchId: widget.branchId),
              ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.warning_amber_outlined),
            tooltip: 'Geciken Siparişler',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DelayedOrdersScreen(branchId: widget.branchId),
              ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: 'Tam Ekran',
            onPressed: () => setState(() => _isFullscreen = true),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _load,
          ),
        ],
      ),
      body: board,
    );
  }

  Widget _buildBoard(
    List<KitchenTicket> tickets,
    Map<String, List<KitchenWorkItem>> grouped,
    DateTime now,
  ) {
    final filteredByTicket = <String, List<KitchenWorkItem>>{
      for (final ticket in tickets)
        ticket.id: _filterItemsByStatus(
          ticket,
          grouped[ticket.id] ?? const [],
          now,
        ),
    };
    final visibleTickets = tickets
        .where((t) => (filteredByTicket[t.id] ?? const []).isNotEmpty)
        .toList();

    if (visibleTickets.isEmpty) {
      return const EmptyView(
        icon: Icons.receipt_long_outlined,
        message: 'Bekleyen sipariş yok',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.75,
      ),
      itemCount: visibleTickets.length,
      itemBuilder: (context, index) {
        final ticket = visibleTickets[index];
        final items = filteredByTicket[ticket.id] ?? const [];
        return KitchenOrderCard(
          ticket: ticket,
          workItems: items,
          now: now,
          thresholds: _defaultThresholds,
          onLineTap: _advanceLine,
          // Manual print from the KDS card is always a reprint: the
          // automatic job already fired at order acceptance (Sprint 4's
          // `requestPrintJobForAcceptance` server-side hook) by the time a
          // ticket is visible here at all.
          onPrintRequested: () => _requestPrint(ticket, isCopy: true),
          onOpenDetails: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => KitchenOrderDetailsScreen(
                kitchenTicketId: ticket.id,
                authorizationPolicy: widget.authorizationPolicy,
                deviceId: widget.deviceId,
                performedByStaffId: widget.performedByStaffId,
              ),
            ));
          },
        );
      },
    );
  }
}

class _StationFilterBar extends StatelessWidget {
  const _StationFilterBar({required this.selected, required this.onSelected});

  final KitchenStation? selected;
  final ValueChanged<KitchenStation?> onSelected;

  static const _labels = {
    null: 'Tümü',
    KitchenStation.hot: 'Sıcak',
    KitchenStation.cold: 'Soğuk',
    KitchenStation.beverage: 'İçecek',
    KitchenStation.dessert: 'Tatlı',
    KitchenStation.packing: 'Paketleme',
    KitchenStation.shared: 'Ortak',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.xs,
        children: [
          for (final entry in _labels.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: selected == entry.key,
              onSelected: (_) => onSelected(entry.key),
            ),
        ],
      ),
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.selected, required this.onSelected});

  final _KdsStatusFilter selected;
  final ValueChanged<_KdsStatusFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xs,
        children: [
          for (final entry in _kdsStatusFilterLabels.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: selected == entry.key,
              onSelected: (_) => onSelected(entry.key),
            ),
        ],
      ),
    );
  }
}

class _SyncStatusBar extends StatelessWidget {
  const _SyncStatusBar({required this.state, required this.onResync});

  final KitchenSynchronizationState? state;
  final VoidCallback onResync;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final isSynced = s?.isSynchronized ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Icon(
            isSynced ? Icons.cloud_done_outlined : Icons.cloud_sync_outlined,
            size: 16,
            color: isSynced ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            isSynced
                ? 'Senkronize'
                : '${s?.pendingEventCount ?? 0} bekleyen olay',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          if (!isSynced)
            TextButton(
                onPressed: onResync, child: const Text('Yeniden Bağlan')),
        ],
      ),
    );
  }
}

/// One order's board card — every [KitchenWorkItem] for the ticket, each
/// tappable to advance to its next natural [KitchenLineStatus].
class KitchenOrderCard extends StatelessWidget {
  const KitchenOrderCard({
    super.key,
    required this.ticket,
    required this.workItems,
    required this.now,
    required this.thresholds,
    required this.onLineTap,
    required this.onOpenDetails,
    required this.onPrintRequested,
  });

  final KitchenTicket ticket;
  final List<KitchenWorkItem> workItems;
  final DateTime now;
  final KitchenDelayThresholds thresholds;
  final void Function(KitchenWorkItem item, KitchenLineStatus to) onLineTap;
  final VoidCallback onOpenDetails;
  final VoidCallback onPrintRequested;

  static KitchenLineStatus? nextStatus(KitchenLineStatus current) {
    switch (current) {
      case KitchenLineStatus.queued:
        return KitchenLineStatus.acknowledged;
      case KitchenLineStatus.acknowledged:
        return KitchenLineStatus.preparing;
      case KitchenLineStatus.preparing:
        return KitchenLineStatus.ready;
      case KitchenLineStatus.recalled:
        return KitchenLineStatus.preparing;
      case KitchenLineStatus.ready:
      case KitchenLineStatus.cancelled:
      case KitchenLineStatus.unavailable:
      case KitchenLineStatus.wasted:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final worstDelay = workItems
        .map((item) => KitchenDelayState.compute(
              workItemId: item.id,
              queuedAt: item.queuedAt,
              preparingStartedAt: item.preparingStartedAt,
              readyAt: item.readyAt,
              now: now,
              thresholds: thresholds,
              channelName: ticket.header.orderTypeLabel,
            ))
        .fold<KitchenDelayState?>(null, (worst, state) {
      if (worst == null) return state;
      return state.totalDuration > worst.totalDuration ? state : worst;
    });
    final isCritical = worstDelay?.isCritical ?? false;
    final isWarning = worstDelay?.isWarning ?? false;
    final allReady = workItems.every((i) =>
        i.status == KitchenLineStatus.ready ||
        i.status == KitchenLineStatus.cancelled ||
        i.status == KitchenLineStatus.unavailable ||
        i.status == KitchenLineStatus.wasted);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderColor: isCritical
          ? AppColors.error
          : isWarning
              ? AppColors.warning
              : null,
      child: InkWell(
        onTap: onOpenDetails,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(ticket.header.orderNumber,
                      style: AppTypography.bodyLarge,
                      overflow: TextOverflow.ellipsis),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${worstDelay?.totalDuration.inMinutes ?? 0}dk',
                      style: AppTypography.bodySmall.copyWith(
                        color: isCritical
                            ? AppColors.error
                            : isWarning
                                ? AppColors.warning
                                : AppColors.textSecondary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.print_outlined, size: 18),
                      tooltip: 'Fiş Yazdır / Tekrar Yazdır',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onPrintRequested,
                    ),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _ChannelBadge(label: ticket.header.channelLabel),
                  if (ticket.header.tableLabel != null)
                    Text(ticket.header.tableLabel!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textPrimary)),
                  if (ticket.header.customerName != null)
                    Text(ticket.header.customerName!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textPrimary)),
                  Text(_formatClockTime(ticket.header.receivedAt),
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final item in workItems)
                    _WorkItemTile(
                      item: item,
                      line: ticket.lines.firstWhere(
                        (l) => l.id == item.kitchenTicketLineId,
                        orElse: () => KitchenTicketLine(
                          id: item.kitchenTicketLineId,
                          productName: '(bilinmiyor)',
                          quantity: item.quantity,
                        ),
                      ),
                      onTap: () {
                        final next = nextStatus(item.status);
                        if (next != null) onLineTap(item, next);
                      },
                    ),
                ],
              ),
            ),
            if (allReady)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  borderRadius: AppRadius.kSmall,
                ),
                alignment: Alignment.center,
                child: Text('HAZIR',
                    style: AppTypography.labelLarge
                        .copyWith(color: AppColors.onPrimary)),
              ),
          ],
        ),
      ),
    );
  }
}

/// AP-5 Sprint 4 — a colored channel-type chip (QR/Kasiyer/Gel-Al/Teslimat/
/// Rezervasyon), replacing the plain-text channel label. Colors come
/// entirely from the existing `AppColors` semantic palette (no new tokens
/// added — see this sprint's own §6 mandate); an unrecognized label (e.g.
/// a future marketplace channel not yet modeled in `OrderChannel`) falls
/// back to [AppColors.textSecondary] rather than guessing.
class _ChannelBadge extends StatelessWidget {
  const _ChannelBadge({required this.label});

  final String label;

  static const _colorsByLabel = {
    'Masa (QR)': AppColors.primary,
    'Masa': AppColors.primaryLight,
    'Gel-Al': AppColors.accent,
    'Teslimat': AppColors.info,
    'Rezervasyon Ön Sipariş': AppColors.secondary,
  };

  @override
  Widget build(BuildContext context) {
    final color = _colorsByLabel[label] ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: color, borderRadius: AppRadius.kPill),
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(
          color: AppColors.onPrimary,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// AP-5 Sprint 4 — an explicit visual badge for the terminal `wasted`
/// status (distinct from every other status, which stays a plain text
/// label per this sprint's targeted ask), so a wasted line is unmistakable
/// at a glance rather than reading like any other status word.
class _WastedBadge extends StatelessWidget {
  const _WastedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: const BoxDecoration(
        color: AppColors.error,
        borderRadius: AppRadius.kSmall,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_outlined,
              size: 14, color: AppColors.onPrimary),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text('Fireye Ayrıldı',
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.onPrimary)),
          ),
        ],
      ),
    );
  }
}

class _WorkItemTile extends StatelessWidget {
  const _WorkItemTile({
    required this.item,
    required this.line,
    required this.onTap,
  });

  final KitchenWorkItem item;
  final KitchenTicketLine line;
  final VoidCallback onTap;

  static const _statusLabels = {
    KitchenLineStatus.queued: 'Sırada',
    KitchenLineStatus.acknowledged: 'Görüldü',
    KitchenLineStatus.preparing: 'Hazırlanıyor',
    KitchenLineStatus.ready: 'Hazır',
    KitchenLineStatus.cancelled: 'İptal',
    KitchenLineStatus.unavailable: 'Yok',
    KitchenLineStatus.recalled: 'Geri Çağrıldı',
    KitchenLineStatus.wasted: 'Fireye Ayrıldı',
  };

  @override
  Widget build(BuildContext context) {
    final isReady = item.status == KitchenLineStatus.ready;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isReady ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: isReady ? AppColors.success : AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${line.quantity}x ${line.productName}',
                    style: AppTypography.bodyMedium.copyWith(
                      decoration: isReady ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  for (final warning in line.warnings)
                    Text('⚠ $warning',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.error)),
                  if (line.note.isNotEmpty)
                    Text(line.note,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.warning)),
                  const SizedBox(height: AppSpacing.xs),
                  if (item.status == KitchenLineStatus.wasted)
                    const _WastedBadge()
                  else
                    Text(
                      _statusLabels[item.status] ?? item.status.name,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
