import 'campaign.dart';

/// Server-Authoritative Campaign Engine P8-B (2026-08-25) — small,
/// screen-agnostic human-readable summaries for [CampaignRule]/
/// [CampaignSchedule], scoped to this feature only (no central date/rule
/// formatter exists yet elsewhere in this codebase). Never a substitute for
/// server-side calculation — these summaries describe the OFFER, they never
/// compute a discount amount themselves.
extension CampaignRuleDisplay on CampaignRule {
  String get summary {
    switch (mechanic) {
      case 'percentage':
        final basisPoints = percentBasisPoints ?? 0;
        final percent = basisPoints / 100;
        final label = percent % 1 == 0
            ? percent.toInt().toString()
            : percent.toStringAsFixed(1);
        return '%$label indirim';
      case 'fixedAmount':
        final minorUnits = amountMinorUnits ?? 0;
        final tl = minorUnits / 100;
        final label =
            tl % 1 == 0 ? tl.toInt().toString() : tl.toStringAsFixed(2);
        return '$label TL indirim';
      case 'freeProduct':
        return 'Ücretsiz ürün';
      case 'buyXGetY':
        return '${triggerQuantity ?? 0} al, ${rewardQuantity ?? 0} bedava';
      default:
        return '';
    }
  }
}

extension CampaignScheduleDisplay on CampaignSchedule {
  String get validitySummary {
    if (mode == 'oneTime') {
      final end = endAt;
      if (end != null) {
        return '${_formatDate(end)} tarihine kadar geçerli';
      }
      return 'Süresiz geçerli';
    }
    return 'Belirli gün ve saatlerde geçerli';
  }
}

String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day.$month.${date.year}';
}
