import '../../../orders/domain/models/order_channel.dart';
import 'modifier_option.dart';

/// Whether a [ModifierGroup] allows one choice (radio-style) or several
/// (checkbox-style).
enum ModifierSelectionType { single, multiple }

/// A named set of [ModifierOption]s attached to a product (e.g. "Protein",
/// "Sos", "Ekstra"), plus the rules governing how many of its options a
/// customer must/may choose.
///
/// [visibleChannels] reuses the existing [OrderChannel] enum rather than
/// inventing a separate channel concept — a modifier group already needs to
/// answer "which ordering channels show this," and that's exactly what
/// [OrderChannel] already models. Defaults to all channels.
class ModifierGroup {
  final String id;
  final String name;
  final ModifierSelectionType selectionType;
  final bool isRequired;
  final int minSelections;
  final int maxSelections;
  final List<ModifierOption> options;
  final Set<OrderChannel> visibleChannels;

  const ModifierGroup({
    required this.id,
    required this.name,
    required this.selectionType,
    this.isRequired = false,
    this.minSelections = 0,
    this.maxSelections = 1,
    required this.options,
    this.visibleChannels = const {
      OrderChannel.dineInQr,
      OrderChannel.dineInStaff,
      OrderChannel.takeaway,
      OrderChannel.delivery,
      OrderChannel.reservationPreorder,
    },
  });

  /// Whether [selectedOptionIds] satisfies this group's min/max/required
  /// rules. A non-required group with zero selections and `minSelections ==
  /// 0` is always valid.
  bool isSatisfiedBy(List<String> selectedOptionIds) {
    final count = selectedOptionIds.length;
    if (isRequired && count == 0) return false;
    if (count < minSelections) return false;
    if (count > maxSelections) return false;
    return true;
  }

  ModifierGroup copyWith({
    String? id,
    String? name,
    ModifierSelectionType? selectionType,
    bool? isRequired,
    int? minSelections,
    int? maxSelections,
    List<ModifierOption>? options,
    Set<OrderChannel>? visibleChannels,
  }) {
    return ModifierGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      selectionType: selectionType ?? this.selectionType,
      isRequired: isRequired ?? this.isRequired,
      minSelections: minSelections ?? this.minSelections,
      maxSelections: maxSelections ?? this.maxSelections,
      options: options ?? this.options,
      visibleChannels: visibleChannels ?? this.visibleChannels,
    );
  }
}
