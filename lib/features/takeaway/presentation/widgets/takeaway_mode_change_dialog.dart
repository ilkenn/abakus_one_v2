import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/calendar/signature_calendar.dart';
import '../../data/takeaway_operations_gateway.dart';
import '../../domain/models/branch_takeaway_settings.dart';
import '../providers/takeaway_operations_dependencies_provider.dart';

enum _PauseDurationPreset { thirtyMinutes, oneHour, twoHours, endOfDay, custom }

/// AP-6 Sprint 1 — the three-way takeaway mode-change dialog: Aktif / Yoğun
/// (with a busy-delay chip picker) / Kapat-Mola (with a pause-duration chip
/// picker, including a bespoke-`SignatureCalendar` custom-date option —
/// never the stock Material date picker, per this codebase's own hard UI
/// rule). Mirrors `ReservationProposeChangeDialog`'s exact shape
/// (`AlertDialog` + `TextButton`/`FilledButton`, `AppColors`/
/// `AppTypography`/`AppSpacing`/`AppRadius` tokens only).
///
/// All duration math happens HERE, client-side, resolving to one absolute
/// [DateTime] before the callable is ever invoked — `updateTakeawayOperationStatus`
/// performs no duration arithmetic of its own (mirrors
/// `updateBranchOperatingHours`/`setStandardIngredientCost`'s own
/// "fully-resolved values in" precedent).
class TakeawayModeChangeDialog extends ConsumerStatefulWidget {
  const TakeawayModeChangeDialog({
    super.key,
    required this.organizationId,
    required this.branchId,
    required this.currentStatus,
    required this.currentBusyDelayMinutes,
  });

  final String organizationId;
  final String branchId;
  final TakeawayOperationStatus currentStatus;
  final int currentBusyDelayMinutes;

  @override
  ConsumerState<TakeawayModeChangeDialog> createState() =>
      _TakeawayModeChangeDialogState();
}

class _TakeawayModeChangeDialogState
    extends ConsumerState<TakeawayModeChangeDialog> {
  late TakeawayOperationStatus _status = widget.currentStatus;
  late int _busyDelayMinutes =
      widget.currentBusyDelayMinutes > 0 ? widget.currentBusyDelayMinutes : 15;
  _PauseDurationPreset? _pausePreset;
  DateTime? _customPauseDate;
  bool _isSubmitting = false;
  String? _error;

  DateTime? get _resolvedPausedUntil {
    final now = DateTime.now();
    switch (_pausePreset) {
      case null:
        return null;
      case _PauseDurationPreset.thirtyMinutes:
        return now.add(const Duration(minutes: 30));
      case _PauseDurationPreset.oneHour:
        return now.add(const Duration(hours: 1));
      case _PauseDurationPreset.twoHours:
        return now.add(const Duration(hours: 2));
      case _PauseDurationPreset.endOfDay:
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case _PauseDurationPreset.custom:
        final date = _customPauseDate;
        if (date == null) return null;
        return DateTime(date.year, date.month, date.day, 23, 59, 59);
    }
  }

  bool get _canSubmit {
    if (_isSubmitting) return false;
    if (_status == TakeawayOperationStatus.paused) {
      return _resolvedPausedUntil != null;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref.read(takeawayOperationsGatewayProvider).updateTakeawayOperationStatus(
            organizationId: widget.organizationId,
            branchId: widget.branchId,
            status: _status,
            busyDelayMinutes:
                _status == TakeawayOperationStatus.busy ? _busyDelayMinutes : 0,
            pausedUntil: _status == TakeawayOperationStatus.paused
                ? _resolvedPausedUntil
                : null,
          );
      if (!mounted) return;
      Navigator.pop(context);
    } on TakeawayOperationsException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return AlertDialog(
      title: const Text('Paket Servis Durumu'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusChoiceRow(
                selected: _status,
                onChanged: (status) => setState(() => _status = status),
              ),
              if (_status == TakeawayOperationStatus.busy) ...[
                const SizedBox(height: AppSpacing.lg),
                const Text('Gecikme süresi', style: AppTypography.bodyMedium),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    for (final minutes in kTakeawayBusyDelayMinuteOptions)
                      ChoiceChip(
                        label: Text(minutes == 0 ? 'Gecikme yok' : '+$minutes dk'),
                        selected: _busyDelayMinutes == minutes,
                        onSelected: (_) =>
                            setState(() => _busyDelayMinutes = minutes),
                      ),
                  ],
                ),
              ],
              if (_status == TakeawayOperationStatus.paused) ...[
                const SizedBox(height: AppSpacing.lg),
                const Text('Mola süresi', style: AppTypography.bodyMedium),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    ChoiceChip(
                      label: const Text('30 dk'),
                      selected: _pausePreset == _PauseDurationPreset.thirtyMinutes,
                      onSelected: (_) => setState(
                          () => _pausePreset = _PauseDurationPreset.thirtyMinutes),
                    ),
                    ChoiceChip(
                      label: const Text('1 sa'),
                      selected: _pausePreset == _PauseDurationPreset.oneHour,
                      onSelected: (_) => setState(
                          () => _pausePreset = _PauseDurationPreset.oneHour),
                    ),
                    ChoiceChip(
                      label: const Text('2 sa'),
                      selected: _pausePreset == _PauseDurationPreset.twoHours,
                      onSelected: (_) => setState(
                          () => _pausePreset = _PauseDurationPreset.twoHours),
                    ),
                    ChoiceChip(
                      label: const Text('Gün sonu'),
                      selected: _pausePreset == _PauseDurationPreset.endOfDay,
                      onSelected: (_) => setState(
                          () => _pausePreset = _PauseDurationPreset.endOfDay),
                    ),
                    ChoiceChip(
                      label: const Text('Özel tarih'),
                      selected: _pausePreset == _PauseDurationPreset.custom,
                      onSelected: (_) => setState(
                          () => _pausePreset = _PauseDurationPreset.custom),
                    ),
                  ],
                ),
                if (_pausePreset == _PauseDurationPreset.custom) ...[
                  const SizedBox(height: AppSpacing.md),
                  SignatureCalendar(
                    selectedDate: _customPauseDate,
                    firstSelectableDate: DateTime(now.year, now.month, now.day),
                    lastSelectableDate: DateTime(now.year, now.month, now.day)
                        .add(const Duration(days: 60)),
                    onDateSelected: (date) =>
                        setState(() => _customPauseDate = date),
                  ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: AppRadius.kMedium,
                  ),
                  child: Text(
                    _error!,
                    style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(_isSubmitting ? 'Kaydediliyor...' : 'Kaydet'),
        ),
      ],
    );
  }
}

class _StatusChoiceRow extends StatelessWidget {
  const _StatusChoiceRow({required this.selected, required this.onChanged});

  final TakeawayOperationStatus selected;
  final ValueChanged<TakeawayOperationStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        ChoiceChip(
          label: const Text('Aktif'),
          selected: selected == TakeawayOperationStatus.active,
          onSelected: (_) => onChanged(TakeawayOperationStatus.active),
        ),
        ChoiceChip(
          label: const Text('Yoğun'),
          selected: selected == TakeawayOperationStatus.busy,
          onSelected: (_) => onChanged(TakeawayOperationStatus.busy),
        ),
        ChoiceChip(
          label: const Text('Kapat / Mola'),
          selected: selected == TakeawayOperationStatus.paused,
          onSelected: (_) => onChanged(TakeawayOperationStatus.paused),
        ),
      ],
    );
  }
}
