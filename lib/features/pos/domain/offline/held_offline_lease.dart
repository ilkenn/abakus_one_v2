/// AP-4 Wave E — the device's own locally-held copy of a server-issued
/// offline authorization lease (`fiscalEngine.ts`'s `OfflineLease`,
/// `FiscalOfflineGateway.issueOfflineLease`'s response). Acquired while
/// still online, held locally so a later loss of connectivity has
/// something to authorize against — the lease itself is the server's own
/// signed decision, never fabricated client-side.
class HeldOfflineLease {
  const HeldOfflineLease({
    required this.leaseId,
    required this.expiresAt,
    required this.allowedTenderTypes,
    required this.maxTransactionCount,
    required this.maxTransactionValueMinorUnits,
    required this.catalogVersion,
    required this.transactionsUsedLocally,
  });

  final String leaseId;
  final DateTime expiresAt;
  final List<String> allowedTenderTypes;
  final int maxTransactionCount;
  final int maxTransactionValueMinorUnits;

  /// Frozen at issuance — an offline capture against a check whose menu/
  /// pricing catalog has since moved on is refused client-side (the
  /// server would refuse it too on sync, but catching it at capture time
  /// means the cashier finds out immediately, not after a failed replay).
  final String catalogVersion;

  /// This device's own local count of transactions captured against this
  /// lease so far — mirrors the server's `transactionsUsed`, advanced
  /// optimistically at capture time (never trusted as the sync-time
  /// authority; the server independently re-checks its own ceiling on
  /// every replay).
  final int transactionsUsedLocally;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get hasRemainingCapacity => transactionsUsedLocally < maxTransactionCount;

  bool allowsTenderType(String tenderType) =>
      allowedTenderTypes.contains(tenderType);

  bool isUsableNow({required String tenderType}) =>
      !isExpired && hasRemainingCapacity && allowsTenderType(tenderType);

  HeldOfflineLease copyWith({int? transactionsUsedLocally}) {
    return HeldOfflineLease(
      leaseId: leaseId,
      expiresAt: expiresAt,
      allowedTenderTypes: allowedTenderTypes,
      maxTransactionCount: maxTransactionCount,
      maxTransactionValueMinorUnits: maxTransactionValueMinorUnits,
      catalogVersion: catalogVersion,
      transactionsUsedLocally:
          transactionsUsedLocally ?? this.transactionsUsedLocally,
    );
  }

  Map<String, Object?> toJson() => {
        'leaseId': leaseId,
        'expiresAt': expiresAt.toIso8601String(),
        'allowedTenderTypes': allowedTenderTypes,
        'maxTransactionCount': maxTransactionCount,
        'maxTransactionValueMinorUnits': maxTransactionValueMinorUnits,
        'catalogVersion': catalogVersion,
        'transactionsUsedLocally': transactionsUsedLocally,
      };

  factory HeldOfflineLease.fromJson(Map<String, Object?> json) {
    return HeldOfflineLease(
      leaseId: json['leaseId'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      allowedTenderTypes:
          List<String>.from(json['allowedTenderTypes'] as List),
      maxTransactionCount: json['maxTransactionCount'] as int,
      maxTransactionValueMinorUnits:
          json['maxTransactionValueMinorUnits'] as int,
      catalogVersion: json['catalogVersion'] as String,
      transactionsUsedLocally: json['transactionsUsedLocally'] as int,
    );
  }
}
