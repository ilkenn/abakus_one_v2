import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../admin/presentation/providers/admin_context_provider.dart';
import '../../../admin/presentation/providers/admin_dependencies_provider.dart';
import '../../../admin/presentation/providers/trusted_device_session_providers.dart';
import '../../../admin/presentation/screens/trusted_device_status_screen.dart';
import '../../data/pos_action_gateway.dart';
import '../../data/pos_operational_view_gateway.dart';
import '../providers/pos_workspace_providers.dart';
import '../widgets/pos_operational_rail.dart';
import '../widgets/print_table_receipt_action.dart';
import 'end_of_day_screen.dart';
import 'pos_cash_register_screen.dart';
import 'pos_checkout_screen.dart';
import 'pos_table_workspace_screen.dart';
import 'pos_takeaway_orders_screen.dart';

/// Masalar grid'inin bölge filtresi (2026-11-06) — `RestaurantTable
/// .areaName`'in zaten taşıdığı serbest metni kullanır, yeni bir alan
/// değil. [takeaway] gerçek bir masa/alan değil — bu ekranın bugünkü veri
/// modelinde paket/gel-al siparişleri için ayrı bir sorgu/kart tasarımı
/// yok; seçildiğinde bunu açıkça gösteren bir yer tutucu render edilir,
/// asla sessizce boş/yanlış bir masa listesi değil.
enum _AreaTab {
  all('Tümü'),
  garden('Bahçe'),
  hall('Salon'),
  terrace('Teras'),
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

  Future<void> _load({bool poll = false}) async {
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
        Expanded(child: _buildTableGrid(tables, ctx)),
      ],
    );
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
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 1.1,
        ),
        itemCount: filtered.length,
        itemBuilder: (context, index) => _TableTile(
          table: filtered[index],
          onResolved: () => _load(),
        ),
      ),
    );
  }
}

class _TableTile extends ConsumerStatefulWidget {
  const _TableTile({required this.table, required this.onResolved});
  final PosBranchTableSummary table;
  final VoidCallback onResolved;

  @override
  ConsumerState<_TableTile> createState() => _TableTileState();
}

class _TableTileState extends ConsumerState<_TableTile> {
  String? _resolvingRequestId;
  bool _printing = false;
  bool _startingPayment = false;

  Color get _statusColor => switch (widget.table.status) {
        'available' => AppColors.primary,
        'occupied' => AppColors.warning,
        'billRequested' => AppColors.secondary,
        'cleaning' => AppColors.textSecondary,
        'disabled' => AppColors.error,
        _ => AppColors.textSecondary,
      };

  String get _statusLabel => switch (widget.table.status) {
        'available' => 'Boş',
        'occupied' => 'Dolu',
        'billRequested' => 'Hesap İstendi',
        'cleaning' => 'Temizleniyor',
        'disabled' => 'Kapalı',
        _ => widget.table.status,
      };

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
    return Stack(
      children: [
        InkWell(
          borderRadius: AppRadius.kMedium,
          onTap: () {
            ref.read(selectedPosTableIdProvider.notifier).state = table.tableId;
            Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const PosTableWorkspaceScreen()),
            );
          },
          child: AppCard(
            borderColor: _statusColor.withValues(alpha: 0.35),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.table_restaurant_rounded,
                    color: _statusColor, size: 28),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  table.displayName,
                  style: AppTypography.titleMedium
                      .copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
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
                const Spacer(),
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
