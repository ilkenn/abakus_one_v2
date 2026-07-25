/// Outcome of a server-side QR token resolution attempt.
///
/// `notFound` covers a token that doesn't correspond to any known
/// [TableQrCode]; `invalid` covers a token that exists but is inactive or
/// rotated; `expired` covers a token past its own expiry.
enum TableQrValidityStatus { valid, invalid, expired, notFound }

/// The only shape the client is ever allowed to learn table/branch identity
/// from. A scanned QR token is opaque — the client sends it to the backend
/// and receives this result back; it never parses table or branch identity
/// out of the token itself.
///
/// All identity fields are nullable because a `notFound`/`invalid`/`expired`
/// result legitimately resolves to nothing.
class TableQrResolutionResult {
  final TableQrValidityStatus validityStatus;
  final String? restaurantId;
  final String? branchId;
  final String? tableId;
  final String? tableDisplayName;
  final String? branchDisplayName;
  final List<String> supportedLanguageCodes;

  const TableQrResolutionResult({
    required this.validityStatus,
    this.restaurantId,
    this.branchId,
    this.tableId,
    this.tableDisplayName,
    this.branchDisplayName,
    this.supportedLanguageCodes = const [],
  });

  /// Whether this result is safe to proceed with (open a session, show a
  /// menu). Anything other than `valid` must be treated as a dead end by
  /// the UI, never guessed around.
  bool get isUsable => validityStatus == TableQrValidityStatus.valid;

  factory TableQrResolutionResult.valid({
    required String restaurantId,
    required String branchId,
    required String tableId,
    required String tableDisplayName,
    required String branchDisplayName,
    required List<String> supportedLanguageCodes,
  }) {
    return TableQrResolutionResult(
      validityStatus: TableQrValidityStatus.valid,
      restaurantId: restaurantId,
      branchId: branchId,
      tableId: tableId,
      tableDisplayName: tableDisplayName,
      branchDisplayName: branchDisplayName,
      supportedLanguageCodes: supportedLanguageCodes,
    );
  }

  factory TableQrResolutionResult.notFound() => const TableQrResolutionResult(
        validityStatus: TableQrValidityStatus.notFound,
      );

  factory TableQrResolutionResult.invalid() => const TableQrResolutionResult(
        validityStatus: TableQrValidityStatus.invalid,
      );

  factory TableQrResolutionResult.expired() => const TableQrResolutionResult(
        validityStatus: TableQrValidityStatus.expired,
      );
}
