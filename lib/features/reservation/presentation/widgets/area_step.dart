import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/cards/option_selection_card.dart';
import '../../domain/models/reservation_area.dart';

/// Step 2 — reservation area. Faz R.2 §6: the customer never selects a
/// physical table, only a branch-configurable area (`getReservationBranchInfo`'s
/// own server-driven list — nothing hardcoded here, so a different tenant's
/// "Teras"/"VIP"/"Salon" set works unmodified).
class AreaStep extends StatelessWidget {
  const AreaStep({
    super.key,
    required this.areas,
    required this.selectedAreaId,
    required this.onSelected,
  });

  final List<ReservationArea> areas;
  final String? selectedAreaId;
  final ValueChanged<ReservationArea> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final area in areas) ...[
          OptionSelectionCard(
            name: area.displayName,
            extraPrice: 0,
            isSelected: selectedAreaId == area.id,
            onTap: () => onSelected(area),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}
