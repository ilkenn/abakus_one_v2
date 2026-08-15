import 'dart:async';

import '../../home/presentation/widgets/home_top_bar.dart'
    show kStaticBranchName;
import '../../restaurant/data/restaurant_table_repository.dart';
import '../domain/models/restaurant_table.dart';
import '../domain/models/table_qr_code.dart';
import 'table_qr_code_repository.dart';

/// **Development-only** seed data for table QR resolution.
///
/// No backend exists to issue/verify a real QR token yet
/// (`docs/table_qr_architecture.md` §5/§10 — server-side resolution is
/// explicitly deferred). Rather than block "Masada Sipariş" entirely on
/// that backend, this seeds a handful of known tables/tokens directly into
/// the same in-memory repositories a real backend-backed implementation
/// would eventually replace — `ResolveTableQrToken` never knows the
/// difference. **This file must never run against anything but the
/// in-memory dev repositories** — there is deliberately no code path that
/// could seed a Firestore-backed implementation with these fake tokens.
///
/// The printed/displayed dev QR codes for manual testing encode these
/// exact opaque token strings (see the constants below) — see this
/// feature's test files for how they're exercised.
abstract final class DevTableQrSeed {
  DevTableQrSeed._();

  static const String branchId = 'branch-1';
  static const String restaurantId = 'restaurant-1';
  static const String branchName = kStaticBranchName;

  static const String table12Id = 'dev-table-12';
  static const String table7Id = 'dev-table-7';
  static const String expiredTableId = 'dev-table-expired';

  /// A valid, active token — resolves to "Masa 12".
  static const String validTokenTable12 = 'DEV-ABAKUS-T12';

  /// A valid, active token — resolves to "Masa 7".
  static const String validTokenTable7 = 'DEV-ABAKUS-T07';

  /// A token whose [TableQrCode] exists but is past its own [TableQrCode
  /// .expiresAt] — exercises the `expired` resolution path.
  static const String expiredToken = 'DEV-ABAKUS-EXPIRED';

  /// A token whose [TableQrCode] exists but has been rotated out —
  /// exercises the `invalid` resolution path.
  static const String rotatedToken = 'DEV-ABAKUS-ROTATED-OLD';

  /// Deliberately synchronous (not `async`) even though the repository
  /// interface's `save` returns a `Future` — [InMemoryTableQrCodeRepository]/
  /// [InMemoryRestaurantTableRepository]'s `save` has no real `await`
  /// inside it, so its map mutation has already happened by the time this
  /// call returns, `Future` or not. This lets a `Provider<T>` builder
  /// (which must return synchronously) call [seed] and have the data
  /// genuinely present for the very next read — no risk of a caller
  /// racing an unresolved seed `Future`.
  /// [now] is the instant this seed's `createdAt`/`activatedAt`/`expiresAt`/
  /// `rotatedAt` values are computed relative to — defaults to real
  /// `DateTime.now()` (production's only current caller,
  /// `active_table_context_provider.dart`, relies on this default and is
  /// unaffected). A test that resolves against a fixed `Clock` should pass
  /// that same fixed instant here, so [expiredToken]'s `expiresAt` is
  /// deterministically relative to the clock the test itself uses instead
  /// of silently drifting against the real wall clock at test-run time.
  static void seed({
    required RestaurantTableRepository tableRepository,
    required TableQrCodeRepository qrCodeRepository,
    DateTime? now,
  }) {
    final resolvedNow = now ?? DateTime.now();

    unawaited(
      tableRepository.save(
        const RestaurantTable(
          id: table12Id,
          branchId: branchId,
          floorPlanId: 'dev-floor-plan-1',
          displayName: 'Masa 12',
          areaName: 'Salon',
          capacity: 4,
          status: TableStatus.available,
          sortOrder: 12,
          isActive: true,
        ),
      ),
    );
    unawaited(
      tableRepository.save(
        const RestaurantTable(
          id: table7Id,
          branchId: branchId,
          floorPlanId: 'dev-floor-plan-1',
          displayName: 'Masa 7',
          areaName: 'Teras',
          capacity: 2,
          status: TableStatus.available,
          sortOrder: 7,
          isActive: true,
        ),
      ),
    );
    unawaited(
      tableRepository.save(
        const RestaurantTable(
          id: expiredTableId,
          branchId: branchId,
          floorPlanId: 'dev-floor-plan-1',
          displayName: 'Masa 99',
          areaName: 'Salon',
          capacity: 4,
          status: TableStatus.available,
          sortOrder: 99,
          isActive: true,
        ),
      ),
    );

    unawaited(
      qrCodeRepository.save(
        TableQrCode(
          id: 'dev-qr-t12',
          tableId: table12Id,
          branchId: branchId,
          opaqueToken: validTokenTable12,
          status: TableQrStatus.active,
          createdAt: resolvedNow,
          activatedAt: resolvedNow,
        ),
      ),
    );
    unawaited(
      qrCodeRepository.save(
        TableQrCode(
          id: 'dev-qr-t07',
          tableId: table7Id,
          branchId: branchId,
          opaqueToken: validTokenTable7,
          status: TableQrStatus.active,
          createdAt: resolvedNow,
          activatedAt: resolvedNow,
        ),
      ),
    );
    unawaited(
      qrCodeRepository.save(
        TableQrCode(
          id: 'dev-qr-expired',
          tableId: expiredTableId,
          branchId: branchId,
          opaqueToken: expiredToken,
          status: TableQrStatus.active,
          createdAt: resolvedNow,
          activatedAt: resolvedNow,
          expiresAt: resolvedNow.subtract(const Duration(days: 1)),
        ),
      ),
    );
    unawaited(
      qrCodeRepository.save(
        TableQrCode(
          id: 'dev-qr-rotated',
          tableId: expiredTableId,
          branchId: branchId,
          opaqueToken: rotatedToken,
          status: TableQrStatus.rotated,
          createdAt: resolvedNow,
          activatedAt: resolvedNow,
          rotatedAt: resolvedNow,
        ),
      ),
    );
  }
}
