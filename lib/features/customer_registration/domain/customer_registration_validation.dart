/// Customer Registration CR.1 — client-side validation/normalization,
/// mirroring `functions/src/completeCustomerProfile.ts`'s server-side
/// rules field-for-field (same trim/length/format checks, same
/// completeness definition) so a rejected submission is caught before a
/// round trip, never contradicted by the server afterward. The server
/// remains the actual authority — these functions exist for UX, not as
/// the security boundary.
library;

import 'models/customer_gender.dart';
import 'models/occupation_status.dart';

const int kMaxNameLength = 80;
// RFC 5321 §4.5.3.1.3 — matches the server-side constant exactly.
const int kMaxEmailLength = 254;
const int kMaxInstitutionLength = 200;
// CR.1.1 — a calendar sanity bound only, NOT a business/legal minimum-age
// rule (the locked product decision explicitly forbids inventing one).
// Matches `functions/src/completeCustomerProfile.ts`'s `MIN_BIRTH_YEAR`
// exactly, so the calendar picker's own selectable range agrees with what
// the server will actually accept.
const int kMinBirthYear = 1900;

final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final RegExp _birthDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// `null` = valid. Matches `TextFormField.validator`'s own contract, so
/// these can be passed directly as a form field's `validator`.
String? validateRequiredName(String? value, {required String fieldLabel}) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return '$fieldLabel gerekli.';
  if (trimmed.length > kMaxNameLength) return '$fieldLabel çok uzun.';
  return null;
}

String? validateEmail(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return 'E-posta adresi gerekli.';
  if (trimmed.length > kMaxEmailLength) return 'E-posta adresi çok uzun.';
  if (!_emailPattern.hasMatch(trimmed)) {
    return 'Geçerli bir e-posta adresi gir.';
  }
  return null;
}

String? validateInstitutionField(String? value, {required String fieldLabel}) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return '$fieldLabel gerekli.';
  if (trimmed.length > kMaxInstitutionLength) return '$fieldLabel çok uzun.';
  return null;
}

/// Trims and lowercases — mirrors the server's own normalization exactly,
/// so what the customer sees echoed back (if ever) matches what's stored.
String normalizeEmail(String value) => value.trim().toLowerCase();

/// The canonical wire/storage representation of a birth date: a
/// zero-padded `"YYYY-MM-DD"` string, date-only, no time component, no
/// timezone suffix — deliberately not [DateTime.toIso8601String], which
/// would append a time-of-day and (for a UTC `DateTime`) a `Z` suffix that
/// has no meaning for a calendar date and that the locked product
/// decision explicitly forbids inventing. Manual zero-padding mirrors
/// this codebase's own existing convention for date string-building (see
/// `account_data_screen.dart`'s day/month/year interpolation) rather than
/// introducing a new formatting utility or package for a single field.
String formatCanonicalBirthDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// `null` = valid. [value] is `null` when nothing has been picked yet —
/// the picker itself structurally prevents a future date or a year before
/// [kMinBirthYear] from ever being selectable, so this exists as a
/// defense-in-depth double-check, not the primary enforcement mechanism.
String? validateBirthDate(DateTime? value) {
  if (value == null) return 'Doğum tarihi gerekli.';
  final today = DateTime.now();
  final todayDateOnly = DateTime(today.year, today.month, today.day);
  final valueDateOnly = DateTime(value.year, value.month, value.day);
  if (valueDateOnly.isAfter(todayDateOnly)) {
    return 'Doğum tarihi gelecekte olamaz.';
  }
  if (value.year < kMinBirthYear) {
    return 'Geçerli bir doğum tarihi seç.';
  }
  return null;
}

/// The one, client-and-server-shared definition of "complete" — mirrors
/// `functions/src/completeCustomerProfile.ts`'s `isProfileComplete`
/// field-for-field. Operates on plain decoded Firestore data
/// (`Map<String, dynamic>?`), never a typed model, so it can be driven
/// directly off a raw `DocumentSnapshot.data()` without an intermediate
/// parsing step this feature doesn't otherwise need.
///
/// Per the audit's own locked instruction: completeness is **never**
/// decided by [membershipExists] alone — every required field on
/// [customerData] is checked independently.
bool isCustomerProfileComplete(
  Map<String, dynamic>? customerData, {
  required bool membershipExists,
}) {
  if (customerData == null) return false;
  if (!membershipExists) return false;

  final firstName = customerData['firstName'];
  if (firstName is! String || firstName.trim().isEmpty) return false;

  final lastName = customerData['lastName'];
  if (lastName is! String || lastName.trim().isEmpty) return false;

  final email = customerData['email'];
  if (email is! String || email.trim().isEmpty) return false;

  final occupationStatusRaw = customerData['occupationStatus'];
  if (occupationStatusRaw is! String ||
      !OccupationStatus.values.any((s) => s.name == occupationStatusRaw)) {
    return false;
  }
  final occupationStatus = OccupationStatus.values.byName(occupationStatusRaw);

  final genderRaw = customerData['gender'];
  if (genderRaw is! String ||
      !CustomerGender.values.any((g) => g.name == genderRaw)) {
    return false;
  }

  final birthDateRaw = customerData['birthDate'];
  if (birthDateRaw is! String || !_birthDatePattern.hasMatch(birthDateRaw)) {
    return false;
  }

  if (customerData['profileCompletedAt'] == null) return false;

  if (occupationStatus == OccupationStatus.working) {
    final workplaceName = customerData['workplaceName'];
    if (workplaceName is! String || workplaceName.trim().isEmpty) {
      return false;
    }
  } else if (occupationStatus == OccupationStatus.student) {
    final institution = customerData['educationalInstitutionName'];
    if (institution is! String || institution.trim().isEmpty) return false;
  }

  return true;
}
