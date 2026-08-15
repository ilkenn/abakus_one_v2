import 'package:flutter/material.dart';

import '../../../../shared/widgets/calendar/signature_calendar.dart';

/// Step 3 — date. Faz R.2 §3/§7: the Signature Calendar is the only
/// date-selection UI; past dates and dates beyond the branch's own
/// `bookingHorizonDays` are disabled client-side for UX, mirroring (never
/// replacing) `submitReservation`'s own authoritative checks.
class DateStep extends StatelessWidget {
  const DateStep({
    super.key,
    required this.selectedDate,
    required this.firstSelectableDate,
    required this.lastSelectableDate,
    required this.onDateSelected,
  });

  final DateTime? selectedDate;
  final DateTime firstSelectableDate;
  final DateTime lastSelectableDate;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    return SignatureCalendar(
      selectedDate: selectedDate,
      firstSelectableDate: firstSelectableDate,
      lastSelectableDate: lastSelectableDate,
      onDateSelected: onDateSelected,
    );
  }
}
