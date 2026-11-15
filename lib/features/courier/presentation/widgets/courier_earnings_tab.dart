import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../data/courier_pay_gateway.dart';
import '../../domain/pay/courier_pay_models.dart';
import '../providers/courier_pay_providers.dart';

/// ADR-085 stage 5 — "Kazancım" in the courier app: the courier's own rate,
/// its shift ("Vardiya Başlat" / "Vardiya Bitir", each approved by a
/// manager; shop couriers only) and its earnings for today, this week or
/// this month.
class CourierEarningsTab extends ConsumerStatefulWidget {
  const CourierEarningsTab({super.key});

  @override
  ConsumerState<CourierEarningsTab> createState() => _CourierEarningsTabState();
}

class _CourierEarningsTabState extends ConsumerState<CourierEarningsTab> {
  CourierPayPeriod _period = CourierPayPeriod.today;
  bool _busy = false;

  Future<void> _refresh() async {
    ref.invalidate(myCourierPayProvider);
    try {
      await ref.read(myCourierPayProvider(_period).future);
    } catch (_) {
      // The error state shows it.
    }
  }

  Future<void> _shiftAction(
    Future<void> Function(CourierPayGateway gateway) action,
    String success,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(courierPayGatewayProvider));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(success)));
      ref.invalidate(myCourierPayProvider);
    } on CourierPayException catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.error,
        ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payAsync = ref.watch(myCourierPayProvider(_period));
    return payAsync.when(
      loading: () =>
          const LoadingView(message: 'Kazanç bilgileri yükleniyor...'),
      error: (error, _) => ErrorView(
        message: error is CourierPayException
            ? error.message
            : 'Kazanç bilgileri yüklenemedi.',
        retryLabel: 'Tekrar Dene',
        onRetry: _refresh,
      ),
      data: (pay) => RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          key: const Key('courierEarningsList'),
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (pay.shiftsEnabled) ...[
              _ShiftCard(
                shift: pay.openShift,
                busy: _busy,
                canStart: pay.currentRate?.hourlyMinorUnits != null,
                onStart: () => _shiftAction(
                  (gateway) => gateway.startShift(),
                  'Vardiya başlangıcı müdür onayına gönderildi.',
                ),
                onEnd: () => _shiftAction(
                  (gateway) => gateway.endShift(),
                  'Vardiya bitişi müdür onayına gönderildi.',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AppCard(
              child: Text(
                pay.currentRate == null
                    ? 'Ücretiniz henüz tanımlanmadı.'
                    : 'Ücretiniz: ${pay.currentRate!.summary}',
                key: const Key('courierCurrentRate'),
                style: AppTypography.bodyMedium,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final period in CourierPayPeriod.values)
                  ChoiceChip(
                    key: Key('earningsPeriod-${period.name}'),
                    label: Text(period.label),
                    selected: _period == period,
                    onSelected: (_) => setState(() => _period = period),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            CourierEarningsTotalsCard(totals: pay.totals),
            const SizedBox(height: AppSpacing.md),
            if (pay.lines.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Bu dönemde kazanç kaydı yok.',
                  key: const Key('noEarnings'),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
              )
            else
              for (final line in pay.lines) CourierEarningLineTile(line: line),
          ],
        ),
      ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.shift,
    required this.busy,
    required this.canStart,
    required this.onStart,
    required this.onEnd,
  });

  final CourierShift? shift;
  final bool busy;
  final bool canStart;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final current = shift;
    final String text;
    Widget? action;
    if (current == null) {
      text = canStart
          ? 'Vardiyada değilsiniz.'
          : 'Saatlik ücretiniz tanımlanınca vardiya başlatabilirsiniz.';
      if (canStart) {
        action = ElevatedButton.icon(
          key: const Key('shiftStart'),
          onPressed: busy ? null : onStart,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Vardiya Başlat'),
        );
      }
    } else {
      switch (current.status) {
        case CourierShiftStatus.startRequested:
          text = 'Başlangıç onayı bekliyor '
              '(${formatClock(current.requestedStartAt)}).';
        case CourierShiftStatus.active:
          text = 'Vardiyadasınız — '
              '${formatClock(current.approvedStartAt ?? current.requestedStartAt)}'
              '\'dan beri.';
          action = OutlinedButton.icon(
            key: const Key('shiftEnd'),
            onPressed: busy ? null : onEnd,
            icon: const Icon(Icons.stop_rounded),
            label: const Text('Vardiya Bitir'),
          );
        case CourierShiftStatus.endRequested:
          text = 'Bitiş onayı bekliyor '
              '(${formatClock(current.requestedEndAt ?? current.requestedStartAt)}).';
        case CourierShiftStatus.closed || CourierShiftStatus.rejected:
          text = current.status.label;
      }
    }
    return AppCard(
      key: const Key('courierShiftCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Vardiya', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(text, key: const Key('courierShiftStatus')),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            action,
          ],
        ],
      ),
    );
  }
}

/// Total, packages and shift time of a period (courier app and panel).
class CourierEarningsTotalsCard extends StatelessWidget {
  const CourierEarningsTotalsCard({super.key, required this.totals});

  final CourierEarningsTotals totals;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Toplam Kazanç',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          Text(
            formatPayAmount(totals.totalMinorUnits),
            key: const Key('earningsTotal'),
            style: AppTypography.priceLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Paket: ${totals.packageCount} adet · '
            '${formatPayAmount(totals.packageMinorUnits)}',
            style: AppTypography.bodyMedium,
          ),
          Text(
            'Vardiya: ${formatShiftMinutes(totals.shiftMinutes)} · '
            '${formatPayAmount(totals.shiftMinorUnits)}',
            style: AppTypography.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class CourierEarningLineTile extends StatelessWidget {
  const CourierEarningLineTile({super.key, required this.line});

  final CourierEarningLine line;

  @override
  Widget build(BuildContext context) {
    final detail = line.kind == CourierEarningKind.package
        ? '${line.earnedDate} · ${formatClock(line.earnedAt)}'
        : '${line.earnedDate} · saatlik '
            '${formatPayAmount(line.unitRateMinorUnits)}';
    return ListTile(
      key: Key('earningLine-${line.lineId}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        line.kind == CourierEarningKind.package
            ? Icons.inventory_2_outlined
            : Icons.schedule_rounded,
        color: AppColors.primary,
      ),
      title: Text(line.title, style: AppTypography.bodyLarge),
      subtitle: Text(detail,
          style:
              AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
      trailing: Text(formatPayAmount(line.amountMinorUnits),
          style: AppTypography.labelLarge),
    );
  }
}

/// "09:05" in the device's local time.
String formatClock(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
