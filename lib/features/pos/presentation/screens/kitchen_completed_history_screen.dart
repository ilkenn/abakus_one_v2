import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/record_kitchen_event.dart';
import '../../application/use_cases/transition_kitchen_work_item.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/kds/kitchen_line_status.dart';
import '../../domain/kds/kitchen_work_item.dart';
import '../providers/kds_dependencies_provider.dart';

/// Every completed ([KitchenLineStatus.ready]) or terminally-closed
/// ([KitchenLineStatus.cancelled]/[KitchenLineStatus.unavailable])
/// [KitchenWorkItem] for a branch — "Completed/Ready History." Reads
/// directly from [KitchenProjectionRepository], never a second, duplicated
/// history record.
///
/// **2026-09-22**: a `ready` item here can now be recalled directly —
/// closing a real gap [KitchenOrderDetailsScreen]'s own recall action
/// doesn't cover: once the order's overall status has advanced past
/// `ready` (a "mistakenly completed" ticket the order flow itself has
/// since moved on from), `FirestoreKitchenTicketRepository.findById`
/// legitimately returns `null` for it (its `_kitchenEligibleStatuses`
/// check), so a staff member can no longer reach that screen for this
/// order at all — this list is the one remaining place such an item is
/// still visible, so it's the one place recall must work from directly
/// (no ticket/order dependency — [TransitionKitchenWorkItem] only ever
/// needed the work item itself).
class KitchenCompletedHistoryScreen extends ConsumerStatefulWidget {
  const KitchenCompletedHistoryScreen({
    super.key,
    required this.branchId,
    this.authorizationPolicy,
    this.deviceId,
    this.performedByStaffId = 'staff-1',
  });

  final String branchId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String? deviceId;
  final String performedByStaffId;

  @override
  ConsumerState<KitchenCompletedHistoryScreen> createState() =>
      _KitchenCompletedHistoryScreenState();
}

class _KitchenCompletedHistoryScreenState
    extends ConsumerState<KitchenCompletedHistoryScreen> {
  List<KitchenWorkItem>? _completed;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final items = await ref
        .read(kitchenProjectionRepositoryProvider)
        .findByBranch(branchId: widget.branchId);
    final completed = items
        .where((i) =>
            i.status == KitchenLineStatus.ready ||
            i.status == KitchenLineStatus.cancelled ||
            i.status == KitchenLineStatus.unavailable ||
            i.status == KitchenLineStatus.wasted)
        .toList()
      ..sort((a, b) {
        final aAt = a.readyAt ?? a.cancelledAt ?? a.unavailableAt ?? a.queuedAt;
        final bAt = b.readyAt ?? b.cancelledAt ?? b.unavailableAt ?? b.queuedAt;
        return bAt.compareTo(aAt);
      });
    if (!mounted) return;
    setState(() => _completed = completed);
  }

  Future<void> _recall(KitchenWorkItem item) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _message = 'Yetki politikası tanımlı değil.');
      return;
    }
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Geri Çağır'),
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
    if (!mounted) return;

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
        to: KitchenLineStatus.recalled,
        expectedRevision: item.revision,
        performedByStaffId: widget.performedByStaffId,
        deviceId: widget.deviceId,
        reason: reason,
      );
      if (!mounted) return;
      setState(() => _message = null);
      // The recalled item no longer matches this screen's own
      // ready/cancelled/unavailable/wasted filter — reloading is what
      // makes it disappear from this list, back onto the active board.
      await _load();
    } on BusinessRuleViolation catch (e) {
      if (!mounted) return;
      setState(() => _message = e.description);
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = _completed;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Tamamlanan Geçmişi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: completed == null
            ? const LoadingView(message: 'Yükleniyor...')
            : Column(
                children: [
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                      child: Text(_message!,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.error)),
                    ),
                  Expanded(
                    child: completed.isEmpty
                        ? const EmptyView(
                            icon: Icons.done_all_outlined,
                            message: 'Henüz tamamlanan sipariş yok',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: completed.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final item = completed[index];
                              return AppCard(
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(item.kitchenTicketLineId,
                                          style: AppTypography.bodyMedium),
                                    ),
                                    Text(
                                      item.status.name,
                                      style: AppTypography.bodySmall.copyWith(
                                        color: item.status ==
                                                KitchenLineStatus.ready
                                            ? AppColors.success
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                    if (item.status == KitchenLineStatus.ready)
                                      TextButton(
                                        onPressed: () => _recall(item),
                                        child: const Text('Geri Çağır'),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
