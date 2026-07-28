import 'discount_preset.dart';

/// The 5 built-in quick-discount presets this sprint ships with —
/// %5/%10/%15/%20/%25, per the approved architecture decision.
abstract final class DiscountPresetSeedData {
  DiscountPresetSeedData._();

  static const DiscountPreset fivePercent = DiscountPreset(
    id: 'discount_preset_5',
    name: '%5',
    percentageBasisPoints: 500,
  );

  static const DiscountPreset tenPercent = DiscountPreset(
    id: 'discount_preset_10',
    name: '%10',
    percentageBasisPoints: 1000,
  );

  static const DiscountPreset fifteenPercent = DiscountPreset(
    id: 'discount_preset_15',
    name: '%15',
    percentageBasisPoints: 1500,
  );

  static const DiscountPreset twentyPercent = DiscountPreset(
    id: 'discount_preset_20',
    name: '%20',
    percentageBasisPoints: 2000,
  );

  static const DiscountPreset twentyFivePercent = DiscountPreset(
    id: 'discount_preset_25',
    name: '%25',
    percentageBasisPoints: 2500,
  );

  static const List<DiscountPreset> all = [
    fivePercent,
    tenPercent,
    fifteenPercent,
    twentyPercent,
    twentyFivePercent,
  ];
}
