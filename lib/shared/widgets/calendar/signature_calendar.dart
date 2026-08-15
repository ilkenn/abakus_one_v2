import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// Abaküs's bespoke month-view date picker — Faz R.2 §3, a hard UI
/// requirement: never the stock Material `showDatePicker`/`DatePicker`
/// widget. Built entirely from real widgets (`GridView`, `AnimatedSwitcher`,
/// `AnimatedScale`/`AnimatedContainer`), not a `CustomPainter` — unlike
/// `HeroAbacus` (this codebase's other bespoke-widget precedent, a
/// physics-driven canvas toy), a date picker is a form control with hard
/// accessibility requirements (semantic labels, keyboard/focus on web,
/// text scaling) that a raw canvas would need extensive manual `Semantics`
/// re-implementation to satisfy — real widgets get correct semantics for
/// free. Built entirely from existing `AppColors`/`AppTypography`/
/// `AppSpacing`/`AppRadius`/`AppShadows` tokens — `primaryLight` (sage),
/// `primaryExtraLight` (pale mint), `background` (cream) already carry the
/// "açık krem zemin, adaçayı yeşili" palette this component asks for, so
/// no new widget-local palette class was needed (unlike `HeroAbacusPalette`,
/// which exists precisely because its brand colors have no `AppColors`
/// equivalent).
class SignatureCalendar extends StatefulWidget {
  const SignatureCalendar({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    required this.firstSelectableDate,
    required this.lastSelectableDate,
  });

  /// `null` when nothing is selected yet.
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  /// Inclusive lower bound (branch-local calendar date) — every earlier
  /// date renders disabled. Client-side UX only; `submitReservation`'s own
  /// `MINIMUM_ADVANCE_MINUTES`/operating-hours checks remain authoritative
  /// (Faz R.2 §7 — "Client clock authority DEĞİL").
  final DateTime firstSelectableDate;

  /// Inclusive upper bound — every later date renders disabled, mirroring
  /// (never replacing) the server's own `bookingHorizonDays` check.
  final DateTime lastSelectableDate;

  @override
  State<SignatureCalendar> createState() => _SignatureCalendarState();
}

class _SignatureCalendarState extends State<SignatureCalendar> {
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final anchor = widget.selectedDate ?? widget.firstSelectableDate;
    _visibleMonth = DateTime(anchor.year, anchor.month);
  }

  DateTime get _firstOfMonth =>
      DateTime(_visibleMonth.year, _visibleMonth.month);
  DateTime get _firstOfFirstSelectableMonth => DateTime(
        widget.firstSelectableDate.year,
        widget.firstSelectableDate.month,
      );
  DateTime get _firstOfLastSelectableMonth => DateTime(
        widget.lastSelectableDate.year,
        widget.lastSelectableDate.month,
      );

  bool get _canGoToPreviousMonth =>
      _firstOfMonth.isAfter(_firstOfFirstSelectableMonth);
  bool get _canGoToNextMonth =>
      _firstOfMonth.isBefore(_firstOfLastSelectableMonth);

  void _goToPreviousMonth() {
    if (!_canGoToPreviousMonth) return;
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    });
    HapticFeedback.selectionClick();
  }

  void _goToNextMonth() {
    if (!_canGoToNextMonth) return;
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    });
    HapticFeedback.selectionClick();
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isSelectable(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final first = DateTime(
      widget.firstSelectableDate.year,
      widget.firstSelectableDate.month,
      widget.firstSelectableDate.day,
    );
    final last = DateTime(
      widget.lastSelectableDate.year,
      widget.lastSelectableDate.month,
      widget.lastSelectableDate.day,
    );
    return !normalized.isBefore(first) && !normalized.isAfter(last);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadius.kExtraLarge,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MonthHeader(
            month: _visibleMonth,
            canGoToPreviousMonth: _canGoToPreviousMonth,
            canGoToNextMonth: _canGoToNextMonth,
            onPreviousMonth: _goToPreviousMonth,
            onNextMonth: _goToNextMonth,
          ),
          const SizedBox(height: AppSpacing.md),
          const _WeekdayHeaderRow(),
          const SizedBox(height: AppSpacing.sm),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final slideIn = Tween<Offset>(
                begin: const Offset(0.06, 0),
                end: Offset.zero,
              ).animate(animation);
              return ClipRect(
                child: FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slideIn, child: child),
                ),
              );
            },
            child: _MonthGrid(
              key: ValueKey('${_visibleMonth.year}-${_visibleMonth.month}'),
              month: _visibleMonth,
              selectedDate: widget.selectedDate,
              isSelectable: _isSelectable,
              isSameDate: _isSameDate,
              onDateSelected: widget.onDateSelected,
            ),
          ),
        ],
      ),
    );
  }
}

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

const List<String> _turkishWeekdayShort = [
  'Pt',
  'Sa',
  'Ça',
  'Pe',
  'Cu',
  'Ct',
  'Pz',
];

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.canGoToPreviousMonth,
    required this.canGoToNextMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final DateTime month;
  final bool canGoToPreviousMonth;
  final bool canGoToNextMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MonthNavButton(
          icon: Icons.chevron_left_rounded,
          enabled: canGoToPreviousMonth,
          onPressed: onPreviousMonth,
          semanticLabel: 'Önceki ay',
        ),
        Expanded(
          child: Center(
            child: Semantics(
              header: true,
              child: Text(
                '${_turkishMonthNames[month.month - 1]} ${month.year}',
                style: AppTypography.titleMedium,
              ),
            ),
          ),
        ),
        _MonthNavButton(
          icon: Icons.chevron_right_rounded,
          enabled: canGoToNextMonth,
          onPressed: onNextMonth,
          semanticLabel: 'Sonraki ay',
        ),
      ],
    );
  }
}

class _MonthNavButton extends StatelessWidget {
  const _MonthNavButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
    required this.semanticLabel,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      enabled: enabled,
      child: Material(
        color: enabled ? AppColors.primaryExtraLight : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Icon(
              icon,
              size: 22,
              color: enabled ? AppColors.primary : AppColors.textDisabled,
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekdayHeaderRow extends StatelessWidget {
  const _WeekdayHeaderRow();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        children: [
          for (final label in _turkishWeekdayShort)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    super.key,
    required this.month,
    required this.selectedDate,
    required this.isSelectable,
    required this.isSameDate,
    required this.onDateSelected,
  });

  final DateTime month;
  final DateTime? selectedDate;
  final bool Function(DateTime date) isSelectable;
  final bool Function(DateTime a, DateTime b) isSameDate;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // DateTime.weekday: Monday=1..Sunday=7 — the grid starts Monday.
    final leadingBlanks = firstOfMonth.weekday - 1;
    final today = DateTime.now();
    final todayNormalized = DateTime(today.year, today.month, today.day);

    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _DayCell(
          date: DateTime(month.year, month.month, day),
          isToday: isSameDate(
              DateTime(month.year, month.month, day), todayNormalized),
          isSelected: selectedDate != null &&
              isSameDate(DateTime(month.year, month.month, day), selectedDate!),
          isEnabled: isSelectable(DateTime(month.year, month.month, day)),
          onTap: () => onDateSelected(DateTime(month.year, month.month, day)),
        ),
    ];

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.xs,
      crossAxisSpacing: AppSpacing.xs,
      children: cells,
    );
  }
}

class _DayCell extends StatefulWidget {
  const _DayCell({
    required this.date,
    required this.isToday,
    required this.isSelected,
    required this.isEnabled,
    required this.onTap,
  });

  final DateTime date;
  final bool isToday;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    final Border? border;

    if (widget.isSelected) {
      background = AppColors.primary;
      foreground = AppColors.onPrimary;
      border = null;
    } else if (widget.isToday) {
      background = AppColors.primaryExtraLight;
      foreground = AppColors.primary;
      border = Border.all(color: AppColors.primaryLight, width: 1.5);
    } else if (!widget.isEnabled) {
      background = Colors.transparent;
      foreground = AppColors.textDisabled;
      border = null;
    } else {
      background = Colors.transparent;
      foreground = AppColors.textPrimary;
      border = null;
    }

    final label = widget.isSelected
        ? '${widget.date.day}, seçili'
        : widget.isToday
            ? '${widget.date.day}, bugün'
            : widget.isEnabled
                ? '${widget.date.day}'
                : '${widget.date.day}, kullanılamaz';

    return Semantics(
      button: widget.isEnabled,
      enabled: widget.isEnabled,
      selected: widget.isSelected,
      label: label,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.isEnabled
              ? () {
                  HapticFeedback.selectionClick();
                  widget.onTap();
                }
              : null,
          child: AnimatedScale(
            scale: widget.isSelected ? 1.0 : 0.98,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
                border: border,
              ),
              alignment: Alignment.center,
              child: Text(
                '${widget.date.day}',
                style: AppTypography.bodyMedium.copyWith(
                  color: foreground,
                  fontWeight: widget.isSelected || widget.isToday
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
