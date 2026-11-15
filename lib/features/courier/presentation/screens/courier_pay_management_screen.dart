import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../data/courier_pay_gateway.dart';
import '../../domain/pay/courier_pay_models.dart';
import '../providers/courier_pay_providers.dart';
import '../widgets/courier_earnings_tab.dart';

/// ADR-085 stage 5 — "Kurye Vardiya & Kazanç" in the panel (manager,
/// admin, owner). **Vardiya Onayları**: the shifts couriers started or
/// ended, to approve, correct (with a reason) or — for a start — reject.
/// **Kazançlar**: each courier's earnings for today, this week or this
/// month. The server limits both to the caller's branches (a manager) or
/// the whole organization (an admin/owner).
class CourierPayManagementScreen extends StatelessWidget {
  const CourierPayManagementScreen({super.key, required this.organizationId});

  final String organizationId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Kurye Vardiya & Kazanç'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          bottom: const TabBar(tabs: [
            Tab(key: Key('tabShiftApprovals'), text: 'Vardiya Onayları'),
            Tab(key: Key('tabCourierEarnings'), text: 'Kazançlar'),
          ]),
        ),
        body: SafeArea(
          child: TabBarView(children: [
            _ShiftApprovalsTab(organizationId: organizationId),
            _EarningsTab(organizationId: organizationId),
          ]),
        ),
      ),
    );
  }
}

class _ShiftApprovalsTab extends ConsumerStatefulWidget {
  const _ShiftApprovalsTab({required this.organizationId});

  final String organizationId;

  @override
  ConsumerState<_ShiftApprovalsTab> createState() => _ShiftApprovalsTabState();
}

class _ShiftApprovalsTabState extends ConsumerState<_ShiftApprovalsTab> {
  String? _busyShiftId;

  Future<void> _review(
    CourierShift shift, {
    required bool approve,
    DateTime? approvedAt,
    String? reason,
    required String success,
  }) async {
    if (_busyShiftId != null) return;
    setState(() => _busyShiftId = shift.shiftId);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(courierPayGatewayProvider).reviewShift(
            organizationId: widget.organizationId,
            shiftId: shift.shiftId,
            approve: approve,
            approvedAt: approvedAt,
            reason: reason,
          );
      messenger.showSnackBar(SnackBar(content: Text(success)));
      ref.invalidate(openCourierShiftsProvider(widget.organizationId));
      ref.invalidate(courierEarningsReportProvider);
    } on CourierPayException catch (error) {
      messenger.showSnackBar(SnackBar(
        content: Text(error.message),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _busyShiftId = null);
    }
  }

  Future<void> _adjust(CourierShift shift) async {
    final result = await showDialog<({DateTime time, String reason})>(
      context: context,
      builder: (_) => _AdjustShiftTimeDialog(shift: shift),
    );
    if (result == null || !mounted) return;
    await _review(shift,
        approve: true,
        approvedAt: result.time,
        reason: result.reason,
        success: '${shift.courierName}: saat düzeltilerek onaylandı.');
  }

  Future<void> _reject(CourierShift shift) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectShiftDialog(shift: shift),
    );
    if (reason == null || !mounted) return;
    await _review(shift,
        approve: false,
        reason: reason,
        success: '${shift.courierName}: vardiya başlangıcı reddedildi.');
  }

  @override
  Widget build(BuildContext context) {
    final shiftsAsync =
        ref.watch(openCourierShiftsProvider(widget.organizationId));
    return shiftsAsync.when(
      loading: () => const LoadingView(message: 'Vardiyalar yükleniyor...'),
      error: (error, _) => ErrorView(
        message: error is CourierPayException
            ? error.message
            : 'Vardiyalar yüklenemedi.',
        retryLabel: 'Tekrar Dene',
        onRetry: () =>
            ref.invalidate(openCourierShiftsProvider(widget.organizationId)),
      ),
      data: (shifts) {
        if (shifts.isEmpty) {
          return EmptyView(
            key: const Key('noOpenShifts'),
            icon: Icons.schedule_outlined,
            message: 'Onay bekleyen ya da süren vardiya yok.',
            actionLabel: 'Yenile',
            onAction: () => ref
                .invalidate(openCourierShiftsProvider(widget.organizationId)),
          );
        }
        final pending = shifts.where((s) => s.status.waitsForManager).toList();
        final running =
            shifts.where((s) => s.status == CourierShiftStatus.active).toList();
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(openCourierShiftsProvider(widget.organizationId));
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (pending.isNotEmpty) ...[
                const Text('Onay Bekleyenler',
                    style: AppTypography.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                for (final shift in pending)
                  _ShiftCard(
                    shift: shift,
                    busy: _busyShiftId == shift.shiftId,
                    onApprove: () => _review(shift,
                        approve: true,
                        success: '${shift.courierName}: onaylandı.'),
                    onAdjust: () => _adjust(shift),
                    onReject: shift.status == CourierShiftStatus.startRequested
                        ? () => _reject(shift)
                        : null,
                  ),
              ],
              if (running.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                const Text('Vardiyada', style: AppTypography.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                for (final shift in running) _ShiftCard(shift: shift),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.shift,
    this.busy = false,
    this.onApprove,
    this.onAdjust,
    this.onReject,
  });

  final CourierShift shift;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onAdjust;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final String detail = switch (shift.status) {
      CourierShiftStatus.startRequested =>
        'Başlangıç basıldı: ${formatClock(shift.requestedStartAt)}',
      CourierShiftStatus.endRequested =>
        'Başlangıç: ${formatClock(shift.approvedStartAt ?? shift.requestedStartAt)}'
            ' · Bitiş basıldı: ${formatClock(shift.pendingTime)}',
      _ =>
        '${formatClock(shift.approvedStartAt ?? shift.requestedStartAt)}\'dan beri',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        key: Key('shiftCard-${shift.shiftId}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(shift.courierName, style: AppTypography.bodyLarge),
            Text('${shift.status.label} · $detail',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
            if (onApprove != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  ElevatedButton(
                    key: Key('approveShift-${shift.shiftId}'),
                    onPressed: busy ? null : onApprove,
                    child: const Text('Onayla'),
                  ),
                  OutlinedButton(
                    key: Key('adjustShift-${shift.shiftId}'),
                    onPressed: busy ? null : onAdjust,
                    child: const Text('Saati Düzelt'),
                  ),
                  if (onReject != null)
                    TextButton(
                      key: Key('rejectShift-${shift.shiftId}'),
                      onPressed: busy ? null : onReject,
                      child: const Text('Reddet'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Saati Düzelt": a time on the pressed day, not in the future, and a
/// mandatory reason.
class _AdjustShiftTimeDialog extends StatefulWidget {
  const _AdjustShiftTimeDialog({required this.shift});

  final CourierShift shift;

  @override
  State<_AdjustShiftTimeDialog> createState() => _AdjustShiftTimeDialogState();
}

class _AdjustShiftTimeDialogState extends State<_AdjustShiftTimeDialog> {
  final _reason = TextEditingController();
  late DateTime _time = widget.shift.pendingTime.toLocal();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (picked == null) return;
    final base = widget.shift.pendingTime.toLocal();
    setState(() {
      _time =
          DateTime(base.year, base.month, base.day, picked.hour, picked.minute);
      _error = null;
    });
  }

  void _save() {
    if (_time.isAfter(DateTime.now())) {
      setState(() => _error = 'İleri bir saat seçilemez.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Gerekçe yazın.');
      return;
    }
    Navigator.of(context).pop((time: _time, reason: _reason.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final isEnd = widget.shift.status == CourierShiftStatus.endRequested;
    return AlertDialog(
      title: Text('${widget.shift.courierName} — '
          '${isEnd ? 'Bitiş' : 'Başlangıç'} Saati'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Kuryenin bastığı saat: '
              '${formatClock(widget.shift.pendingTime)}'),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            key: const Key('adjustShiftPickTime'),
            onPressed: _pick,
            icon: const Icon(Icons.schedule_rounded),
            label: Text('Onaylanacak saat: ${formatClock(_time)}'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('adjustShiftReason'),
            controller: _reason,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Gerekçe'),
          ),
          if (_error != null)
            Text(_error!,
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.error)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          key: const Key('adjustShiftSave'),
          onPressed: _save,
          child: const Text('Onayla'),
        ),
      ],
    );
  }
}

class _RejectShiftDialog extends StatefulWidget {
  const _RejectShiftDialog({required this.shift});

  final CourierShift shift;

  @override
  State<_RejectShiftDialog> createState() => _RejectShiftDialogState();
}

class _RejectShiftDialogState extends State<_RejectShiftDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.shift.courierName} — Vardiyayı Reddet'),
      content: TextField(
        key: const Key('rejectShiftReason'),
        controller: _reason,
        maxLength: 300,
        decoration: const InputDecoration(labelText: 'Gerekçe (isteğe bağlı)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          key: const Key('rejectShiftConfirm'),
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          child: const Text('Reddet'),
        ),
      ],
    );
  }
}

class _EarningsTab extends ConsumerStatefulWidget {
  const _EarningsTab({required this.organizationId});

  final String organizationId;

  @override
  ConsumerState<_EarningsTab> createState() => _EarningsTabState();
}

class _EarningsTabState extends ConsumerState<_EarningsTab> {
  CourierPayPeriod _period = CourierPayPeriod.today;

  @override
  Widget build(BuildContext context) {
    final scope = (organizationId: widget.organizationId, period: _period);
    final reportAsync = ref.watch(courierEarningsReportProvider(scope));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
          child: Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final period in CourierPayPeriod.values)
                ChoiceChip(
                  key: Key('panelEarningsPeriod-${period.name}'),
                  label: Text(period.label),
                  selected: _period == period,
                  onSelected: (_) => setState(() => _period = period),
                ),
            ],
          ),
        ),
        Expanded(
          child: reportAsync.when(
            loading: () =>
                const LoadingView(message: 'Kazançlar yükleniyor...'),
            error: (error, _) => ErrorView(
              message: error is CourierPayException
                  ? error.message
                  : 'Kazançlar yüklenemedi.',
              retryLabel: 'Tekrar Dene',
              onRetry: () =>
                  ref.invalidate(courierEarningsReportProvider(scope)),
            ),
            data: (report) {
              if (report.couriers.isEmpty) {
                return const EmptyView(
                  key: Key('noCourierEarnings'),
                  icon: Icons.payments_outlined,
                  message: 'Bu dönemde kurye kazancı yok.',
                );
              }
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(
                    'Toplam: ${formatPayAmount(report.totalMinorUnits)}',
                    key: const Key('panelEarningsTotal'),
                    style: AppTypography.titleLarge,
                  ),
                  if (report.truncated)
                    Text(
                      'Kayıt sayısı çok fazla; daha kısa bir dönem seçin.',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.warning),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  for (final courier in report.couriers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppCard(
                        padding: EdgeInsets.zero,
                        child: ExpansionTile(
                          key: Key('courierEarnings-${courier.staffUid}'),
                          title: Text(courier.courierName,
                              style: AppTypography.bodyLarge),
                          subtitle: Text(
                            '${courier.totals.packageCount} paket · '
                            '${formatShiftMinutes(courier.totals.shiftMinutes)}'
                            ' vardiya',
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                          ),
                          trailing: Text(
                            formatPayAmount(courier.totals.totalMinorUnits),
                            style: AppTypography.labelLarge,
                          ),
                          childrenPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md),
                          children: [
                            for (final line in courier.lines)
                              CourierEarningLineTile(line: line),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
