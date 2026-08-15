import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/calendar/signature_calendar.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../data/admin_reservation_gateway.dart';
import '../../domain/reservations/admin_reservation_error_messages.dart';
import '../providers/admin_reservation_dependencies_provider.dart';

const List<String> _weekdayKeys = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];
const Map<String, String> _weekdayLabels = {
  'monday': 'Pazartesi',
  'tuesday': 'Salı',
  'wednesday': 'Çarşamba',
  'thursday': 'Perşembe',
  'friday': 'Cuma',
  'saturday': 'Cumartesi',
  'sunday': 'Pazar',
};

/// Faz R.3A §14/§15 — branch operating-hours management. Weekly schedule
/// (7 days, multiple intervals per day, closed days simply have zero
/// intervals), date-specific overrides (closed or custom hours,
/// overriding the weekly schedule for that exact date), all against the
/// canonical `branchOperatingHours` model — never a reservation-specific
/// duplicate. Explicit, visible reminder that saving never touches an
/// existing reservation.
class BranchOperatingHoursScreen extends ConsumerStatefulWidget {
  const BranchOperatingHoursScreen({super.key});

  @override
  ConsumerState<BranchOperatingHoursScreen> createState() =>
      _BranchOperatingHoursScreenState();
}

class _BranchOperatingHoursScreenState
    extends ConsumerState<BranchOperatingHoursScreen> {
  Map<String, List<BranchOperatingHoursInterval>>? _weeklySchedule;
  Map<String, BranchOperatingHoursDateOverride>? _dateOverrides;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final snapshot = await ref
          .read(adminReservationGatewayProvider)
          .getBranchOperatingHours(
            organizationId: adminReservationOrganizationId,
            branchId: adminReservationBranchId,
          );
      if (!mounted) return;
      setState(() {
        _weeklySchedule = {
          for (final day in _weekdayKeys)
            day: List.of(snapshot.weeklySchedule[day] ?? const []),
        };
        _dateOverrides = Map.of(snapshot.dateOverrides);
        _isLoading = false;
      });
    } on AdminReservationException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = adminReservationErrorMessage(error);
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    final weeklySchedule = _weeklySchedule;
    if (weeklySchedule == null) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await ref
          .read(adminReservationGatewayProvider)
          .updateBranchOperatingHours(
            organizationId: adminReservationOrganizationId,
            branchId: adminReservationBranchId,
            weeklySchedule: weeklySchedule,
            dateOverrides: _dateOverrides ?? const {},
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Çalışma saatleri güncellendi.')),
      );
    } on AdminReservationException catch (error) {
      if (!mounted) return;
      setState(() => _error = adminReservationErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _addIntervalToDay(String day) async {
    final start = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 11, minute: 0));
    if (start == null || !mounted) return;
    final end = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 23, minute: 0));
    if (end == null || !mounted) return;
    setState(() {
      _weeklySchedule![day] = [
        ...?_weeklySchedule![day],
        BranchOperatingHoursInterval(
            start: _formatTimeOfDay(start), end: _formatTimeOfDay(end)),
      ];
    });
  }

  void _removeIntervalFromDay(String day, int index) {
    setState(() {
      final updated = List.of(_weeklySchedule![day]!)..removeAt(index);
      _weeklySchedule![day] = updated;
    });
  }

  Future<void> _addDateOverride() async {
    final now = DateTime.now();
    DateTime? selectedDate;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tarih İstisnası Ekle'),
          content: SizedBox(
            width: 340,
            child: SignatureCalendar(
              selectedDate: selectedDate,
              firstSelectableDate: DateTime(now.year, now.month, now.day),
              lastSelectableDate: DateTime(now.year, now.month, now.day)
                  .add(const Duration(days: 365)),
              onDateSelected: (date) =>
                  setDialogState(() => selectedDate = date),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Vazgeç')),
            FilledButton(
              onPressed: selectedDate == null
                  ? null
                  : () {
                      final dateKey = _dateKey(selectedDate!);
                      setState(() {
                        _dateOverrides = {
                          ...?_dateOverrides,
                          dateKey: const BranchOperatingHoursDateOverride(
                              closed: true),
                        };
                      });
                      Navigator.pop(context);
                    },
              child: const Text('Kapalı Olarak Ekle'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleOverrideClosed(String dateKey, bool closed) {
    setState(() {
      _dateOverrides = {
        ...?_dateOverrides,
        dateKey: BranchOperatingHoursDateOverride(
          closed: closed,
          intervals: closed
              ? const []
              : (_dateOverrides![dateKey]?.intervals ?? const []),
        ),
      };
    });
  }

  void _removeOverride(String dateKey) {
    setState(() {
      final updated = Map.of(_dateOverrides!)..remove(dateKey);
      _dateOverrides = updated;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Çalışma Saatleri'),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: Text(_isSaving ? 'Kaydediliyor...' : 'Kaydet'),
            ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Çalışma saatleri yükleniyor...')
            : _error != null && _weeklySchedule == null
                ? ErrorView(
                    message: _error!, retryLabel: 'Tekrar Dene', onRetry: _load)
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: const BoxDecoration(
                            color: AppColors.primaryExtraLight,
                            borderRadius: AppRadius.kMedium,
                          ),
                          child: Text(
                            'Saat değişikliği mevcut rezervasyonları etkilemez veya iptal etmez. '
                            'Çakışma oluşursa personel manuel olarak yönetmelidir.',
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (_error != null) ...[
                          Text(_error!,
                              style: AppTypography.bodySmall
                                  .copyWith(color: AppColors.error)),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        const Text('Haftalık Program',
                            style: AppTypography.titleLarge),
                        const SizedBox(height: AppSpacing.sm),
                        for (final day in _weekdayKeys)
                          _DayScheduleRow(
                            day: day,
                            intervals: _weeklySchedule![day] ?? const [],
                            onAddInterval: () => _addIntervalToDay(day),
                            onRemoveInterval: (index) =>
                                _removeIntervalFromDay(day, index),
                          ),
                        const SizedBox(height: AppSpacing.xl),
                        Row(
                          children: [
                            const Expanded(
                                child: Text('Tarih İstisnaları',
                                    style: AppTypography.titleLarge)),
                            TextButton.icon(
                              onPressed: _addDateOverride,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Ekle'),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if ((_dateOverrides ?? const {}).isEmpty)
                          Text(
                            'Tanımlı tarih istisnası yok.',
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        for (final entry
                            in (_dateOverrides ?? const {}).entries)
                          _DateOverrideRow(
                            dateKey: entry.key,
                            dateOverride: entry.value,
                            onToggleClosed: (closed) =>
                                _toggleOverrideClosed(entry.key, closed),
                            onRemove: () => _removeOverride(entry.key),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _DayScheduleRow extends StatelessWidget {
  const _DayScheduleRow({
    required this.day,
    required this.intervals,
    required this.onAddInterval,
    required this.onRemoveInterval,
  });

  final String day;
  final List<BranchOperatingHoursInterval> intervals;
  final VoidCallback onAddInterval;
  final ValueChanged<int> onRemoveInterval;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 100,
              child:
                  Text(_weekdayLabels[day]!, style: AppTypography.bodyMedium)),
          Expanded(
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (intervals.isEmpty)
                  Text('Kapalı',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                for (var i = 0; i < intervals.length; i++)
                  Chip(
                    label: Text('${intervals[i].start}–${intervals[i].end}'),
                    onDeleted: () => onRemoveInterval(i),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Ekle'),
                  onPressed: onAddInterval,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DateOverrideRow extends StatelessWidget {
  const _DateOverrideRow({
    required this.dateKey,
    required this.dateOverride,
    required this.onToggleClosed,
    required this.onRemove,
  });

  final String dateKey;
  final BranchOperatingHoursDateOverride dateOverride;
  final ValueChanged<bool> onToggleClosed;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.kMedium,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(child: Text(dateKey, style: AppTypography.bodyMedium)),
          Switch(
            value: dateOverride.closed,
            onChanged: onToggleClosed,
          ),
          Text(dateOverride.closed ? 'Kapalı' : 'Özel Saat',
              style: AppTypography.bodySmall),
          IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              onPressed: onRemove),
        ],
      ),
    );
  }
}

String _formatTimeOfDay(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

String _dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
