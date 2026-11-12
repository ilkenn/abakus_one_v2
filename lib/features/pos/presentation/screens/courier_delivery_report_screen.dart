import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../data/delivery_operations_gateway.dart';
import '../../domain/delivery/courier_delivery_report.dart';
import '../providers/courier_dispatch_dependencies_provider.dart';
import '../widgets/delivery_order_dialogs.dart' show formatTlMinor;

/// The quick ranges offered above the report.
enum CourierReportPreset { today, yesterday, last7Days, thisMonth, custom }

extension on CourierReportPreset {
  String get label => switch (this) {
        CourierReportPreset.today => 'Bugün',
        CourierReportPreset.yesterday => 'Dün',
        CourierReportPreset.last7Days => 'Son 7 Gün',
        CourierReportPreset.thisMonth => 'Bu Ay',
        CourierReportPreset.custom => 'Tarih Aralığı',
      };
}

/// `[from, to)` in local days for [preset], relative to [now]. Pure.
({DateTime from, DateTime to}) courierReportRangeFor(
    CourierReportPreset preset, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  return switch (preset) {
    CourierReportPreset.yesterday => (
        from: today.subtract(const Duration(days: 1)),
        to: today
      ),
    CourierReportPreset.last7Days => (
        from: today.subtract(const Duration(days: 6)),
        to: tomorrow
      ),
    CourierReportPreset.thisMonth => (
        from: DateTime(now.year, now.month),
        to: tomorrow
      ),
    _ => (from: today, to: tomorrow),
  };
}

String _minutes(double? value) =>
    value == null ? '—' : '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} dk';

String _day(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _time(DateTime d) {
  final local = d.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// 2026-11-12 (Faz 4, ADR-080) — "Kurye & Paket Raporu" (Admin → Teslimat
/// Dağıtımı altında): per date range, Restoran Kuryeleri vs Kayıtlı Dış
/// Kuryeler — package count, average preparation and delivery time, the
/// tender mix (Nakit / POS / each meal-card brand), cash-difference totals
/// and the pool orders external couriers completed. Server-computed from
/// the "Kurye Hesap Kapat" records; read-only. Manager and above.
class CourierDeliveryReportScreen extends ConsumerStatefulWidget {
  const CourierDeliveryReportScreen({
    super.key,
    required this.organizationId,
    required this.branchId,
    this.clock = DateTime.now,
  });

  final String organizationId;
  final String branchId;
  final DateTime Function() clock;

  @override
  ConsumerState<CourierDeliveryReportScreen> createState() =>
      _CourierDeliveryReportScreenState();
}

class _CourierDeliveryReportScreenState
    extends ConsumerState<CourierDeliveryReportScreen> {
  CourierReportPreset _preset = CourierReportPreset.today;
  late ({DateTime from, DateTime to}) _range =
      courierReportRangeFor(_preset, widget.clock());

  CourierReportQuery get _query => (
        organizationId: widget.organizationId,
        branchId: widget.branchId,
        from: _range.from,
        to: _range.to,
      );

  Future<void> _select(CourierReportPreset preset) async {
    if (preset != CourierReportPreset.custom) {
      setState(() {
        _preset = preset;
        _range = courierReportRangeFor(preset, widget.clock());
      });
      return;
    }
    final now = widget.clock();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(
        start: _range.from,
        end: _range.to.subtract(const Duration(days: 1)),
      ),
      helpText: 'Rapor tarih aralığı (en fazla 92 gün)',
    );
    if (picked == null || !mounted) return;
    final from =
        DateTime(picked.start.year, picked.start.month, picked.start.day);
    final to = DateTime(picked.end.year, picked.end.month, picked.end.day)
        .add(const Duration(days: 1));
    setState(() {
      _preset = CourierReportPreset.custom;
      _range = (from: from, to: to);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(courierDeliveryReportProvider(_query));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kurye & Paket Raporu'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            key: const Key('refreshCourierReport'),
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                ref.invalidate(courierDeliveryReportProvider(_query)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final preset in CourierReportPreset.values)
                    ChoiceChip(
                      key: Key('reportPreset-${preset.name}'),
                      label: Text(preset.label),
                      selected: _preset == preset,
                      onSelected: (_) => _select(preset),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: Text(
                      _range.to.difference(_range.from).inDays <= 1
                          ? _day(_range.from)
                          : '${_day(_range.from)} – '
                              '${_day(_range.to.subtract(const Duration(days: 1)))}',
                      key: const Key('reportRangeLabel'),
                      style: AppTypography.bodyMedium
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: reportAsync.when(
                loading: () =>
                    const LoadingView(message: 'Rapor hazırlanıyor...'),
                error: (error, _) => ErrorView(
                  message: error is DeliveryOperationsException &&
                          error.isPermissionDenied
                      ? 'Bu raporu görüntüleme yetkiniz yok.'
                      : 'Rapor yüklenemedi.',
                  retryLabel: 'Tekrar Dene',
                  onRetry: () =>
                      ref.invalidate(courierDeliveryReportProvider(_query)),
                ),
                data: (report) => report.isEmpty
                    ? const EmptyView(
                        icon: Icons.inventory_2_outlined,
                        message:
                            'Bu tarih aralığında hesabı kapatılmış paket yok.',
                      )
                    : _ReportBody(report: report),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});

  final CourierDeliveryReport report;

  @override
  Widget build(BuildContext context) {
    final totals = report.totals;
    return ListView(
      key: const Key('courierReportBody'),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (report.truncated)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Aralıkta çok fazla paket var; ilk 5.000 paket gösteriliyor. '
              'Daha kısa bir aralık seçin.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.warning),
            ),
          ),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _StatTile(
                key: const Key('statPackages'),
                label: 'Toplam Paket',
                value: '${totals.packageCount}'),
            _StatTile(
                label: 'Toplam Tahsilat',
                value: formatTlMinor(totals.collectedMinorUnits)),
            _StatTile(
                label: 'Ort. Hazırlık',
                value: _minutes(totals.averagePreparationMinutes)),
            _StatTile(
                label: 'Ort. Teslimat',
                value: _minutes(totals.averageDeliveryMinutes)),
            _StatTile(
              key: const Key('statCashDifference'),
              label: 'Kasa Farkı',
              value: formatTlMinor(totals.cashDifferenceMinorUnits),
              emphasis:
                  totals.cashDifferenceMinorUnits < 0 ? AppColors.error : null,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(builder: (context, constraints) {
          final internal = _KindCard(
              key: const Key('kindInternal'),
              title: 'Restoran Kuryeleri',
              aggregate: report.internal);
          final pool = _KindCard(
              key: const Key('kindPool'),
              title: 'Kayıtlı Dış Kuryeler',
              aggregate: report.pool);
          if (constraints.maxWidth < 720) {
            return Column(children: [
              internal,
              const SizedBox(height: AppSpacing.sm),
              pool,
            ]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: internal),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: pool),
            ],
          );
        }),
        const SizedBox(height: AppSpacing.md),
        const Text('Kurye Bazında', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (final courier in report.couriers)
                ListTile(
                  key: Key('reportCourier-${courier.courierId}'),
                  leading: Icon(courier.kind == CourierKind.pool
                      ? Icons.groups_rounded
                      : Icons.two_wheeler_rounded),
                  title: Text(courier.courierName),
                  subtitle: Text([
                    courier.kind == CourierKind.pool
                        ? 'Dış Kurye'
                        : 'Dükkan Kuryesi',
                    '${courier.aggregate.packageCount} paket',
                    'Hazırlık ${_minutes(courier.aggregate.averagePreparationMinutes)}',
                    'Teslimat ${_minutes(courier.aggregate.averageDeliveryMinutes)}',
                    for (final m in courier.aggregate.paymentMethods)
                      '${m.label}: ${formatTlMinor(m.amountMinorUnits)}',
                  ].join(' · ')),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatTlMinor(courier.aggregate.collectedMinorUnits),
                          style: AppTypography.bodyMedium
                              .copyWith(fontWeight: FontWeight.bold)),
                      Text(
                        'Fark ${formatTlMinor(courier.aggregate.cashDifferenceMinorUnits)}',
                        style: AppTypography.bodySmall.copyWith(
                            color:
                                courier.aggregate.cashDifferenceMinorUnits < 0
                                    ? AppColors.error
                                    : AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Dış Kuryelerin Tamamladığı Havuz Siparişleri',
            style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: report.poolOrders.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Text('Bu aralıkta havuz siparişi yok.',
                      key: Key('poolOrdersEmpty'),
                      style: AppTypography.bodyMedium),
                )
              : Column(
                  children: [
                    for (final order in report.poolOrders)
                      ListTile(
                        key: Key('poolOrder-${order.orderId}'),
                        dense: true,
                        title:
                            Text('${order.orderNumber} · ${order.courierName}'),
                        subtitle: Text([
                          if (order.neighborhoodName.isNotEmpty)
                            order.neighborhoodName,
                          order.paymentMethodDisplayName,
                          'Teslimat ${_minutes(order.deliveryMinutes)}',
                          _time(order.collectedAt),
                        ].join(' · ')),
                        trailing: Text(formatTlMinor(order.amountMinorUnits),
                            style: AppTypography.bodyMedium),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Paketler "Kurye Hesap Kapat" anına göre sayılır. Hazırlık: sipariş '
          '→ hazır. Teslimat: yola çıkış → "Teslim Ettim" (uygulaması '
          'olmayan dükkan kuryesinde hesap kapanışı; dönüş yolunu içerir).',
          style:
              AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.label,
    required this.value,
    this.emphasis,
  });

  final String label;
  final String value;
  final Color? emphasis;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.xs),
            Text(value,
                style: AppTypography.titleLarge.copyWith(
                    color: emphasis ?? AppColors.textPrimary,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({super.key, required this.title, required this.aggregate});

  final String title;
  final CourierReportAggregate aggregate;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: AppTypography.titleMedium
                  .copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${aggregate.packageCount} paket · '
            '${formatTlMinor(aggregate.collectedMinorUnits)} · '
            'Hazırlık ${_minutes(aggregate.averagePreparationMinutes)} · '
            'Teslimat ${_minutes(aggregate.averageDeliveryMinutes)}',
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (aggregate.paymentMethods.isEmpty)
            Text('Tahsilat yok.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary))
          else
            for (final method in aggregate.paymentMethods)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                        child: Text('${method.label} (${method.count})',
                            style: AppTypography.bodySmall)),
                    Text(formatTlMinor(method.amountMinorUnits),
                        style: AppTypography.bodySmall
                            .copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
          const Divider(),
          Row(
            children: [
              const Expanded(
                  child: Text('Kasa Farkı', style: AppTypography.bodySmall)),
              Text(formatTlMinor(aggregate.cashDifferenceMinorUnits),
                  style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.bold,
                      color: aggregate.cashDifferenceMinorUnits < 0
                          ? AppColors.error
                          : AppColors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }
}
