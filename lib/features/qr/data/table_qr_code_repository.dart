import '../domain/models/table_qr_code.dart';

/// Storage for [TableQrCode] records — the repository
/// `docs/table_qr_architecture.md` described the model for but explicitly
/// deferred ("no backend exists to enforce this yet"). Mirrors
/// `TableSessionRepository`/`RestaurantTableRepository`'s exact shape
/// rather than inventing a different one for this sibling entity.
abstract interface class TableQrCodeRepository {
  Future<void> save(TableQrCode qrCode);

  Future<TableQrCode?> findById(String id);

  /// The record whose [TableQrCode.opaqueToken] matches [token], if any —
  /// the one lookup a scanned QR code actually needs.
  Future<TableQrCode?> findByToken(String token);
}

/// In-memory [TableQrCodeRepository] — the only implementation until a
/// backend exists, matching every other repository in this domain
/// (`InMemoryTableSessionRepository`/`InMemoryRestaurantTableRepository`).
class InMemoryTableQrCodeRepository implements TableQrCodeRepository {
  final Map<String, TableQrCode> _qrCodesById = {};

  @override
  Future<void> save(TableQrCode qrCode) async {
    _qrCodesById[qrCode.id] = qrCode;
  }

  @override
  Future<TableQrCode?> findById(String id) async {
    return _qrCodesById[id];
  }

  @override
  Future<TableQrCode?> findByToken(String token) async {
    for (final qrCode in _qrCodesById.values) {
      if (qrCode.opaqueToken == token) return qrCode;
    }
    return null;
  }
}
