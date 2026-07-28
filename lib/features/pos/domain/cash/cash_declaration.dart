import '../../../../shared/models/money.dart';

/// The cashier's raw declaration of the physical cash actually present in
/// the drawer — a value object embedded in [CashCount], distinct from the
/// *expected* amount `CashCount` computes independently from recorded
/// `CashMovement`s. No denomination-level breakdown is modeled this
/// sprint (a lump-sum count, plus free-text notes) — a per-denomination
/// breakdown would be additive, not a breaking change, if ever needed.
class CashDeclaration {
  const CashDeclaration({required this.actualAmount, this.notes = ''});

  final Money actualAmount;
  final String notes;
}
