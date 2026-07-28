/// A quick-discount button on the payment/cashier screen — a
/// [percentageBasisPoints] value with a display [name]. Seed data, matching
/// this sprint's approved 5 presets; an Admin Panel is meant to
/// add/remove/enable/disable/reorder these later without a code change,
/// mirroring [PaymentMethod]'s own seed-data pattern.
class DiscountPreset {
  const DiscountPreset({
    required this.id,
    required this.name,
    required this.percentageBasisPoints,
  });

  final String id;
  final String name;

  /// Hundredths of a percent (10.00% = 1000), matching `Discount`'s
  /// convention.
  final int percentageBasisPoints;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DiscountPreset && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
