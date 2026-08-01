import 'branch_status.dart';

/// A physical/operational location under a [Restaurant] — resurrects
/// `lib/shared/models/branch.dart`'s shape (also dead code before Phase
/// 6) as a real, repository-backed registry entity. **Every existing
/// `branchId` reference across courier/POS/CRM/feedback/restaurant
/// (177 call sites, confirmed by the Phase 6 pre-implementation survey)
/// stays a bare `String`** — this entity is additive, a lookup target
/// those ids can resolve against, not a replacement for how they're
/// already passed around. `docs/decisions.md` ADR-023 documents this
/// explicitly as the "migration/adaptation seam," not a rewrite of every
/// existing `branchId`-typed parameter.
class Branch {
  const Branch({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.status = BranchStatus.active,
    this.contactPhone,
    this.contactEmail,
    this.timezone = 'Europe/Istanbul',
    this.currencyCode = 'TRY',
    this.localeCode = 'tr',
    this.supportedOrderChannelIds = const {},
    this.serviceAreaDescription,
    this.emergencyStopped = false,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String restaurantId;
  final String name;
  final BranchStatus status;
  final String? contactPhone;
  final String? contactEmail;
  final String timezone;
  final String currencyCode;
  final String localeCode;

  /// Raw channel identifiers (e.g. `'dineInQr'`, `'delivery'`), not a
  /// typed `OrderChannel` — `features/admin` deliberately avoids a hard
  /// domain dependency on `features/orders` for one configuration field.
  final Set<String> supportedOrderChannelIds;

  final String? serviceAreaDescription;

  /// "Branch emergency operational stop" — distinct from
  /// `PosAuthorizedAction.emergencyChannelClosure` (Phase 3, per-channel,
  /// per-order-flow) — this is the whole branch, admin-only
  /// (`branchEmergencyStop`).
  final bool emergencyStopped;

  final DateTime createdAt;
  final int revision;

  Branch copyWith({
    String? name,
    BranchStatus? status,
    String? contactPhone,
    bool clearContactPhone = false,
    String? contactEmail,
    bool clearContactEmail = false,
    String? timezone,
    String? currencyCode,
    String? localeCode,
    Set<String>? supportedOrderChannelIds,
    String? serviceAreaDescription,
    bool clearServiceAreaDescription = false,
    bool? emergencyStopped,
    required int revision,
  }) {
    return Branch(
      id: id,
      restaurantId: restaurantId,
      name: name ?? this.name,
      status: status ?? this.status,
      contactPhone:
          clearContactPhone ? null : (contactPhone ?? this.contactPhone),
      contactEmail:
          clearContactEmail ? null : (contactEmail ?? this.contactEmail),
      timezone: timezone ?? this.timezone,
      currencyCode: currencyCode ?? this.currencyCode,
      localeCode: localeCode ?? this.localeCode,
      supportedOrderChannelIds:
          supportedOrderChannelIds ?? this.supportedOrderChannelIds,
      serviceAreaDescription: clearServiceAreaDescription
          ? null
          : (serviceAreaDescription ?? this.serviceAreaDescription),
      emergencyStopped: emergencyStopped ?? this.emergencyStopped,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
