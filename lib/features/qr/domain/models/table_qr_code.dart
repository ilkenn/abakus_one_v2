/// Lifecycle status of a [TableQrCode].
enum TableQrStatus { active, inactive, rotated, expired }

/// The physical/printed QR code that resolves to exactly one
/// [RestaurantTable].
///
/// Kept separate from [RestaurantTable] on purpose: a table is a permanent
/// operational concept, while its QR code is a rotatable credential. Baking
/// the token into the table would make rotation (a security operation) a
/// mutation of operational data instead of an isolated, auditable event.
///
/// The public URL this token is embedded in is expected to be shaped as
/// `menu.abakus.app/t/{opaqueToken}` — the token itself carries no
/// structure a client can parse; table/branch identity is only ever known
/// after server-side resolution (see [TableQrResolutionResult]).
///
/// Tokens are never generated on the client. This model represents a
/// backend-issued value; nothing in this class creates or derives a token.
class TableQrCode {
  final String id;
  final String tableId;
  final String branchId;
  final String opaqueToken;
  final TableQrStatus status;
  final DateTime createdAt;
  final DateTime? activatedAt;
  final DateTime? deactivatedAt;
  final DateTime? expiresAt;
  final DateTime? rotatedAt;

  /// The id of the [TableQrCode] this one replaced, if any. Forms an
  /// auditable rotation chain without deleting prior records.
  final String? previousQrCodeId;

  const TableQrCode({
    required this.id,
    required this.tableId,
    required this.branchId,
    required this.opaqueToken,
    required this.status,
    required this.createdAt,
    this.activatedAt,
    this.deactivatedAt,
    this.expiresAt,
    this.rotatedAt,
    this.previousQrCodeId,
  });

  /// Whether this code can open a new [TableSession] at the given instant.
  /// A rotated, inactive, or explicitly expired code is never valid, and an
  /// active code past its own [expiresAt] is treated as invalid even if its
  /// [status] hasn't been batch-updated yet.
  bool isValidAt(DateTime now) {
    if (status != TableQrStatus.active) return false;
    if (expiresAt != null && !now.isBefore(expiresAt!)) return false;
    return true;
  }

  TableQrCode copyWith({
    String? id,
    String? tableId,
    String? branchId,
    String? opaqueToken,
    TableQrStatus? status,
    DateTime? createdAt,
    DateTime? activatedAt,
    DateTime? deactivatedAt,
    DateTime? expiresAt,
    DateTime? rotatedAt,
    String? previousQrCodeId,
  }) {
    return TableQrCode(
      id: id ?? this.id,
      tableId: tableId ?? this.tableId,
      branchId: branchId ?? this.branchId,
      opaqueToken: opaqueToken ?? this.opaqueToken,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      activatedAt: activatedAt ?? this.activatedAt,
      deactivatedAt: deactivatedAt ?? this.deactivatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      rotatedAt: rotatedAt ?? this.rotatedAt,
      previousQrCodeId: previousQrCodeId ?? this.previousQrCodeId,
    );
  }
}
