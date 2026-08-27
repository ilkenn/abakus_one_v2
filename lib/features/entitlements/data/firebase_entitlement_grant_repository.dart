import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../domain/entitlement_grant.dart';
import '../domain/entitlement_module.dart';
import '../domain/entitlement_scope_type.dart';
import '../domain/entitlement_status.dart';
import 'entitlement_grant_repository.dart';

const _moduleWireNames = {
  EntitlementModule.smartRestaurantSetup: 'smartRestaurantSetup',
  EntitlementModule.menuImport: 'menuImport',
  EntitlementModule.inventory: 'inventory',
  EntitlementModule.recipes: 'recipes',
  EntitlementModule.nutrition: 'nutrition',
  EntitlementModule.allergens: 'allergens',
  EntitlementModule.purchasing: 'purchasing',
  EntitlementModule.suppliers: 'suppliers',
  EntitlementModule.costing: 'costing',
  EntitlementModule.profitability: 'profitability',
  EntitlementModule.advancedReporting: 'advancedReporting',
  EntitlementModule.qrMenu: 'qrMenu',
  EntitlementModule.reservations: 'reservations',
  EntitlementModule.crm: 'crm',
  EntitlementModule.loyalty: 'loyalty',
  EntitlementModule.pos: 'pos',
  EntitlementModule.kds: 'kds',
  EntitlementModule.courier: 'courier',
  EntitlementModule.marketplace: 'marketplace',
  EntitlementModule.payments: 'payments',
  EntitlementModule.ai: 'ai',
};

EntitlementModule entitlementModuleFromWire(String value) {
  for (final entry in _moduleWireNames.entries) {
    if (entry.value == value) return entry.key;
  }
  throw ArgumentError('Unknown entitlement module: $value');
}

String entitlementModuleToWire(EntitlementModule module) =>
    _moduleWireNames[module]!;

EntitlementScopeType entitlementScopeTypeFromWire(String value) {
  switch (value) {
    case 'organization':
      return EntitlementScopeType.organization;
    case 'restaurant':
      return EntitlementScopeType.restaurant;
    case 'branch':
      return EntitlementScopeType.branch;
    default:
      throw ArgumentError('Unknown entitlement scope type: $value');
  }
}

String entitlementScopeTypeToWire(EntitlementScopeType scopeType) {
  switch (scopeType) {
    case EntitlementScopeType.organization:
      return 'organization';
    case EntitlementScopeType.restaurant:
      return 'restaurant';
    case EntitlementScopeType.branch:
      return 'branch';
  }
}

EntitlementStatus entitlementStatusFromWire(String value) {
  switch (value) {
    case 'trial':
      return EntitlementStatus.trial;
    case 'active':
      return EntitlementStatus.active;
    case 'grace':
      return EntitlementStatus.grace;
    case 'suspended':
      return EntitlementStatus.suspended;
    case 'expired':
      return EntitlementStatus.expired;
    case 'revoked':
      return EntitlementStatus.revoked;
    default:
      throw ArgumentError('Unknown entitlement status: $value');
  }
}

/// AP-2 final wiring — direct Firestore reads (`entitlements`' own rule:
/// `isOrgMember(...) || isPlatformMember()`), matching `entitlementAdmin.ts`'s
/// doc shape/id (`${organizationId}_${scopeType}_${scopeId}_${module}`)
/// exactly. **Read-only by design**: [save] always throws —
/// `grantEntitlement`/`renewEntitlement`/`suspendEntitlement`/
/// `revokeEntitlement` are the ONLY real mutation path (all
/// `requirePlatformMember`-gated server-side), consumed instead through
/// `EntitlementAdminGateway` (Platform Owner console only). A Tenant Admin
/// has no legitimate call to `save` at all — this repository structurally
/// cannot be used to bypass that, not merely by convention.
class FirestoreEntitlementGrantRepository
    implements EntitlementGrantRepository {
  FirestoreEntitlementGrantRepository({fs.FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  // Lazily resolved — see `FirebasePlatformMemberRepository`'s identical
  // doc comment for why construction alone must never require a real
  // `Firebase.initializeApp()`.
  final fs.FirebaseFirestore? _providedFirestore;
  fs.FirebaseFirestore get _firestore =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  @override
  Future<void> save(EntitlementGrant grant) {
    throw UnsupportedError(
      'Entitlement mutations only happen through the real backend '
      'callables (grantEntitlement/renewEntitlement/suspendEntitlement/'
      'revokeEntitlement) — never a direct Firestore write.',
    );
  }

  @override
  Future<EntitlementGrant?> findById(String id) async {
    final doc = await _firestore.collection('entitlements').doc(id).get();
    if (!doc.exists) return null;
    return _mapGrant(doc.id, doc.data()!);
  }

  @override
  Future<EntitlementGrant?> findByModuleAndScope(
    EntitlementModule module,
    EntitlementScopeType scopeType,
    String scopeId,
  ) async {
    final query = await _firestore
        .collection('entitlements')
        .where('scopeType', isEqualTo: entitlementScopeTypeToWire(scopeType))
        .where('scopeId', isEqualTo: scopeId)
        .where('module', isEqualTo: entitlementModuleToWire(module))
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    return _mapGrant(query.docs.first.id, query.docs.first.data());
  }

  @override
  Future<List<EntitlementGrant>> findByScope(
    EntitlementScopeType scopeType,
    String scopeId,
  ) async {
    final query = await _firestore
        .collection('entitlements')
        .where('scopeType', isEqualTo: entitlementScopeTypeToWire(scopeType))
        .where('scopeId', isEqualTo: scopeId)
        .get();
    return [
      for (final doc in query.docs) _mapGrant(doc.id, doc.data()),
    ];
  }

  EntitlementGrant _mapGrant(String id, Map<String, dynamic> data) {
    return EntitlementGrant(
      id: id,
      module: entitlementModuleFromWire(data['module'] as String),
      scopeType: entitlementScopeTypeFromWire(data['scopeType'] as String),
      scopeId: data['scopeId'] as String,
      status: entitlementStatusFromWire(data['status'] as String),
      startsAt: (data['contractStartsAt'] as fs.Timestamp?)?.toDate(),
      expiresAt: (data['contractEndsAt'] as fs.Timestamp?)?.toDate(),
      graceEndsAt: (data['graceEndsAt'] as fs.Timestamp?)?.toDate(),
      postGraceDisabledModules: [
        for (final m in (data['postGraceDisabledModules'] as List? ?? []))
          entitlementModuleFromWire(m as String),
      ],
      grantedByStaffId: data['grantedByPlatformUid'] as String? ?? '',
      grantedAt:
          (data['grantedAt'] as fs.Timestamp?)?.toDate() ?? DateTime.now(),
      revision: data['version'] as int? ?? 1,
    );
  }
}

/// `firebaseReadyProvider` is false — every read fails closed with a real
/// error, never a silently-empty entitlement list.
class UnavailableEntitlementGrantRepository
    implements EntitlementGrantRepository {
  const UnavailableEntitlementGrantRepository();

  Never _unavailable() =>
      throw StateError('Entitlement backend is not available in this build.');

  @override
  Future<void> save(EntitlementGrant grant) async => _unavailable();

  @override
  Future<EntitlementGrant?> findById(String id) async => _unavailable();

  @override
  Future<EntitlementGrant?> findByModuleAndScope(
    EntitlementModule module,
    EntitlementScopeType scopeType,
    String scopeId,
  ) async =>
      _unavailable();

  @override
  Future<List<EntitlementGrant>> findByScope(
    EntitlementScopeType scopeType,
    String scopeId,
  ) async =>
      _unavailable();
}
