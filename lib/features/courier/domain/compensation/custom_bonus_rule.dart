import '../../../../shared/models/money.dart';

/// A named, flat bonus amount a manager can attach to a
/// [CourierCompensationProfile] — **foundation only**: a flat label +
/// amount, evaluated manually by a manager when creating an adjustment
/// (`CourierEarningsAdjustment`), not an automatic rule-matching engine.
/// No trigger condition/expression language exists — that is deliberately
/// out of scope for this sprint (see `docs/decisions.md` ADR-018).
class CustomBonusRule {
  const CustomBonusRule({
    required this.id,
    required this.label,
    required this.amount,
    this.description = '',
  });

  final String id;
  final String label;
  final Money amount;
  final String description;
}
