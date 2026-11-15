import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/pay/courier_pay_models.dart';

/// ADR-085 stage 6A — the period chips of both earnings views: Bugün / Bu
/// Hafta / Bu Ay and "Tarih Aralığı Seç" (any two days, at most a year).
/// [selected] is `null` while a custom range is shown.
class CourierPayPeriodBar extends StatelessWidget {
  const CourierPayPeriodBar({
    super.key,
    required this.selected,
    required this.range,
    required this.now,
    required this.onChanged,
    this.keyPrefix = 'earningsPeriod',
  });

  final CourierPayPeriod? selected;
  final CourierPayRange range;
  final DateTime now;
  final void Function(CourierPayPeriod? period, CourierPayRange range)
      onChanged;
  final String keyPrefix;

  Future<void> _pickRange(BuildContext context) async {
    final today = DateUtils.dateOnly(now.toLocal());
    final from = DateTime.tryParse(range.fromDate) ?? today;
    final to = DateTime.tryParse(range.toDate) ?? today;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
      initialDateRange: DateTimeRange(
        start: from.isAfter(today) ? today : from,
        end: to.isAfter(today) ? today : to,
      ),
      helpText: 'Tarih aralığı seçin',
      saveText: 'Göster',
    );
    if (picked == null || !context.mounted) return;
    final days = picked.end.difference(picked.start).inDays;
    if (days >= courierPayMaxRangeDays) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('En fazla 366 günlük bir aralık seçebilirsiniz.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    onChanged(
        null, (fromDate: isoDay(picked.start), toDate: isoDay(picked.end)));
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final period in CourierPayPeriod.values)
          ChoiceChip(
            key: Key('$keyPrefix-${period.name}'),
            label: Text(period.label),
            selected: selected == period,
            onSelected: (_) => onChanged(period, period.range(now)),
          ),
        ChoiceChip(
          key: Key('$keyPrefix-custom'),
          avatar: const Icon(Icons.date_range_outlined, size: 18),
          label: Text(selected == null
              ? '${range.fromDate} – ${range.toDate}'
              : 'Tarih Aralığı Seç'),
          selected: selected == null,
          onSelected: (_) => _pickRange(context),
        ),
      ],
    );
  }
}
