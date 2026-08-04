import 'integration_credential_kind.dart';

/// A tenant's stored secret for a provider — **metadata only**, Phase 8
/// (`docs/decisions.md` ADR-025). The actual secret value is never a
/// field here, never returned by any query on this type, and never
/// appears in an audit description — this record only says *that* a
/// credential of [kind] exists and *where* its real value is stored
/// ([storageKey], an opaque key into `IntegrationCredentialStorage`,
/// never the value itself). Mirrors `CustomerPhoto.photoRef`'s "opaque
/// reference, never raw bytes" boundary (Phase 6, `docs/decisions.md`
/// ADR-023 Decision 5), applied to secrets instead of images.
class IntegrationCredentialRef {
  const IntegrationCredentialRef({
    required this.id,
    required this.organizationId,
    required this.providerId,
    required this.kind,
    required this.storageKey,
    this.revoked = false,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String providerId;
  final IntegrationCredentialKind kind;

  /// The key `IntegrationCredentialStorage.readValue`/`writeValue` uses
  /// — an opaque string, never the secret value itself.
  final String storageKey;

  final bool revoked;
  final DateTime createdAt;
  final int revision;

  IntegrationCredentialRef copyWith({
    bool? revoked,
    required int revision,
  }) {
    return IntegrationCredentialRef(
      id: id,
      organizationId: organizationId,
      providerId: providerId,
      kind: kind,
      storageKey: storageKey,
      revoked: revoked ?? this.revoked,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
