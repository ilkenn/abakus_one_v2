import 'import_confidence.dart';
import 'parsed_modifier_group.dart';

/// One product extracted from an [ImportSource], not yet an authoritative
/// `MenuProduct` — Phase 7 (`docs/decisions.md` ADR-024). See
/// `ParsedCategory`'s doc comment for why [tempId] is never a real id.
class ParsedProduct {
  const ParsedProduct({
    required this.tempId,
    required this.categoryTempId,
    required this.name,
    this.description,
    this.price,
    this.currencyCode,
    this.imageReference,
    this.modifierGroups = const [],
    this.portionVariants = const [],
    this.isAvailable = true,
    this.skuCode,
    this.taxMetadata,
    this.sourceReference,
    required this.confidence,
  });

  final String tempId;
  final String categoryTempId;
  final String name;
  final String? description;
  final double? price;
  final String? currencyCode;

  /// Opaque reference only, matching `CustomerPhoto.photoRef`/
  /// `ImportFileReference` — never raw image bytes.
  final String? imageReference;

  final List<ParsedModifierGroup> modifierGroups;
  final List<String> portionVariants;
  final bool isAvailable;
  final String? skuCode;
  final String? taxMetadata;
  final String? sourceReference;
  final ImportConfidence confidence;
}
