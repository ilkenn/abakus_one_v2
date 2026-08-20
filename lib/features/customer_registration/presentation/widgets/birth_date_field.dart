import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/calendar/signature_calendar.dart';
import '../../domain/customer_registration_validation.dart';

/// "Doğum Tarihi" picker for "Profilini Tamamla" (CR.1.1). Reuses
/// [SignatureCalendar] entirely unmodified — this repo's documented,
/// tested replacement for a raw Material date picker — wrapped in a
/// year-jump step: [SignatureCalendar]'s own navigation (prev/next month
/// arrows only) fits its 3 existing consumers' near-future reservation
/// dates fine, but is impractical for a birth date up to [kMinBirthYear]
/// years in the past. Lives feature-local rather than under
/// `shared/widgets/` — exactly one consumer today, matching this repo's
/// own "2nd consumer promotes to shared/" convention.
class BirthDateField extends StatelessWidget {
  const BirthDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  /// `null` when nothing has been picked yet.
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String? errorText;

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BirthDateSheet(initialDate: value),
    );
    if (selected != null) onChanged(selected);
  }

  String _formatDisplay(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return InkWell(
      key: const Key('completeProfileBirthDateField'),
      borderRadius: AppRadius.kExtraLarge,
      onTap: () => _openPicker(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Doğum Tarihi',
          prefixIcon: const Icon(Icons.cake_outlined),
          errorText: errorText,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.lg,
          ),
          border: const OutlineInputBorder(
            borderRadius: AppRadius.kExtraLarge,
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.kExtraLarge,
            borderSide: BorderSide(
              color: hasError ? AppColors.error : AppColors.border,
            ),
          ),
        ),
        // The selected value must remain clearly visible before submission
        // (locked requirement) — this Text is the field's permanent,
        // always-rendered display, never hidden behind the picker sheet.
        child: Text(
          value != null ? _formatDisplay(value!) : 'Seç',
          key: const Key('completeProfileBirthDateDisplay'),
          style: AppTypography.bodyLarge.copyWith(
            color:
                value != null ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _BirthDateSheet extends StatefulWidget {
  const _BirthDateSheet({required this.initialDate});

  final DateTime? initialDate;

  @override
  State<_BirthDateSheet> createState() => _BirthDateSheetState();
}

class _BirthDateSheetState extends State<_BirthDateSheet> {
  int? _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialDate?.year;
  }

  @override
  Widget build(BuildContext context) {
    final year = _selectedYear;
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.extraLarge),
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.xl),
        // A modal sheet's Column has no guaranteed available height (it
        // varies with screen size/text scaling) — scrollable rather than
        // fixed prevents a rigid overflow on smaller viewports instead of
        // silently clipping content.
        child: SingleChildScrollView(
          child: year == null
              ? _YearGrid(
                  initialDate: widget.initialDate,
                  onYearSelected: (selectedYear) =>
                      setState(() => _selectedYear = selectedYear),
                )
              : _MonthDayStep(
                  year: year,
                  initialDate: widget.initialDate,
                  onBack: () => setState(() => _selectedYear = null),
                  onDateSelected: (date) => Navigator.of(context).pop(date),
                ),
        ),
      ),
    );
  }
}

class _YearGrid extends StatelessWidget {
  const _YearGrid({required this.initialDate, required this.onYearSelected});

  final DateTime? initialDate;
  final ValueChanged<int> onYearSelected;

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = [for (var y = currentYear; y >= kMinBirthYear; y--) y];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Doğum Yılı', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 360,
          child: GridView.builder(
            key: const Key('birthDateYearGrid'),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 2.2,
            ),
            itemCount: years.length,
            itemBuilder: (context, index) {
              final year = years[index];
              final isSelected = initialDate?.year == year;
              return Material(
                color:
                    isSelected ? AppColors.primary : AppColors.surfaceVariant,
                borderRadius: AppRadius.kMedium,
                child: InkWell(
                  key: Key('birthDateYearOption_$year'),
                  borderRadius: AppRadius.kMedium,
                  onTap: () => onYearSelected(year),
                  child: Center(
                    child: Text(
                      '$year',
                      style: AppTypography.bodyMedium.copyWith(
                        color: isSelected
                            ? AppColors.onPrimary
                            : AppColors.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MonthDayStep extends StatelessWidget {
  const _MonthDayStep({
    required this.year,
    required this.initialDate,
    required this.onBack,
    required this.onDateSelected,
  });

  final int year;
  final DateTime? initialDate;
  final VoidCallback onBack;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isCurrentYear = year == today.year;
    final firstSelectableDate = DateTime(year, 1, 1);
    // Structurally excludes any future date from ever being selectable —
    // the current year is bounded at today, not December 31st.
    final lastSelectableDate = isCurrentYear
        ? DateTime(today.year, today.month, today.day)
        : DateTime(year, 12, 31);
    final selectedDate = initialDate?.year == year ? initialDate : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('birthDateYearBackButton'),
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Yıl değiştir',
              color: AppColors.textPrimary,
              onPressed: onBack,
            ),
            Expanded(
              child: Center(
                child: Text('$year', style: AppTypography.titleMedium),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SignatureCalendar(
          selectedDate: selectedDate,
          firstSelectableDate: firstSelectableDate,
          lastSelectableDate: lastSelectableDate,
          onDateSelected: onDateSelected,
        ),
      ],
    );
  }
}
