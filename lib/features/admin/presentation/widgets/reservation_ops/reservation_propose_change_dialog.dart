import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../shared/widgets/calendar/signature_calendar.dart';
import '../../../data/admin_reservation_gateway.dart';
import '../../../domain/reservations/admin_reservation_error_messages.dart';
import '../../../domain/reservations/admin_reservation_summary.dart';
import '../../providers/admin_reservation_dependencies_provider.dart';
import '../../providers/admin_reservation_detail_provider.dart';

const List<String> _monthNames = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// Faz R.3A §9 — staff propose an alternative date/time/area. Reuses the
/// same Signature Calendar the customer flow uses (this is the one place
/// admin genuinely benefits from the identical widget — the underlying
/// interaction, "pick a date," is the same regardless of who's picking).
/// Availability-aware per the requirement: a known-unavailable slot is
/// never silently selectable as if it were fine — the backend's own
/// capacity check remains authoritative and this dialog surfaces its
/// rejection directly, never guesses at availability client-side.
class ReservationProposeChangeDialog extends ConsumerStatefulWidget {
  const ReservationProposeChangeDialog({super.key, required this.reservation});

  final AdminReservationSummary reservation;

  @override
  ConsumerState<ReservationProposeChangeDialog> createState() =>
      _ReservationProposeChangeDialogState();
}

class _ReservationProposeChangeDialogState
    extends ConsumerState<ReservationProposeChangeDialog> {
  DateTime? _date;
  TimeOfDay? _time;
  String? _areaId;
  bool _isSubmitting = false;
  String? _error;

  Future<void> _submit() async {
    final date = _date;
    final time = _time;
    final areaId = _areaId;
    if (date == null || time == null || areaId == null) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final proposedTime =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    try {
      await ref.read(adminReservationGatewayProvider).proposeChange(
            reservationId: widget.reservation.id,
            proposedTime: proposedTime,
            proposedAreaId: areaId,
          );
      if (!mounted) return;
      Navigator.pop(context);
    } on AdminReservationException catch (error) {
      if (!mounted) return;
      setState(() => _error = adminReservationErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final areasAsync = ref.watch(adminReservationBranchAreasProvider);
    final now = DateTime.now();

    return AlertDialog(
      title: const Text('Alternatif Öner'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Talep edilen: ${_formatDateTime(widget.reservation.requestedTime)}',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              SignatureCalendar(
                selectedDate: _date,
                firstSelectableDate: DateTime(now.year, now.month, now.day),
                lastSelectableDate: DateTime(now.year, now.month, now.day)
                    .add(const Duration(days: 60)),
                onDateSelected: (date) => setState(() => _date = date),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label:
                    Text(_time == null ? 'Saat Seç' : _time!.format(context)),
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _time ?? const TimeOfDay(hour: 19, minute: 0),
                  );
                  if (picked != null) setState(() => _time = picked);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              areasAsync.maybeWhen(
                data: (areas) => DropdownButtonFormField<String>(
                  initialValue: _areaId,
                  decoration: const InputDecoration(labelText: 'Alan'),
                  items: [
                    for (final area in areas)
                      DropdownMenuItem(
                          value: area.id, child: Text(area.displayName)),
                  ],
                  onChanged: (value) => setState(() => _areaId = value),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: AppRadius.kMedium),
                  child: Text(_error!,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.error)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç')),
        FilledButton(
          onPressed: (_date != null &&
                  _time != null &&
                  _areaId != null &&
                  !_isSubmitting)
              ? _submit
              : null,
          child: Text(_isSubmitting ? 'Gönderiliyor...' : 'Öneriyi Gönder'),
        ),
      ],
    );
  }
}

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  return '${local.day} ${_monthNames[local.month - 1]} ${local.year}, '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
