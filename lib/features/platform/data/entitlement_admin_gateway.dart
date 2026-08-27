import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../../entitlements/domain/entitlement_module.dart';
import '../../entitlements/domain/entitlement_scope_type.dart';
import '../../entitlements/data/firebase_entitlement_grant_repository.dart';

class EntitlementAdminException implements Exception {
  const EntitlementAdminException(this.code, this.message, [this.details]);

  final String code;
  final String message;
  final Map<String, dynamic>? details;

  @override
  String toString() => 'EntitlementAdminException($code): $message';
}

/// AP-2 final wiring — the Platform Owner's real mutation surface for
/// entitlements, mirroring `entitlementAdmin.ts`'s 4 callables exactly
/// (all `requirePlatformMember`-gated server-side; this client never
/// re-derives that check, only surfaces the backend's own denial). Reads
/// go through `entitlementGrantReadRepositoryProvider` instead (the same
/// `entitlements` collection, direct Firestore read) — this gateway is
/// mutation-only, matching the real backend's own callable/read split
/// (no list/read callable exists there either).
abstract interface class EntitlementAdminGateway {
  Future<void> grant({
    required String organizationId,
    required EntitlementScopeType scopeType,
    required String scopeId,
    required EntitlementModule module,
    bool asActiveImmediately = false,
    DateTime? contractStartsAt,
    DateTime? contractEndsAt,
  });

  Future<void> renew({
    required String entitlementId,
    required DateTime contractEndsAt,
  });

  Future<void> suspend({
    required String entitlementId,
    required String reasonMessage,
    List<EntitlementModule>? postGraceDisabledModules,
  });

  Future<void> revoke({
    required String entitlementId,
    required String reasonMessage,
  });
}

class FirebaseEntitlementAdminGateway implements EntitlementAdminGateway {
  const FirebaseEntitlementAdminGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw EntitlementAdminException(
      error.code,
      error.message ?? 'İşlem tamamlanamadı.',
      error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : null,
    );
  }

  @override
  Future<void> grant({
    required String organizationId,
    required EntitlementScopeType scopeType,
    required String scopeId,
    required EntitlementModule module,
    bool asActiveImmediately = false,
    DateTime? contractStartsAt,
    DateTime? contractEndsAt,
  }) async {
    final callable =
        functions.FirebaseFunctions.instance.httpsCallable('grantEntitlement');
    try {
      await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'scopeType': entitlementScopeTypeToWire(scopeType),
        'scopeId': scopeId,
        'module': entitlementModuleToWire(module),
        'initialStatus': asActiveImmediately ? 'active' : 'trial',
        if (contractStartsAt != null)
          'contractStartsAtIso': contractStartsAt.toIso8601String(),
        if (contractEndsAt != null)
          'contractEndsAtIso': contractEndsAt.toIso8601String(),
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> renew({
    required String entitlementId,
    required DateTime contractEndsAt,
  }) async {
    final callable =
        functions.FirebaseFunctions.instance.httpsCallable('renewEntitlement');
    try {
      await callable.call<Map<String, dynamic>>({
        'entitlementId': entitlementId,
        'contractEndsAtIso': contractEndsAt.toIso8601String(),
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> suspend({
    required String entitlementId,
    required String reasonMessage,
    List<EntitlementModule>? postGraceDisabledModules,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('suspendEntitlement');
    try {
      await callable.call<Map<String, dynamic>>({
        'entitlementId': entitlementId,
        'reasonMessage': reasonMessage,
        if (postGraceDisabledModules != null)
          'postGraceDisabledModules': [
            for (final m in postGraceDisabledModules)
              entitlementModuleToWire(m),
          ],
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> revoke({
    required String entitlementId,
    required String reasonMessage,
  }) async {
    final callable =
        functions.FirebaseFunctions.instance.httpsCallable('revokeEntitlement');
    try {
      await callable.call<Map<String, dynamic>>({
        'entitlementId': entitlementId,
        'reasonMessage': reasonMessage,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

class UnavailableEntitlementAdminGateway implements EntitlementAdminGateway {
  const UnavailableEntitlementAdminGateway();

  Never _unavailable() => throw const EntitlementAdminException(
      'unavailable', 'Abonelik yönetimi backend\'i bu ortamda kullanılamıyor.');

  @override
  Future<void> grant({
    required String organizationId,
    required EntitlementScopeType scopeType,
    required String scopeId,
    required EntitlementModule module,
    bool asActiveImmediately = false,
    DateTime? contractStartsAt,
    DateTime? contractEndsAt,
  }) async =>
      _unavailable();

  @override
  Future<void> renew({
    required String entitlementId,
    required DateTime contractEndsAt,
  }) async =>
      _unavailable();

  @override
  Future<void> suspend({
    required String entitlementId,
    required String reasonMessage,
    List<EntitlementModule>? postGraceDisabledModules,
  }) async =>
      _unavailable();

  @override
  Future<void> revoke({
    required String entitlementId,
    required String reasonMessage,
  }) async =>
      _unavailable();
}
