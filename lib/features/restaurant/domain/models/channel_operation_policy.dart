import '../../../orders/domain/models/order_channel.dart';
import 'channel_acceptance_mode.dart';
import 'channel_operational_state.dart';

/// One branch's operational policy for one order channel — whether it
/// accepts new orders automatically or manually, and whether it's
/// currently open/busy/closed to new orders.
///
/// Keyed by `(branchId, channel, externalPlatformCode)` rather than a
/// separate synthetic id: this sprint has at most one *current* policy per
/// that triple, so the natural key is sufficient (mirrors why
/// `PaymentMethodSnapshot` doesn't need its own id either — see
/// `docs/decisions.md`).
///
/// [externalPlatformCode] is `null` for every built-in [OrderChannel]
/// value. It exists so a future external marketplace channel (Getir,
/// Yemeksepeti, Trendyol, ...) can be distinguished under the same
/// `OrderChannel.delivery` value without growing a closed enum per
/// platform — an extensible-catalog choice, not a closed enum, matching
/// `Currency`/`PaymentMethod`'s established pattern rather than
/// `docs/domain_architecture.md`'s older `MarketplaceConnector.platform`
/// enum sketch (unimplemented, and predates that pattern).
///
/// **Append-only**: never mutated in place — every change produces a new
/// instance with the same key and an incremented [revision];
/// `ChannelOperationPolicyRepository.save` always appends.
class ChannelOperationPolicy {
  const ChannelOperationPolicy({
    required this.branchId,
    required this.channel,
    this.externalPlatformCode,
    required this.acceptanceMode,
    required this.operationalState,
    required this.updatedAt,
    required this.updatedByStaffId,
    required this.revision,
  });

  final String branchId;
  final OrderChannel channel;
  final String? externalPlatformCode;

  final ChannelAcceptanceMode acceptanceMode;
  final ChannelOperationalState operationalState;

  final DateTime updatedAt;
  final String updatedByStaffId;

  /// Optimistic-concurrency counter — starts at 1.
  final int revision;

  /// Whether a new order on this channel would currently be accepted.
  bool get acceptsNewOrders =>
      operationalState == ChannelOperationalState.open ||
      operationalState == ChannelOperationalState.busy;

  ChannelOperationPolicy copyWith({
    ChannelAcceptanceMode? acceptanceMode,
    ChannelOperationalState? operationalState,
    DateTime? updatedAt,
    String? updatedByStaffId,
    int? revision,
  }) {
    return ChannelOperationPolicy(
      branchId: branchId,
      channel: channel,
      externalPlatformCode: externalPlatformCode,
      acceptanceMode: acceptanceMode ?? this.acceptanceMode,
      operationalState: operationalState ?? this.operationalState,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByStaffId: updatedByStaffId ?? this.updatedByStaffId,
      revision: revision ?? this.revision,
    );
  }
}
