import '../../../../shared/models/money.dart';

/// Hourly and per-package compensation rates — **metadata/contract only**.
/// No payroll calculation, payment run, or payout exists anywhere in this
/// phase (explicitly out of scope); this is only what BR-COURIER-002/003
/// already described as DECIDED-but-unimplemented, now given a concrete
/// (still inert) shape.
class CourierCompensationMetadata {
  const CourierCompensationMetadata({this.hourlyRate, this.perPackageRate});

  final Money? hourlyRate;
  final Money? perPackageRate;
}
