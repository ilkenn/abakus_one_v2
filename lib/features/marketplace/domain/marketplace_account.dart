import 'marketplace_account_status.dart';

/// One tenant's account with a marketplace provider — Phase 8
/// (`docs/decisions.md` ADR-025), the "Provider → Marketplace Account"
/// step of the kickoff's own hierarchy. **A tenant may own multiple
/// accounts under the same provider** (e.g. two separate Yemeksepeti
/// seller accounts for two legally-distinct entities) — [id] is the
/// identity, never `(organizationId, providerId)`, which is
/// deliberately *not* unique. "Never assume 1 provider, 1 account, 1
/// restaurant."
class MarketplaceAccount {
  const MarketplaceAccount({
    required this.id,
    required this.organizationId,
    required this.providerId,
    required this.accountLabel,
    this.status = MarketplaceAccountStatus.active,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;

  /// References `IntegrationProviderAdapter.providerId` in the
  /// platform's `IntegrationProviderRegistry` (Phase 8G).
  final String providerId;

  /// A tenant-chosen label distinguishing this account from any other
  /// under the same [providerId] — e.g. "Yemeksepeti - Kadıköy Şubesi".
  final String accountLabel;

  final MarketplaceAccountStatus status;
  final DateTime createdAt;
  final int revision;

  MarketplaceAccount copyWith({
    String? accountLabel,
    MarketplaceAccountStatus? status,
    required int revision,
  }) {
    return MarketplaceAccount(
      id: id,
      organizationId: organizationId,
      providerId: providerId,
      accountLabel: accountLabel ?? this.accountLabel,
      status: status ?? this.status,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
