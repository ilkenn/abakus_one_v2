import 'dart:async';

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
import '../../../admin/presentation/providers/admin_context_provider.dart';
import '../../../admin/presentation/providers/admin_dependencies_provider.dart';
import '../../../admin/presentation/providers/trusted_device_session_providers.dart';
import '../../../admin/presentation/screens/trusted_device_status_screen.dart';
import '../../data/pos_action_gateway.dart';
import '../../data/pos_operational_view_gateway.dart';
import '../providers/pos_workspace_providers.dart';
import '../widgets/pos_operational_rail.dart';
import 'end_of_day_screen.dart';
import 'pos_cash_register_screen.dart';
import 'pos_table_workspace_screen.dart';

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
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
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
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 1.1,
        ),
        itemCount: tables.length,
        itemBuilder: (context, index) => _TableTile(
          table: tables[index],
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
        _ => Icons.notifications_active_outlined,
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

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    return InkWell(
      borderRadius: AppRadius.kMedium,
      onTap: () {
        ref.read(selectedPosTableIdProvider.notifier).state = table.tableId;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PosTableWorkspaceScreen()),
        );
      },
      child: AppCard(
        borderColor: _statusColor.withValues(alpha: 0.35),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.table_restaurant_rounded, color: _statusColor, size: 28),
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
                style: AppTypography.bodySmall
                    .copyWith(color: _statusColor, fontWeight: FontWeight.bold),
              ),
            ),
            if (table.pendingServiceRequests.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (final request in table.pendingServiceRequests)
                    InkWell(
                      borderRadius: AppRadius.kPill,
                      onTap: () => _resolve(request),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.14),
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
                ],
              ),
            ],
            const Spacer(),
            if (table.pendingQrLineCount > 0)
              Row(
                children: [
                  const Icon(Icons.qr_code_2_rounded,
                      size: 16, color: AppColors.accent),
                  const SizedBox(width: 4),
                  Text(
                    '${table.pendingQrLineCount} bekleyen',
                    style: AppTypography.bodySmall.copyWith(
                        color: AppColors.accent, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
