import '../../../../core/errors/business_rule_violation.dart';

/// The deterministic outcome of validating a set of modifier selections
/// against a `ModifierGroup` — never throws; every rejection reason is
/// collected into [ModifierValidationInvalid.violations] instead, so a
/// caller (e.g. a POS screen) can show every problem at once rather than
/// one exception at a time.
sealed class ModifierValidationResult {
  const ModifierValidationResult();

  bool get isValid => this is ModifierValidationValid;
}

final class ModifierValidationValid extends ModifierValidationResult {
  const ModifierValidationValid();
}

final class ModifierValidationInvalid extends ModifierValidationResult {
  ModifierValidationInvalid(this.violations)
      : assert(violations.isNotEmpty, 'must carry at least one violation');

  final List<BusinessRuleViolation> violations;
}
