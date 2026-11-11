import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/logging/log_level.dart';
import '../../../../core/services/logging/logging_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../admin/application/use_cases/trusted_device_session_controller.dart';
import '../../../admin/presentation/providers/admin_context_provider.dart';
import '../../../admin/presentation/providers/admin_dependencies_provider.dart';
import '../../../admin/presentation/providers/trusted_device_session_providers.dart';
import '../../../admin/presentation/screens/trusted_device_status_screen.dart';
import '../../data/pos_action_gateway.dart';
import '../../data/pos_operational_view_gateway.dart';
import '../providers/pos_workspace_providers.dart';
import '../widgets/pos_operational_rail.dart';
import '../widgets/pos_table_top_view.dart';
import '../widgets/print_table_receipt_action.dart';
import 'end_of_day_screen.dart';
import 'pos_cash_register_screen.dart';
import 'pos_checkout_screen.dart';
import 'pos_table_workspace_screen.dart';
import 'pos_takeaway_orders_screen.dart';

/// Masalar grid'inin bölge filtresi (2026-11-06) — `RestaurantTable
/// .areaName`'in zaten taşıdığı serbest metni kullanır, yeni bir alan
/// değil. 2026-11-11 — "Teras" sekmesi kaldırıldı (açılış düzeninde teras
/// masası yok: Salon 1–6 / Bahçe 1–6). [takeaway] gerçek bir masa/alan değil — bu ekranın bugünkü veri
/// modelinde paket/gel-al siparişleri için ayrı bir sorgu/kart tasarımı
/// yok; seçildiğinde bunu açıkça gösteren bir yer tutucu render edilir,
/// asla sessizce boş/yanlış bir masa listesi değil.
enum _AreaTab {
  all('Tümü'),
  garden('Bahçe'),
  hall('Salon'),
  takeaway('Paket / Gel-Al');

  const _AreaTab(this.label);
  final String label;
}

/// The real POS branch/table overview — AP-3 continuation (`docs/decisions
/// .md` ADR-041's own "no longer blocked" follow-up). Consumes the real
/// device-gated `getPosBranchTableOverview` backend; renders nothing at
/// all, redirecting to [TrustedDeviceStatusScreen] instead, until a real
/// trusted-device session exists — there is no code path here that could
/// show table data without one.
///
/// Dark Abaküs-green left operational rail, cream central workspace — the
/// existing design-system tokens only (`AppColors.primary`/`.background`),
/// no invented colors.
class PosBranchOverviewScreen extends ConsumerStatefulWidget {
  const PosBranchOverviewScreen({super.key});

  @override
  ConsumerState<PosBranchOverviewScreen> createState() =>
      _PosBranchOverviewScreenState();
}

class _PosBranchOverviewScreenState
    extends ConsumerState<PosBranchOverviewScreen> {
  static const _pollInterval = Duration(seconds: 8);
  Timer? _timer;

  List<PosBranchTableSummary>? _tables;
  String? _version;
  Object? _error;
  _AreaTab _selectedAreaTab = _AreaTab.all;

  /// 2026-11-11 — set while staff pick the target table for a whole-table
  /// move started from the table workspace's "Taşı" button.
  PosTableMoveRequest? _moveRequest;
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensureBranchSelected();
      await _load();
    });
    _timer = Timer.periodic(_pollInterval, (_) => _load(poll: true));
  }

  /// Defaults [selectedPosBranchIdProvider] to the signed-in staff actor's
  /// first accessible branch under the current organization — a real
  /// picker for a genuinely multi-branch actor is later, out-of-scope
  /// polish; this is the honest minimum so the trusted-device flow has a
  /// real branch to register against without the operator needing to
  /// configure anything by hand first.
  Future<void> _ensureBranchSelected() async {
    if (ref.read(selectedPosBranchIdProvider) != null) return;
    try {
      final accesses = await ref.read(typedActorContextProvider.future);
      final organizationId = ref.read(currentOrganizationIdProvider);
      final match = accesses.where((a) => a.organizationId == organizationId);
      if (match.isEmpty || match.first.branchIds.isEmpty) return;
      if (!mounted) return;
      ref.read(selectedPosBranchIdProvider.notifier).state =
          match.first.branchIds.first;
    } catch (_) {
      // Left unselected — the branch-selection-required fallback state
      // handles this honestly rather than throwing.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Self-Order QR Faz 5 (23-rule plan §6) — "POS zili": the sum of every
  /// table's own `pendingQrLineCount` (orders awaiting the approval queue)
  /// and `pendingServiceRequests` (çağrı butonları) — a single, generic
  /// "needs staff attention" count this screen already has both halves of.
  int _totalPendingAttentionCount(List<PosBranchTableSummary> tables) {
    return tables.fold(
      0,
      (sum, table) =>
          sum + table.pendingQrLineCount + table.pendingServiceRequests.length,
    );
  }

  /// [afterSessionRecovery] — this load is the single retry right after a
  /// rejected device session was replaced; never recovers a second time,
  /// so a server that keeps rejecting cannot loop.
  Future<void> _load({
    bool poll = false,
    bool afterSessionRecovery = false,
  }) async {
    final ctx = ref.read(posDeviceContextProvider);
    if (ctx == null) return;
    if (!poll) setState(() => _error = null);
    try {
      final gateway = ref.read(posOperationalViewGatewayProvider);
      final page = await gateway.getBranchOverview(
        organizationId: ctx.organizationId,
        branchId: ctx.branchId,
        deviceId: ctx.deviceId,
        deviceSessionId: ctx.deviceSessionId,
        ifNoneMatchVersion: poll ? _version : null,
      );
      if (!mounted) return;
      if (page.unchanged) {
        return; // nothing changed — skip a redundant re-render.
      }
      // A higher total than last time means something NEW arrived (a
      // fresh QR order line or a fresh çağrı), not just an existing one
      // being resolved — only that case rings the bell. `_tables == null`
      // (this screen's very first load) never dings — there is nothing
      // to compare the initial snapshot against.
      final previousCount =
          _tables == null ? null : _totalPendingAttentionCount(_tables!);
      final newCount = _totalPendingAttentionCount(page.tables);
      if (previousCount != null && newCount > previousCount) {
        SystemSound.play(SystemSoundType.alert);
      }
      setState(() {
        _tables = page.tables;
        _version = page.version;
        _error = null;
      });
    } catch (e) {
      // 2026-11-10 — the server no longer knows this device session (data
      // reset, expired or deactivated server-side) while the local cache
      // still says it is valid: get a fresh session with the same device
      // key and retry once. This screen stays mounted (and keeps polling)
      // under every POS screen pushed on top of it, so this recovers the
      // whole POS within one poll interval.
      if (!afterSessionRecovery &&
          mounted &&
          e is PosOperationalViewException &&
          TrustedDeviceSessionController.isRecoverableSessionRejection(
            code: e.code,
            message: e.message,
          )) {
        final args = ref.read(currentTrustedDeviceSessionControllerProvider);
        if (args != null) {
          final recovered = await ref
              .read(trustedDeviceSessionControllerProvider(args).notifier)
              .recoverFromRejectedSession(ctx.deviceSessionId);
          if (recovered && mounted) {
            await _load(poll: poll, afterSessionRecovery: true);
            return;
          }
        }
      }
      if (!mounted || poll) {
        return; // a background poll failure never clobbers an already-shown list.
      }
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = ref.watch(posDeviceContextProvider);
    if (ctx == null) {
      return const TrustedDeviceStatusScreen(capabilities: ['POS']);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            PosOperationalRail(
              onCashRegister: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const PosCashRegisterScreen()),
              ),
              onEndOfDay: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EndOfDayScreen()),
              ),
            ),
            Expanded(child: _buildContent(ctx)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(PosDeviceContext ctx) {
    final error = _error;
    final tables = _tables;
    if (error != null && tables == null) {
      return ErrorView(
        message: 'Şube masaları yüklenirken bir sorun oluştu.',
        retryLabel: 'Tekrar Dene',
        onRetry: () => _load(),
      );
    }
    if (tables == null) {
      return const LoadingView(message: 'Masalar yükleniyor...');
    }
    if (tables.isEmpty) {
      return const EmptyView(
        icon: Icons.table_restaurant_outlined,
        message: 'Bu şubede kayıtlı masa yok.',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final tab in _AreaTab.values)
                  ChoiceChip(
                    label: Text(tab.label),
                    selected: _selectedAreaTab == tab,
                    onSelected: (_) => setState(() => _selectedAreaTab = tab),
                  ),
              ],
            ),
          ),
        ),
        if (_moveRequest != null) _buildMoveBanner(tables),
        Expanded(child: _buildTableGrid(tables, ctx)),
      ],
    );
  }

  String _tableName(List<PosBranchTableSummary> tables, String tableId) {
    for (final table in tables) {
      if (table.tableId == tableId) return table.displayName;
    }
    return tableId;
  }

  Widget _buildMoveBanner(List<PosBranchTableSummary> tables) {
    final request = _moveRequest!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
      child: Container(
        key: const Key('tableMoveBanner'),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.14),
          border: Border.all(color: AppColors.warning),
          borderRadius: AppRadius.kMedium,
        ),
        child: Row(
          children: [
            const Icon(Icons.table_restaurant, color: AppColors.warning),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${_tableName(tables, request.sourceTableId)} taşınıyor — '
                'hedef masayı seçin.',
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            if (_moving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: SizedBox.square(
                  dimension: AppSpacing.lg,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            TextButton(
              onPressed:
                  _moving ? null : () => setState(() => _moveRequest = null),
              child: const Text('Vazgeç'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTable(PosBranchTableSummary table) async {
    if (_moveRequest != null) {
      await _completeMove(table);
      return;
    }
    ref.read(selectedPosTableIdProvider.notifier).state = table.tableId;
    final result = await Navigator.of(context).push<PosTableMoveRequest>(
      MaterialPageRoute(builder: (_) => const PosTableWorkspaceScreen()),
    );
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _moveRequest = result;
        _selectedAreaTab = _AreaTab.all;
      });
    }
    await _load();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 2026-11-11 — a free target gets the whole session
  /// (`transferTableSession`); an occupied one can only be merged into
  /// (`mergeTableSessions` — the server refuses a transfer onto a table with
  /// its own session), after an explicit confirmation.
  Future<void> _completeMove(PosBranchTableSummary target) async {
    final request = _moveRequest;
    final ctx = ref.read(posDeviceContextProvider);
    if (request == null || ctx == null || _moving) return;
    if (target.tableId == request.sourceTableId) {
      _showSnack('Taşınan masanın kendisi hedef olamaz.');
      return;
    }
    if (target.status == 'disabled') {
      _showSnack('Kapalı bir masaya taşınamaz.');
      return;
    }
    final tables = _tables ?? const <PosBranchTableSummary>[];
    final sourceName = _tableName(tables, request.sourceTableId);
    final merge = target.activeTableSessionId != null;
    if (merge) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Birleştirilsin mi?'),
          content: Text(
            '${target.displayName} dolu. $sourceName adisyonu '
            '${target.displayName} adisyonuyla birleştirilecek.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Birleştir'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _moving = true);
    try {
      final gateway = ref.read(posActionGatewayProvider);
      if (merge) {
        await gateway.mergeTables(
          ctx: ctx,
          sourceTableId: request.sourceTableId,
          targetTableId: target.tableId,
        );
      } else {
        await gateway.transferTable(
          ctx: ctx,
          sourceTableId: request.sourceTableId,
          targetTableId: target.tableId,
        );
      }
      if (!mounted) return;
      setState(() => _moveRequest = null);
      _showSnack(merge
          ? '$sourceName, ${target.displayName} ile birleştirildi.'
          : '$sourceName, ${target.displayName} masasına taşındı.');
      await _load();
    } on PosActionException catch (error, stackTrace) {
      ref.read(loggingServiceProvider).log(
        LogLevel.warning,
        'PosBranchOverviewScreen: table move failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'sourceTableId': request.sourceTableId,
          'targetTableId': target.tableId,
          'merge': merge,
        },
      );
      if (!mounted) return;
      _showSnack(_moveFailureMessage(error));
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  static String _moveFailureMessage(PosActionException error) {
    final detailCode = error.details?['code'];
    if (detailCode == 'reservationConflict') {
      return 'Hedef masada aktif bir rezervasyon var; taşıma yapılamadı.';
    }
    if (detailCode == 'targetSessionConflict') {
      return 'Hedef masa bu sırada doldu. Lütfen tekrar deneyin.';
    }
    return 'Masa taşınamadı. Lütfen tekrar deneyin.';
  }

  Widget _buildTableGrid(
      List<PosBranchTableSummary> tables, PosDeviceContext ctx) {
    if (_selectedAreaTab == _AreaTab.takeaway) {
      // Adım 5 (2026-11-07) — real paket/gel-al order management,
      // replacing the disclosed placeholder ADR-060 left here (this
      // screen's table-centric data model has no takeaway-order query of
      // its own; `PosTakeawayOrdersScreen` reads `CanonicalOrderRepository
      // .watchByBranch` directly instead, exactly like the Admin Siparişler
      // screen already does).
      return PosTakeawayOrdersScreen(ctx: ctx);
    }
    final filtered = _selectedAreaTab == _AreaTab.all
        ? tables
        : tables.where((t) => t.areaName == _selectedAreaTab.label).toList();
    if (filtered.isEmpty) {
      return EmptyView(
        icon: Icons.table_restaurant_outlined,
        message: '${_selectedAreaTab.label} bölgesinde masa yok.',
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: GridView.builder(
        // 2026-11-11 — bird's-eye cards are taller than wide (status row
        // + top-down table + badge row).
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 0.82,
        ),
        itemCount: filtered.length,
        itemBuilder: (context, index) => _TableTile(
          table: filtered[index],
          onResolved: () => _load(),
          onTap: () => _openTable(filtered[index]),
          isMoveSource: _moveRequest?.sourceTableId == filtered[index].tableId,
        ),
      ),
    );
  }
}

class _TableTile extends ConsumerStatefulWidget {
  const _TableTile({
    required this.table,
    required this.onResolved,
    required this.onTap,
    this.isMoveSource = false,
  });
  final PosBranchTableSummary table;
  final VoidCallback onResolved;
  final VoidCallback onTap;

  /// 2026-11-11 — the table being moved, highlighted while staff pick the
  /// target.
  final bool isMoveSource;

  @override
  ConsumerState<_TableTile> createState() => _TableTileState();
}

class _TableTileState extends ConsumerState<_TableTile> {
  String? _resolvingRequestId;
  bool _printing = false;
  bool _startingPayment = false;

  /// 2026-11-11 — bird's-eye card state (see [PosTableTone]).
  PosTableTone get _tone => PosTableTone.resolve(
        status: widget.table.status,
        activePortionCount: widget.table.activePortionCount,
      );

  IconData _iconFor(String type) => switch (type) {
        'callWaiter' => Icons.room_service_outlined,
        'requestBill' => Icons.receipt_long_outlined,
        // Self-Order QR Faz 5.
        'ashtrayOrService' => Icons.cleaning_services_outlined,
        'clearTable' => Icons.cleaning_services_outlined,
        'customNote' => Icons.sticky_note_2_outlined,
        _ => Icons.notifications_active_outlined,
      };

  /// Self-Order QR Faz 5 — a staff-facing label for the tooltip on each
  /// request icon; for `customNote` this also surfaces the guest's own
  /// typed text, since the icon alone can't convey free-form content.
  String _labelFor(PosPendingServiceRequest request) => switch (request.type) {
        'callWaiter' => 'Garson Çağrısı',
        'requestBill' => 'Hesap İsteği',
        'ashtrayOrService' => 'Kül Tablası / Servis İsteği',
        'clearTable' => 'Masa Temizliği İsteği',
        'customNote' =>
          request.note == null ? 'Özel Not' : 'Özel Not: ${request.note}',
        _ => request.type,
      };

  Future<void> _resolve(PosPendingServiceRequest request) async {
    final deviceCtx = ref.read(posDeviceContextProvider);
    if (deviceCtx == null || _resolvingRequestId != null) return;
    setState(() => _resolvingRequestId = request.requestId);
    try {
      await ref.read(posActionGatewayProvider).resolveServiceRequest(
            ctx: deviceCtx,
            requestId: request.requestId,
          );
      widget.onResolved();
    } on PosActionException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _resolvingRequestId = null);
    }
  }

  /// Green quick-print button on an occupied/bill-requested card
  /// (2026-11-05 printer integration) — prints the table's current ara
  /// hesap fişi without entering the table workspace first. Fetches the
  /// table's full operational view itself (the overview grid's own
  /// summary doesn't carry line/check detail), so this works even though
  /// [PosBranchTableSummary] doesn't expose a checkId.
  Future<void> _print(PosDeviceContext ctx) async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      await printTableReceipt(
        context: context,
        ref: ref,
        ctx: ctx,
        tableId: widget.table.tableId,
        checkId: null,
        tableName: widget.table.displayName,
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// Blue quick-payment button on an occupied/bill-requested card
  /// (2026-11-06) — opens the compact ödeme modal directly on the
  /// table's currently open/ready-for-payment check, without entering
  /// the table workspace first. Mirrors [_print]'s own "fetch the view,
  /// then resolve the check" shape, reusing the same resolution function
  /// [PrintTableReceipt] already uses (`resolveOpenOrReadyForPaymentCheckId`).
  Future<void> _payNow(PosDeviceContext ctx) async {
    if (_startingPayment) return;
    setState(() => _startingPayment = true);
    try {
      final view =
          await ref.read(posOperationalViewGatewayProvider).getTableView(
                organizationId: ctx.organizationId,
                branchId: ctx.branchId,
                tableId: widget.table.tableId,
                deviceId: ctx.deviceId,
                deviceSessionId: ctx.deviceSessionId,
              );
      final checkId = resolveOpenOrReadyForPaymentCheckId(view);
      if (checkId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu masada açık bir hesap yok.')),
        );
        return;
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) =>
            PosCheckoutScreen(ctx: ctx, checkId: checkId, view: view),
      );
      widget.onResolved();
    } on PosOperationalViewException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _startingPayment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final deviceCtx = ref.watch(posDeviceContextProvider);
    final canPrint = deviceCtx != null &&
        (table.status == 'occupied' || table.status == 'billRequested');
    final tone = _tone;
    final seating = posTableSeating(
      capacity: table.capacity,
      activePortionCount: table.activePortionCount,
    );
    return Stack(
      children: [
        InkWell(
          borderRadius: AppRadius.kMedium,
          onTap: widget.onTap,
          child: AppCard(
            borderColor: widget.isMoveSource
                ? AppColors.warning
                : tone.color.withValues(alpha: 0.5),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: tone.color.withValues(alpha: 0.12),
                    borderRadius: AppRadius.kPill,
                  ),
                  child: Text(
                    tone.label,
                    style: AppTypography.bodySmall.copyWith(
                        color: tone.color, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                // 2026-11-11 — top-down table with up to four chairs; one
                // chair per live main portion shows a person.
                Expanded(
                  child: PosTableTopView(
                    tableName: table.displayName,
                    tone: tone,
                    chairs: seating.chairs,
                    seated: seating.seated,
                  ),
                ),
                if (table.pendingServiceRequests.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      for (final request in table.pendingServiceRequests)
                        Tooltip(
                          message: _labelFor(request),
                          child: InkWell(
                            borderRadius: AppRadius.kPill,
                            onTap: () => _resolve(request),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.secondary.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              child: _resolvingRequestId == request.requestId
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.secondary,
                                      ),
                                    )
                                  : Icon(
                                      _iconFor(request.type),
                                      size: 14,
                                      color: AppColors.secondary,
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                // Adım 5 (2026-11-07) — "Mutfakta Hazır": at least one of
                // this table's orders has reached `status == "ready"`
                // (every kitchen line confirmed ready) and is waiting to be
                // served — visual-only, no sound (the existing alert sound
                // is reserved for new-QR-order arrivals; conflating the two
                // events under one cue would blur what staff are being
                // told).
                if (table.kitchenReadyOrderCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.restaurant_rounded,
                            size: 16, color: AppColors.success),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Mutfakta Hazır',
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (table.pendingQrLineCount > 0)
                  Row(
                    children: [
                      const Icon(Icons.qr_code_2_rounded,
                          size: 16, color: AppColors.accent),
                      const SizedBox(width: 4),
                      Text(
                        '${table.pendingQrLineCount} bekleyen',
                        style: AppTypography.bodySmall.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (canPrint)
          Positioned(
            top: AppSpacing.xs,
            right: AppSpacing.xs,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mavi "Ödeme Al" (2026-11-06) — tahsilat akışını masa
                // kartından, çalışma alanına girmeden tetikler.
                InkWell(
                  borderRadius: AppRadius.kPill,
                  onTap: () => _payNow(deviceCtx),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppColors.info,
                      shape: BoxShape.circle,
                    ),
                    child: _startingPayment
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : const Icon(Icons.payments_outlined,
                            size: 14, color: AppColors.onPrimary),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                InkWell(
                  borderRadius: AppRadius.kPill,
                  onTap: () => _print(deviceCtx),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                    child: _printing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : const Icon(Icons.print_outlined,
                            size: 14, color: AppColors.onPrimary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
