import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/build_courier_earnings_summary.dart';
import '../../domain/compensation/courier_earnings_summary.dart';
import '../providers/courier_dependencies_provider.dart';

enum _EarningsPeriod { today, week, month }

/// The courier-facing earnings dashboard — "the courier must understand
/// exactly why every amount exists." Every figure comes directly from
/// [CourierEarningsSummary] (`BuildCourierEarningsSummary`), never a
/// screen-local recomputation.
class CourierEarningsScreen extends ConsumerStatefulWidget {
  const CourierEarningsScreen({super.key, required this.courierId});

  final String courierId;

  @override
  ConsumerState<CourierEarningsScreen> createState() =>
      _CourierEarningsScreenState();
}

class _CourierEarningsScreenState extends ConsumerState<CourierEarningsScreen> {
  _EarningsPeriod _period = _EarningsPeriod.today;
  CourierEarningsSummary? _summary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  ({DateTime start, DateTime end}) _rangeFor(_EarningsPeriod period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case _EarningsPeriod.today:
        return (start: today, end: today.add(const Duration(days: 1)));
      case _EarningsPeriod.week:
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        return (start: weekStart, end: weekStart.add(const Duration(days: 7)));
      case _EarningsPeriod.month:
        final monthStart = DateTime(now.year, now.month, 1);
        final monthEnd = DateTime(now.year, now.month + 1, 1);
        return (start: monthStart, end: monthEnd);
    }
  }

  Future<void> _load() async {
    final range = _rangeFor(_period);
    final summary = await BuildCourierEarningsSummary(
      deliveryEarningsRepository: ref.read(deliveryEarningsRepositoryProvider),
      shiftEarningsRepository: ref.read(shiftHourlyEarningsRepositoryProvider),
      adjustmentRepository:
          ref.read(courierEarningsAdjustmentRepositoryProvider),
      paymentRepository: ref.read(courierEarningsPaymentRepositoryProvider),
    )(
      courierId: widget.courierId,
      periodStart: range.start,
      periodEnd: range.end,
    );
    if (!mounted) return;
    setState(() => _summary = summary);
  }

  static const _periodLabels = {
    _EarningsPeriod.today: 'Bugün',
    _EarningsPeriod.week: 'Bu Hafta',
    _EarningsPeriod.month: 'Bu Ay',
  };

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kazançlarım'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  for (final period in _EarningsPeriod.values)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: ChoiceChip(
                        label: Text(_periodLabels[period]!),
                        selected: _period == period,
                        onSelected: (_) {
                          setState(() {
                            _period = period;
                            _summary = null;
                          });
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: summary == null
                  ? const LoadingView(message: 'Kazançlar yükleniyor...')
                  : ListView(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      children: [
                        _buildTotalsCard(summary),
                        const SizedBox(height: AppSpacing.md),
                        _buildBreakdownCard(summary),
                        const SizedBox(height: AppSpacing.md),
                        _buildOperationalCard(summary),
                        const SizedBox(height: AppSpacing.lg),
                        const Text('Teslimat Bazında',
                            style: AppTypography.titleMedium),
                        const SizedBox(height: AppSpacing.sm),
                        if (summary.deliveryLineItems.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: AppSpacing.lg),
                            child: EmptyView(
                              icon: Icons.receipt_long_outlined,
                              message: 'Bu dönemde teslimat kazancı yok',
                            ),
                          )
                        else
                          for (final item in summary.deliveryLineItems)
                            _DeliveryEarningsTile(item: item),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsCard(CourierEarningsSummary summary) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Toplam Kazanç', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _row('Brüt Kazanç', summary.grossEarnings.toString()),
          _row('Ödenen', summary.paidAmount.toString()),
          _row('Bekleyen Ödeme', summary.pendingAmount.toString(),
              emphasize: true),
        ],
      ),
    );
  }

  Widget _buildBreakdownCard(CourierEarningsSummary summary) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Kazanç Dökümü', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _row('Paket Kazancı', summary.packageEarnings.toString()),
          _row('Saatlik Kazanç', summary.hourlyEarnings.toString()),
          _row('Ekstra Mesafe Kazancı',
              summary.extraDistanceEarnings.toString()),
          _row('Primler', summary.bonuses.toString()),
          _row('Düzeltmeler', summary.adjustmentsTotal.toString()),
        ],
      ),
    );
  }

  Widget _buildOperationalCard(CourierEarningsSummary summary) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Çalışma Özeti', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _row('Çalışılan Saat',
              '${summary.hoursWorked.inMinutes ~/ 60}s ${summary.hoursWorked.inMinutes % 60}dk'),
          _row('Teslim Edilen Paket', '${summary.packagesDelivered}'),
          _row('Kat Edilen Mesafe',
              '${summary.distanceTravelledKm.toStringAsFixed(1)} km'),
          _row('Ücretli Ekstra Mesafe',
              '${summary.chargeableExtraDistanceKm.toStringAsFixed(1)} km'),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
          Text(
            value,
            style: emphasize
                ? AppTypography.titleMedium.copyWith(color: AppColors.primary)
                : AppTypography.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _DeliveryEarningsTile extends StatelessWidget {
  const _DeliveryEarningsTile({required this.item});

  final DeliveryEarningsLineItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Sipariş: ${item.orderReference}',
                    style: AppTypography.bodyLarge),
                Text(item.totalEarnings.toString(),
                    style: AppTypography.titleMedium
                        .copyWith(color: AppColors.success)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Paket: ${item.packageEarnings} • Saatlik pay: '
              '${item.hourlyContribution} • Ekstra mesafe: '
              '${item.extraDistanceEarnings}',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
