import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import 'rest_callable_client.dart';

class MaintenanceOperationsException implements Exception {
  const MaintenanceOperationsException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'MaintenanceOperationsException($code): $message';
}

class SyncCanonicalCatalogResult {
  const SyncCanonicalCatalogResult({
    required this.categoriesWritten,
    required this.productsWritten,
    required this.ingredientsWritten,
    required this.channelPricingPolicyWritten,
    this.exportedAt,
  });

  final int categoriesWritten;
  final int productsWritten;
  final int ingredientsWritten;
  final bool channelPricingPolicyWritten;
  final String? exportedAt;
}

/// 2026-10-30 — the key-free operational-maintenance surface, shared by
/// two wholly separate auth sessions/shells: `syncCanonicalCatalog`
/// (`requirePlatformMember` — called from the Platform Console) and
/// `renameBranch` (`requireStaffPermission("manageBranch")` — called from
/// the tenant Admin shell, since platform membership alone never
/// satisfies a staff-gated command, the same documented constraint
/// `PlatformShellScreen`'s own "Kiracı Admin Paneline Geç" icon exists
/// for). Lives in `core/services/` rather than inside either feature,
/// since both `features/platform` and `features/admin` call it. Both
/// callables run under the deployed Cloud Function's own service-account
/// identity — no key file is ever downloaded, held, or passed around for
/// either to work (see `functions/src/syncCanonicalCatalog.ts`'s own doc
/// comment). Windows REST-bridge, same pattern as every other gateway
/// this session.
abstract interface class MaintenanceOperationsGateway {
  Future<SyncCanonicalCatalogResult> syncCanonicalCatalog({
    required String organizationId,
    required String restaurantId,
  });

  Future<void> renameBranch({
    required String organizationId,
    required String branchId,
    required String name,
  });
}

class FirebaseMaintenanceOperationsGateway
    implements MaintenanceOperationsGateway {
  FirebaseMaintenanceOperationsGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  bool get _useRest =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    if (_useRest) {
      try {
        return await _restClient.call(name, data);
      } on RestCallableException catch (error) {
        throw MaintenanceOperationsException(error.code, error.message);
      }
    }
    try {
      final result = await functions.FirebaseFunctions.instance
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data);
      return result.data;
    } on functions.FirebaseFunctionsException catch (error) {
      throw MaintenanceOperationsException(
        error.code,
        error.message ?? 'İşlem gerçekleştirilemedi.',
      );
    }
  }

  @override
  Future<SyncCanonicalCatalogResult> syncCanonicalCatalog({
    required String organizationId,
    required String restaurantId,
  }) async {
    final result = await _call('syncCanonicalCatalog', {
      'organizationId': organizationId,
      'restaurantId': restaurantId,
    });
    return SyncCanonicalCatalogResult(
      categoriesWritten: result['categoriesWritten'] as int,
      productsWritten: result['productsWritten'] as int,
      ingredientsWritten: result['ingredientsWritten'] as int,
      channelPricingPolicyWritten:
          result['channelPricingPolicyWritten'] as bool,
      exportedAt: result['exportedAt'] as String?,
    );
  }

  @override
  Future<void> renameBranch({
    required String organizationId,
    required String branchId,
    required String name,
  }) async {
    await _call('renameBranch', {
      'organizationId': organizationId,
      'branchId': branchId,
      'name': name,
    });
  }
}

class UnavailableMaintenanceOperationsGateway
    implements MaintenanceOperationsGateway {
  const UnavailableMaintenanceOperationsGateway();

  Never _unavailable() => throw const MaintenanceOperationsException(
      'unavailable', 'Bakım araçları bu ortamda kullanılamıyor.');

  @override
  Future<SyncCanonicalCatalogResult> syncCanonicalCatalog({
    required String organizationId,
    required String restaurantId,
  }) async =>
      _unavailable();

  @override
  Future<void> renameBranch({
    required String organizationId,
    required String branchId,
    required String name,
  }) async =>
      _unavailable();
}
