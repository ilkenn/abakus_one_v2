class NotificationSettingsModel {
  final bool orderStatus;
  final bool courierApproaching;
  final bool campaigns;
  final bool coupons;
  final bool loyaltyPoints;
  final bool accountSecurity; // Önemli hesap bildirimleri (Zorunlu)
  final String systemPermissionStatus; // 'granted', 'denied', 'prompt'

  /// Consent evidence — Sprint 9G (`docs/decisions.md` ADR-026),
  /// `docs/phase9_architecture_analysis.md` §15's own literal spec:
  /// "extend `NotificationSettingsModel` with an explicit consent-
  /// timestamp + accepted-policy-version pair." `null` means never
  /// accepted. The version strings come from
  /// `core/legal/legal_document_version.dart` — currently DRAFT, since no
  /// final legal text exists yet (see that file's own doc comment).
  final DateTime? privacyPolicyAcceptedAt;
  final String? privacyPolicyAcceptedVersion;
  final DateTime? termsAcceptedAt;
  final String? termsAcceptedVersion;

  const NotificationSettingsModel({
    this.orderStatus = true,
    this.courierApproaching = true,
    this.campaigns = true,
    this.coupons = true,
    this.loyaltyPoints = true,
    this.accountSecurity = true,
    this.systemPermissionStatus = 'prompt',
    this.privacyPolicyAcceptedAt,
    this.privacyPolicyAcceptedVersion,
    this.termsAcceptedAt,
    this.termsAcceptedVersion,
  });

  NotificationSettingsModel copyWith({
    bool? orderStatus,
    bool? courierApproaching,
    bool? campaigns,
    bool? coupons,
    bool? loyaltyPoints,
    bool? accountSecurity,
    String? systemPermissionStatus,
    DateTime? privacyPolicyAcceptedAt,
    String? privacyPolicyAcceptedVersion,
    DateTime? termsAcceptedAt,
    String? termsAcceptedVersion,
  }) {
    return NotificationSettingsModel(
      orderStatus: orderStatus ?? this.orderStatus,
      courierApproaching: courierApproaching ?? this.courierApproaching,
      campaigns: campaigns ?? this.campaigns,
      coupons: coupons ?? this.coupons,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      accountSecurity: accountSecurity ?? this.accountSecurity,
      systemPermissionStatus:
          systemPermissionStatus ?? this.systemPermissionStatus,
      privacyPolicyAcceptedAt:
          privacyPolicyAcceptedAt ?? this.privacyPolicyAcceptedAt,
      privacyPolicyAcceptedVersion:
          privacyPolicyAcceptedVersion ?? this.privacyPolicyAcceptedVersion,
      termsAcceptedAt: termsAcceptedAt ?? this.termsAcceptedAt,
      termsAcceptedVersion: termsAcceptedVersion ?? this.termsAcceptedVersion,
    );
  }
}
