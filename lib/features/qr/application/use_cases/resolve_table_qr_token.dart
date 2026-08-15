import '../../../../core/utils/clock.dart';
import '../../../home/presentation/widgets/home_top_bar.dart'
    show kStaticBranchName;
import '../../../restaurant/data/restaurant_table_repository.dart';
import '../../data/table_qr_code_repository.dart';
import '../../domain/models/table_qr_resolution.dart';

/// Resolves a scanned QR token into a [TableQrResolutionResult] — the use
/// case `docs/table_qr_architecture.md` §5 describes as "domain shape
/// only, no networking implemented." Implemented here against the local
/// [TableQrCodeRepository]/[RestaurantTableRepository] (today, seeded only
/// by `DevTableQrSeed` — see that file's doc comment) rather than a real
/// backend call, but the *shape* of this boundary is exactly what a future
/// backend-backed implementation would return: the caller never learns
/// table/branch identity except through this result, and never parses the
/// token itself.
class ResolveTableQrToken {
  const ResolveTableQrToken({
    required Clock clock,
    required TableQrCodeRepository qrCodeRepository,
    required RestaurantTableRepository tableRepository,
  })  : _clock = clock,
        _qrCodeRepository = qrCodeRepository,
        _tableRepository = tableRepository;

  final Clock _clock;
  final TableQrCodeRepository _qrCodeRepository;
  final RestaurantTableRepository _tableRepository;

  Future<TableQrResolutionResult> call(String token) async {
    final qrCode = await _qrCodeRepository.findByToken(token);
    if (qrCode == null) {
      return TableQrResolutionResult.notFound();
    }
    if (!qrCode.isValidAt(_clock.now())) {
      final isExpired =
          qrCode.expiresAt != null && !_clock.now().isBefore(qrCode.expiresAt!);
      return isExpired
          ? TableQrResolutionResult.expired()
          : TableQrResolutionResult.invalid();
    }

    final table = await _tableRepository.findById(qrCode.tableId);
    if (table == null || !table.isActive) {
      return TableQrResolutionResult.notFound();
    }
    if (!table.isOrderable) {
      // Active but not currently available (occupied/reserved/cleaning/
      // disabled) — the code itself is genuinely valid, but this specific
      // table can't accept a new session right now. There is no distinct
      // `TableQrValidityStatus` for "table temporarily unavailable" today
      // (the enum only models the *code's* own validity, not the table's
      // live operational status) — `invalid` is the closest honest fit
      // rather than claiming `valid` and letting session-open fail later.
      return TableQrResolutionResult.invalid();
    }

    return TableQrResolutionResult.valid(
      // Neither `TableQrCode` nor `RestaurantTable` carries a restaurant id
      // or a human branch name (there is no `Branch`/`Restaurant` lookup
      // wired into this domain module) — `'restaurant-1'`/
      // `kStaticBranchName` are this codebase's own existing, documented
      // placeholders for "the one real restaurant/branch this app models
      // today" (see `submitCustomerOrderProvider`'s identical
      // `restaurantId: 'restaurant-1'` and `home_top_bar.dart`'s doc
      // comment) — reused here rather than inventing a second, possibly
      // inconsistent source for the same not-yet-real concept.
      restaurantId: 'restaurant-1',
      branchId: qrCode.branchId,
      tableId: table.id,
      tableDisplayName: table.displayName,
      branchDisplayName: kStaticBranchName,
      supportedLanguageCodes: const ['tr'],
    );
  }
}
