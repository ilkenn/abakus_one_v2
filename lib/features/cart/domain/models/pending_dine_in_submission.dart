/// One queued-while-offline `submitDineInOrder` request — Self-Order QR
/// Faz 6 (23-rule plan §7, "offline order queueing with auto-flush on
/// reconnect"). Carries the exact same fields `SubmitDineInOrderGateway
/// .submit` accepts, so replaying it later is a direct pass-through —
/// never re-derived or guessed at flush time.
class PendingDineInSubmission {
  const PendingDineInSubmission({
    required this.submissionKey,
    required this.tableSessionId,
    required this.items,
    required this.customerNote,
    this.selectedRewardId,
    this.selectedCampaignId,
    this.guestDisplayName,
    this.submittedCartLineIds = const [],
    required this.queuedAt,
  });

  /// The same idempotency key `submitDineInOrder.ts` already keys on — a
  /// replay after the original attempt actually reached the server first
  /// (a false "offline" read, or a response that arrived after the client
  /// gave up) is safely treated as the existing order, never a duplicate.
  final String submissionKey;
  final String tableSessionId;

  /// Each entry is a `DineInOrderItem.toJson()` map — stored instead of
  /// the sealed class itself so this model needs no knowledge of its two
  /// subtypes to serialize/deserialize.
  final List<Map<String, dynamic>> items;
  final String customerNote;
  final String? selectedRewardId;
  final String? selectedCampaignId;
  final String? guestDisplayName;
  final List<String> submittedCartLineIds;
  final DateTime queuedAt;

  Map<String, dynamic> toJson() => {
        'submissionKey': submissionKey,
        'tableSessionId': tableSessionId,
        'items': items,
        'customerNote': customerNote,
        'selectedRewardId': selectedRewardId,
        'selectedCampaignId': selectedCampaignId,
        'guestDisplayName': guestDisplayName,
        'submittedCartLineIds': submittedCartLineIds,
        'queuedAt': queuedAt.toIso8601String(),
      };

  factory PendingDineInSubmission.fromJson(Map<String, dynamic> json) {
    return PendingDineInSubmission(
      submissionKey: json['submissionKey'] as String,
      tableSessionId: json['tableSessionId'] as String,
      items: (json['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      customerNote: json['customerNote'] as String? ?? '',
      selectedRewardId: json['selectedRewardId'] as String?,
      selectedCampaignId: json['selectedCampaignId'] as String?,
      guestDisplayName: json['guestDisplayName'] as String?,
      submittedCartLineIds:
          (json['submittedCartLineIds'] as List? ?? const []).cast<String>(),
      queuedAt: DateTime.parse(json['queuedAt'] as String),
    );
  }
}
