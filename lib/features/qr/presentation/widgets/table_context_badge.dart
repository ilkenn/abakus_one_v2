import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/table_guest_session_gateway.dart';
import '../providers/active_table_context_provider.dart';
import '../providers/table_guest_session_dependencies_provider.dart';

/// Compact, single-line "you are ordering at this table" indicator —
/// structurally the same shape as `ActiveOrderBanner` (a small pill row,
/// conditional render, no card chrome), shown wherever the customer needs
/// a persistent reminder of the active table without it eating screen
/// space: [MenuScreen]'s title area, [CartScreen]'s top.
///
/// Renders nothing when [activeTableContextProvider] is `null` — every
/// call site can drop this in unconditionally, immediately after whatever
/// it sits below, with no extra spacing to account for either way (the
/// visible pill carries its own top margin; the invisible
/// [SizedBox.shrink] carries none).
///
/// Dine-in Sprint 3 — also carries the two service-request tap targets
/// (garson çağır / hesap iste): this badge is already the one place every
/// dine-in-facing screen renders while a table is active, so the request
/// buttons live here rather than a new widget with its own conditional-
/// render logic to duplicate.
class TableContextBadge extends ConsumerStatefulWidget {
  const TableContextBadge({super.key});

  @override
  ConsumerState<TableContextBadge> createState() => _TableContextBadgeState();
}

class _TableContextBadgeState extends ConsumerState<TableContextBadge> {
  ServiceRequestType? _busyType;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    // Client Staleness Check — forces a rebuild every minute so the local
    // `expiresAt` comparison (DateTime.now()) is re-evaluated even when
    // nothing about the live Firestore stream changes. A no-op setState
    // when the badge is currently hidden (no active table context).
    _tickTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestService(String guestSessionId, ServiceRequestType type) async {
    if (_busyType != null) return;
    setState(() => _busyType = type);
    try {
      await ref.read(tableGuestSessionGatewayProvider).createServiceRequest(
            guestSessionId: guestSessionId,
            type: type,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İsteğiniz iletildi.')),
      );
    } on TableGuestSessionException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('İsteğiniz gönderilirken bir sorun oluştu.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyType = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tableContext = ref.watch(activeTableContextProvider);
    if (tableContext == null) return const SizedBox.shrink();
    final guestSessionId = tableContext.session.id;

    final localExpired = tableContext.session.expiresAt != null &&
        DateTime.now().isAfter(tableContext.session.expiresAt!);
    final liveAsync = ref.watch(tableGuestSessionLivenessProvider(guestSessionId));
    // The stream not having delivered data yet (loading/error, e.g. a
    // transient reconnect) must never itself read as stale — only a real
    // snapshot saying so does. `orElse` deliberately stays `false`.
    final liveStale = liveAsync.maybeWhen(
      data: (snapshot) => snapshot == null || !snapshot.isActive,
      orElse: () => false,
    );
    final isStale = localExpired || liveStale;

    final accentColor = isStale ? AppColors.error : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isStale
              ? AppColors.error.withValues(alpha: 0.1)
              : AppColors.primaryExtraLight,
          borderRadius: AppRadius.kPill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isStale
                  ? Icons.warning_amber_rounded
                  : Icons.table_restaurant_rounded,
              size: 16,
              color: accentColor,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                isStale
                    ? 'Oturum süresi doldu — QR kodu tekrar okutun'
                    : '${tableContext.branchName} · ${tableContext.tableName}',
                style: AppTypography.labelLarge.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!isStale) ...[
              const SizedBox(width: AppSpacing.sm),
              _ServiceRequestTapTarget(
                icon: Icons.room_service_outlined,
                tooltip: 'Garson Çağır',
                busy: _busyType == ServiceRequestType.callWaiter,
                onTap: () => _requestService(
                  guestSessionId,
                  ServiceRequestType.callWaiter,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _ServiceRequestTapTarget(
                icon: Icons.receipt_long_outlined,
                tooltip: 'Hesap İste',
                busy: _busyType == ServiceRequestType.requestBill,
                onTap: () => _requestService(
                  guestSessionId,
                  ServiceRequestType.requestBill,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ServiceRequestTapTarget extends StatelessWidget {
  const _ServiceRequestTapTarget({
    required this.icon,
    required this.tooltip,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: AppRadius.kPill,
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              : Icon(icon, size: 16, color: AppColors.primary),
        ),
      ),
    );
  }
}
