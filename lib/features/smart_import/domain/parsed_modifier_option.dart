/// One modifier choice extracted from an [ImportSource] — Phase 7
/// (`docs/decisions.md` ADR-024).
class ParsedModifierOption {
  const ParsedModifierOption({
    required this.tempId,
    required this.name,
    this.extraPrice,
  });

  final String tempId;
  final String name;
  final double? extraPrice;
}
