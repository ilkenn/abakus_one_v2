import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/build_courier_earnings_summary.dart';
import '../../application/use_cases/create_courier_compensation_profile.dart';
import '../../application/use_cases/create_courier_earnings_adjustment.dart';
import '../../application/use_cases/mark_courier_earnings_paid.dart';
import '../../domain/compensation/courier_compensation_profile.dart';
import '../../domain/compensation/courier_earnings_adjustment_reason.dart';
import '../../domain/compensation/courier_earnings_summary.dart';
import '../providers/courier_dependencies_provider.dart';

/// Manager-facing compensation panel for one courier — "create
/// compensation profiles, assign different compensation to every courier,
/// schedule future raises, view historical profile versions, preview
/// calculated earnings, approve adjustments, mark earnings as paid. Never
/// edit historical profiles." Every profile shown is read-only; the only
/// way to change a courier's rates is [_openCreateProfileDialog], which
/// always creates a brand-new version.
class ManagerCourierCompensationScreen extends ConsumerStatefulWidget {
  const ManagerCourierCompensationScreen({
    super.key,
    required this.courierId,
    required this.branchId,
    this.authorizationPolicy,
    this.performedByStaffId = 'manager-1',
  });

  final String courierId;
  final String branchId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<ManagerCourierCompensationScreen> createState() =>
      _ManagerCourierCompensationScreenState();
}

/// Converts a manager-entered whole/decimal TRY string into [Money] —
/// rounds to the nearest kuruş, ties away from zero. A screen-local
/// conversion rather than reusing `Money.fromLegacyDoubleTry` (that
/// factory's own doc comment restricts it to the cart-to-order mapper
/// boundary specifically).
Money? _parseTryInput(String text) {
  final trimmed = text.trim().replaceAll(',', '.');
  if (trimmed.isEmpty) return null;
  final value = double.tryParse(trimmed);
  if (value == null) return null;
  final minorUnits =
      (value * Currency.accountingCurrency.minorUnitsPerWhole).round();
  return Money(minorUnits, Currency.accountingCurrency);
}

class _ManagerCourierCompensationScreenState
    extends ConsumerState<ManagerCourierCompensationScreen> {
  List<CourierCompensationProfile>? _profiles;
  CourierEarningsSummary? _summary;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  ({DateTime start, DateTime end}) get _currentMonthRange {
    final now = DateTime.now();
    return (
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 1),
    );
  }

  Future<void> _load() async {
    final profiles = await ref
        .read(courierCompensationProfileRepositoryProvider)
        .findAllByCourierId(widget.courierId);
    final range = _currentMonthRange;
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
    setState(() {
      _profiles = profiles.reversed.toList();
      _summary = summary;
    });
  }

  Future<void> _createProfile({
    required DateTime effectiveFrom,
    Money? hourlyRate,
    Money? deliveryFeePerPackage,
    required double freeDistanceKm,
    Money? extraDistanceRatePerKm,
    Money? fixedShiftAllowance,
  }) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _message = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await CreateCourierCompensationProfile(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        idGenerator: ref.read(courierCompensationProfileIdGeneratorProvider),
        repository: ref.read(courierCompensationProfileRepositoryProvider),
        auditRepository:
            ref.read(courierOperationalAuditEntryRepositoryProvider),
      )(
        courierId: widget.courierId,
        branchId: widget.branchId,
        effectiveFrom: effectiveFrom,
        hourlyRate: hourlyRate,
        deliveryFeePerPackage: deliveryFeePerPackage,
        freeDistanceKm: freeDistanceKm,
        extraDistanceRatePerKm: extraDistanceRatePerKm,
        fixedShiftAllowance: fixedShiftAllowance,
        performedByStaffId: widget.performedByStaffId,
      );
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  Future<void> _createAdjustment({
    required CourierEarningsAdjustmentReason reason,
    required Money amount,
    required String notes,
  }) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _message = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await CreateCourierEarningsAdjustment(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        idGenerator: ref.read(courierEarningsAdjustmentIdGeneratorProvider),
        repository: ref.read(courierEarningsAdjustmentRepositoryProvider),
        auditRepository:
            ref.read(courierOperationalAuditEntryRepositoryProvider),
      )(
        courierId: widget.courierId,
        branchId: widget.branchId,
        reason: reason,
        amount: amount,
        notes: notes,
        performedByStaffId: widget.performedByStaffId,
      );
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  Future<void> _markPending() async {
    final summary = _summary;
    final policy = widget.authorizationPolicy;
    if (summary == null) return;
    if (policy == null) {
      setState(() => _message = 'Yetki politikası tanımlı değil.');
      return;
    }
    if (summary.pendingAmount.isZero) {
      setState(() => _message = 'Bekleyen ödeme yok.');
      return;
    }
    final range = _currentMonthRange;
    final deliveryEarnings = await ref
        .read(deliveryEarningsRepositoryProvider)
        .findByCourierIdAndPeriod(
            courierId: widget.courierId,
            periodStart: range.start,
            periodEnd: range.end);
    final shiftEarnings = await ref
        .read(shiftHourlyEarningsRepositoryProvider)
        .findByCourierIdAndPeriod(
            courierId: widget.courierId,
            periodStart: range.start,
            periodEnd: range.end);
    final adjustments = await ref
        .read(courierEarningsAdjustmentRepositoryProvider)
        .findByCourierIdAndPeriod(
            courierId: widget.courierId,
            periodStart: range.start,
            periodEnd: range.end);

    final paymentRepository =
        ref.read(courierEarningsPaymentRepositoryProvider);
    final unpaidDeliveryIds = <String>[];
    for (final e in deliveryEarnings) {
      if ((await paymentRepository.findByReferencedId(e.id)).isEmpty) {
        unpaidDeliveryIds.add(e.id);
      }
    }
    final unpaidShiftIds = <String>[];
    for (final e in shiftEarnings) {
      if ((await paymentRepository.findByReferencedId(e.id)).isEmpty) {
        unpaidShiftIds.add(e.id);
      }
    }
    final unpaidAdjustmentIds = <String>[];
    for (final a in adjustments) {
      if ((await paymentRepository.findByReferencedId(a.id)).isEmpty) {
        unpaidAdjustmentIds.add(a.id);
      }
    }

    try {
      await MarkCourierEarningsPaid(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        idGenerator: ref.read(courierEarningsPaymentIdGeneratorProvider),
        repository: paymentRepository,
        auditRepository:
            ref.read(courierOperationalAuditEntryRepositoryProvider),
      )(
        courierId: widget.courierId,
        branchId: widget.branchId,
        periodStart: range.start,
        periodEnd: range.end,
        totalAmount: summary.pendingAmount,
        deliveryEarningsIds: unpaidDeliveryIds,
        shiftEarningsIds: unpaidShiftIds,
        adjustmentIds: unpaidAdjustmentIds,
        performedByStaffId: widget.performedByStaffId,
      );
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  Future<void> _openCreateProfileDialog() async {
    final hourlyController = TextEditingController();
    final perPackageController = TextEditingController();
    final freeDistanceController = TextEditingController(text: '0');
    final extraDistanceRateController = TextEditingController();
    final allowanceController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Ücret Profili'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: hourlyController,
                decoration:
                    const InputDecoration(labelText: 'Saatlik Ücret (TL)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: perPackageController,
                decoration:
                    const InputDecoration(labelText: 'Paket Başı Ücret (TL)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: freeDistanceController,
                decoration:
                    const InputDecoration(labelText: 'Ücretsiz Mesafe (km)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: extraDistanceRateController,
                decoration: const InputDecoration(
                    labelText: 'Ekstra Km Ücreti (TL/km)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: allowanceController,
                decoration: const InputDecoration(
                    labelText: 'Sabit Vardiya Ödeneği (TL)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _createProfile(
      effectiveFrom: DateTime.now(),
      hourlyRate: _parseTryInput(hourlyController.text),
      deliveryFeePerPackage: _parseTryInput(perPackageController.text),
      freeDistanceKm: double.tryParse(freeDistanceController.text.trim()) ?? 0,
      extraDistanceRatePerKm: _parseTryInput(extraDistanceRateController.text),
      fixedShiftAllowance: _parseTryInput(allowanceController.text),
    );
  }

  Future<void> _openCreateAdjustmentDialog() async {
    var selectedReason = CourierEarningsAdjustmentReason.manualCorrection;
    final amountController = TextEditingController();
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Kazanç Düzeltmesi'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<CourierEarningsAdjustmentReason>(
                  initialValue: selectedReason,
                  items: [
                    for (final reason in CourierEarningsAdjustmentReason.values)
                      DropdownMenuItem(value: reason, child: Text(reason.name)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedReason = value);
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Sebep'),
                ),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(
                      labelText: 'Tutar (TL, negatif olabilir)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(signed: true),
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Not'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final amount = _parseTryInput(amountController.text);
    if (amount == null) return;
    await _createAdjustment(
      reason: selectedReason,
      amount: amount,
      notes: notesController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles;
    final summary = _summary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kurye Ücretlendirme'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: profiles == null || summary == null
            ? const LoadingView(message: 'Yükleniyor...')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (_message != null) ...[
                    Text(_message!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.error)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  _buildPreviewCard(summary),
                  const SizedBox(height: AppSpacing.lg),
                  _buildProfilesCard(profiles),
                  const SizedBox(height: AppSpacing.lg),
                  _buildActionsCard(),
                ],
              ),
      ),
    );
  }

  Widget _buildPreviewCard(CourierEarningsSummary summary) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bu Ay Kazanç Önizlemesi',
              style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text('Brüt: ${summary.grossEarnings}',
              style: AppTypography.bodyMedium),
          Text('Ödenen: ${summary.paidAmount}',
              style: AppTypography.bodyMedium),
          Text('Bekleyen: ${summary.pendingAmount}',
              style:
                  AppTypography.bodyMedium.copyWith(color: AppColors.warning)),
          const SizedBox(height: AppSpacing.sm),
          ElevatedButton(
            onPressed: _markPending,
            child: const Text('Bekleyeni Ödendi Olarak İşaretle'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilesCard(List<CourierCompensationProfile> profiles) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Ücret Profilleri (Geçmiş)',
                  style: AppTypography.titleMedium),
              TextButton(
                onPressed: _openCreateProfileDialog,
                child: const Text('+ Yeni'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (profiles.isEmpty)
            const EmptyView(
              icon: Icons.payments_outlined,
              message: 'Henüz ücret profili tanımlanmadı',
            )
          else
            for (final profile in profiles)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('v${profile.version} — ${profile.effectiveFrom}'),
                subtitle: Text('Saatlik: ${profile.hourlyRate ?? '-'} • Paket: '
                    '${profile.deliveryFeePerPackage ?? '-'} • Ücretsiz: '
                    '${profile.freeDistanceKm} km'),
                trailing: profile.isActive
                    ? const Icon(Icons.check_circle, color: AppColors.success)
                    : const Icon(Icons.block, color: AppColors.textSecondary),
              ),
        ],
      ),
    );
  }

  Widget _buildActionsCard() {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Düzeltmeler', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: _openCreateAdjustmentDialog,
            child: const Text('Kazanç Düzeltmesi Ekle'),
          ),
        ],
      ),
    );
  }
}
