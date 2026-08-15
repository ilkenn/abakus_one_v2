import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../../shared/widgets/feedback/error_view.dart';
import '../../../../../shared/widgets/feedback/loading_view.dart';
import '../../../data/admin_reservation_gateway.dart';
import '../../../domain/reservations/admin_reservation_error_messages.dart';
import '../../providers/admin_reservation_detail_provider.dart';
import '../../providers/admin_reservation_list_provider.dart';
import 'reservation_list_card.dart';

const List<String> _turkishWeekdayLong = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];
const List<String> _turkishMonthNames = [
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

/// Faz R.3A §3 — the operations calendar: a day-oriented, density-focused
/// agenda (never the customer Signature Calendar copied wholesale — a
/// deliberately different design for a deliberately different job).
/// Reservations for the selected day, grouped by hour, with an area
/// filter — the exact fields §3 asks for (hour grouping stands in for a
/// literal timeline: at typical service volume this reads faster than an
/// absolute-pixel-positioned grid would, and needs no new bespoke layout
/// primitive).
class ReservationCalendarView extends ConsumerStatefulWidget {
  const ReservationCalendarView({super.key, required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  ConsumerState<ReservationCalendarView> createState() =>
      _ReservationCalendarViewState();
}

class _ReservationCalendarViewState
    extends ConsumerState<ReservationCalendarView> {
  late DateTime _selectedDate;
  String? _areaId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  void _shiftDay(int deltaDays) {
    setState(
        () => _selectedDate = _selectedDate.add(Duration(days: deltaDays)));
  }

  @override
  Widget build(BuildContext context) {
    final dateFrom = _selectedDate;
    final dateTo = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
    final query = AdminReservationListQuery(
      dateFrom: dateFrom,
      dateTo: dateTo,
      areaId: _areaId,
      pageSize: 100,
    );
    final areasAsync = ref.watch(adminReservationBranchAreasProvider);
    final pageAsync = ref.watch(adminReservationListProvider(query));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => _shiftDay(-1),
                tooltip: 'Önceki gün',
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_turkishWeekdayLong[_selectedDate.weekday - 1]}, '
                    '${_selectedDate.day} ${_turkishMonthNames[_selectedDate.month - 1]} ${_selectedDate.year}',
                    style: AppTypography.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => _shiftDay(1),
                tooltip: 'Sonraki gün',
              ),
              const SizedBox(width: AppSpacing.sm),
              areasAsync.maybeWhen(
                data: (areas) => DropdownButton<String?>(
                  value: _areaId,
                  hint: const Text('Tüm Alanlar'),
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Tüm Alanlar')),
                    for (final area in areas)
                      DropdownMenuItem<String?>(
                          value: area.id, child: Text(area.displayName)),
                  ],
                  onChanged: (value) => setState(() => _areaId = value),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        Expanded(
          child: pageAsync.when(
            loading: () => const LoadingView(message: 'Takvim yükleniyor...'),
            error: (error, stackTrace) => ErrorView(
              message: error is AdminReservationException
                  ? adminReservationErrorMessage(error)
                  : 'Takvim yüklenirken bir sorun oluştu.',
              retryLabel: 'Tekrar Dene',
              onRetry: () =>
                  ref.invalidate(adminReservationListProvider(query)),
            ),
            data: (page) {
              if (page.reservations.isEmpty) {
                return const EmptyView(
                  icon: Icons.event_available_rounded,
                  message: 'Bu gün için rezervasyon bulunmuyor.',
                );
              }
              final byHour = <int, List<dynamic>>{};
              for (final reservation in page.reservations) {
                final hour = reservation.effectiveTime.toLocal().hour;
                byHour.putIfAbsent(hour, () => []).add(reservation);
              }
              final sortedHours = byHour.keys.toList()..sort();
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  for (final hour in sortedHours) ...[
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm, vertical: 2),
                            decoration: const BoxDecoration(
                              color: AppColors.primaryExtraLight,
                              borderRadius: AppRadius.kPill,
                            ),
                            child: Text(
                              '${hour.toString().padLeft(2, '0')}:00',
                              style: AppTypography.labelMedium
                                  .copyWith(color: AppColors.primary),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          const Expanded(child: Divider()),
                        ],
                      ),
                    ),
                    for (final reservation in byHour[hour]!) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: ReservationListCard(
                          reservation: reservation,
                          onTap: () => widget.onSelect(reservation.id),
                        ),
                      ),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
