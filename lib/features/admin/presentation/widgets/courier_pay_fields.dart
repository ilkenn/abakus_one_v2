import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../courier/domain/pay/courier_pay_models.dart';

/// ADR-085 stage 5 — the courier pay part of the staff add/edit forms:
/// "Dükkan Kuryesi" (hourly + per package) or "Havuz Kuryesi" (per package
/// only, set by an admin/owner), and — stage 6A — "Fatura Keser" (the
/// courier sends invoices; otherwise it is only paid/advanced by an
/// admin/owner). Owns its text controllers; the form that creates it
/// disposes it.
class CourierPayDraft {
  CourierPayDraft({
    this.initial,
    required this.allowPool,
    this.withEffectiveDate = false,
    this.initialIssuesInvoice = false,
  })  : kind = initial?.kind ?? CourierPayKind.shop,
        issuesInvoice = initialIssuesInvoice,
        perPackage = TextEditingController(
            text: initial == null
                ? ''
                : minorUnitsToLiraText(initial.perPackageMinorUnits)),
        hourly = TextEditingController(
            text: initial?.hourlyMinorUnits == null
                ? ''
                : minorUnitsToLiraText(initial!.hourlyMinorUnits!));

  final CourierPayRate? initial;

  /// Admin/owner: may choose (or keep) a pool courier.
  final bool allowPool;

  /// The edit form also asks from which day the new rate applies.
  final bool withEffectiveDate;

  CourierPayKind kind;
  final TextEditingController perPackage;
  final TextEditingController hourly;

  /// `null` = today.
  DateTime? effectiveFrom;

  /// Stage 6A — "Fatura Keser", as it was and as it is now.
  final bool initialIssuesInvoice;
  bool issuesInvoice;

  /// A manager sees a pool courier's rate but cannot change it.
  bool get editable => allowPool || initial?.kind != CourierPayKind.pool;

  /// The typed rate (call after the form validated), or `null` when the
  /// fields are not editable.
  CourierPayRateInput? toInput() {
    if (!editable) return null;
    final perPackageMinor = parseLiraToMinorUnits(perPackage.text);
    final hourlyMinor = parseLiraToMinorUnits(hourly.text);
    if (perPackageMinor == null) return null;
    if (kind == CourierPayKind.shop && hourlyMinor == null) return null;
    final from = effectiveFrom;
    return CourierPayRateInput(
      kind: kind,
      perPackageMinorUnits: perPackageMinor,
      hourlyMinorUnits: kind == CourierPayKind.shop ? hourlyMinor : null,
      effectiveFromDate: from == null ? null : isoDay(from),
      issuesInvoice: issuesInvoice,
    );
  }

  void dispose() {
    perPackage.dispose();
    hourly.dispose();
  }
}

String? _amountError(String? value) {
  final minor = parseLiraToMinorUnits(value ?? '');
  return minor == null ? 'Geçerli bir tutar girin (örn. 45 veya 45,50)' : null;
}

class CourierPayFields extends StatefulWidget {
  const CourierPayFields({super.key, required this.draft});

  final CourierPayDraft draft;

  @override
  State<CourierPayFields> createState() => _CourierPayFieldsState();
}

class _CourierPayFieldsState extends State<CourierPayFields> {
  CourierPayDraft get _draft => widget.draft;

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft.effectiveFrom ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Yeni ücretin başlangıç günü',
    );
    if (picked != null) setState(() => _draft.effectiveFrom = picked);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final editable = draft.editable;
    return Column(
      key: const Key('courierPayFields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Kurye Ücreti', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        if (draft.allowPool || draft.kind == CourierPayKind.pool)
          SegmentedButton<CourierPayKind>(
            key: const Key('courierPayKind'),
            segments: [
              for (final kind in CourierPayKind.values)
                ButtonSegment(
                  value: kind,
                  label: Text(kind.label),
                  enabled: draft.allowPool,
                ),
            ],
            selected: {draft.kind},
            onSelectionChanged: editable && draft.allowPool
                ? (value) => setState(() => draft.kind = value.first)
                : null,
          )
        else
          Text(CourierPayKind.shop.label, style: AppTypography.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          key: const Key('courierPerPackageField'),
          controller: draft.perPackage,
          enabled: editable,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Paket başı ücret',
            suffixText: 'TL',
          ),
          validator: editable ? _amountError : null,
        ),
        if (draft.kind == CourierPayKind.shop) ...[
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('courierHourlyField'),
            controller: draft.hourly,
            enabled: editable,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Saatlik ücret',
              suffixText: 'TL',
            ),
            validator: editable ? _amountError : null,
          ),
        ],
        SwitchListTile(
          key: const Key('courierIssuesInvoice'),
          contentPadding: EdgeInsets.zero,
          value: draft.issuesInvoice,
          onChanged: editable
              ? (value) => setState(() => draft.issuesInvoice = value)
              : null,
          title: const Text('Fatura Keser'),
          subtitle: Text(
            draft.issuesInvoice
                ? 'Kurye hakedişi için uygulamadan fatura yükler.'
                : 'Fatura kesmez; ödeme ve avansı Yönetici veya Sahip girer.',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
        ),
        if (!editable) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Havuz kuryesi ücretini yalnızca Yönetici veya Sahip '
            'değiştirebilir.',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
        if (editable && draft.withEffectiveDate) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            key: const Key('courierPayEffectiveDate'),
            onPressed: _pickDate,
            icon: const Icon(Icons.event_outlined),
            label: Text(draft.effectiveFrom == null
                ? 'Geçerlilik: bugünden itibaren'
                : 'Geçerlilik: ${isoDay(draft.effectiveFrom!)} tarihinden '
                    'itibaren'),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Ücret değişikliği geçmişe uygulanmaz; yazılmış kazançlar '
          'değişmez.',
          style:
              AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
