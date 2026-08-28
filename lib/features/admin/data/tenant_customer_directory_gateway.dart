import 'package:cloud_functions/cloud_functions.dart' as functions;

/// One row in a tenant customer list/search result — AP-3 continuation.
/// Mirrors `listTenantCustomers`'s minimized wire shape exactly; the raw
/// phone number/`phoneSearchHash` are never returned by any callable this
/// gateway calls, so this type structurally cannot carry them.
class TenantCustomerSummary {
  final String id;
  final String displayName;
  final DateTime registrationDate;
  final DateTime lastActivityAt;
  final String accountState;
  final List<String> relatedBranchIds;
  final DateTime? lastOrderAt;
  final int totalOrderCount;

  const TenantCustomerSummary({
    required this.id,
    required this.displayName,
    required this.registrationDate,
    required this.lastActivityAt,
    required this.accountState,
    required this.relatedBranchIds,
    required this.lastOrderAt,
    required this.totalOrderCount,
  });

  factory TenantCustomerSummary.fromWire(Map<String, dynamic> data) {
    return TenantCustomerSummary(
      id: data['id'] as String,
      displayName: data['displayName'] as String,
      registrationDate: DateTime.parse(data['registrationDate'] as String),
      lastActivityAt: DateTime.parse(data['lastActivityAt'] as String),
      accountState: data['accountState'] as String,
      relatedBranchIds:
          List<String>.from(data['relatedBranchIds'] as List? ?? const []),
      lastOrderAt: data['lastOrderAt'] == null
          ? null
          : DateTime.parse(data['lastOrderAt'] as String),
      totalOrderCount: data['totalOrderCount'] as int,
    );
  }
}

class TenantCustomerListPage {
  final List<TenantCustomerSummary> customers;
  final String? nextCursor;

  const TenantCustomerListPage({
    required this.customers,
    required this.nextCursor,
  });
}

/// A `searchCustomersForPos` result row — deliberately narrower than
/// [TenantCustomerSummary]: only `phoneMasked`, never a full phone number,
/// mirroring `maskPhone()`'s server-side redaction (last 2 digits only).
class TenantCustomerSearchResult {
  final String id;
  final String displayName;
  final String phoneMasked;

  const TenantCustomerSearchResult({
    required this.id,
    required this.displayName,
    required this.phoneMasked,
  });

  factory TenantCustomerSearchResult.fromWire(Map<String, dynamic> data) {
    return TenantCustomerSearchResult(
      id: data['id'] as String,
      displayName: data['displayName'] as String,
      phoneMasked: data['phoneMasked'] as String,
    );
  }
}

/// A `getTenantCustomerDetail` result — everything [TenantCustomerSummary]
/// has, plus the tenant-scoped detail fields. `orderAddressSnapshots` are
/// this organization's own past `orders.deliveryAddressSnapshot` values
/// ONLY — never `customerAddresses` directly (the address-privacy
/// correction `functions/src/customerDirectory.ts` enforces server-side;
/// this type can structurally never carry anything beyond what that
/// callable actually returns). `marketingConsent` is always the literal
/// `"notCaptured"` string today — shown honestly, never invented.
class TenantCustomerDetail {
  final String id;
  final String displayName;
  final String phoneMasked;
  final DateTime registrationDate;
  final DateTime lastActivityAt;
  final String accountState;
  final List<String> relatedBranchIds;
  final DateTime? lastOrderAt;
  final int totalOrderCount;
  final List<Map<String, dynamic>> orderAddressSnapshots;
  final String restrictionStatus;
  final String? restrictionReasonMessage;
  final String marketingConsent;

  const TenantCustomerDetail({
    required this.id,
    required this.displayName,
    required this.phoneMasked,
    required this.registrationDate,
    required this.lastActivityAt,
    required this.accountState,
    required this.relatedBranchIds,
    required this.lastOrderAt,
    required this.totalOrderCount,
    required this.orderAddressSnapshots,
    required this.restrictionStatus,
    required this.restrictionReasonMessage,
    required this.marketingConsent,
  });

  bool get isRestricted => restrictionStatus == 'active';

  factory TenantCustomerDetail.fromWire(Map<String, dynamic> data) {
    final rawRestriction = data['tenantRestriction'];
    final restriction = rawRestriction is Map
        ? Map<String, dynamic>.from(rawRestriction)
        : <String, dynamic>{'status': 'none'};
    return TenantCustomerDetail(
      id: data['id'] as String,
      displayName: data['displayName'] as String,
      phoneMasked: data['phoneMasked'] as String,
      registrationDate: DateTime.parse(data['registrationDate'] as String),
      lastActivityAt: DateTime.parse(data['lastActivityAt'] as String),
      accountState: data['accountState'] as String,
      relatedBranchIds:
          List<String>.from(data['relatedBranchIds'] as List? ?? const []),
      lastOrderAt: data['lastOrderAt'] == null
          ? null
          : DateTime.parse(data['lastOrderAt'] as String),
      totalOrderCount: data['totalOrderCount'] as int,
      orderAddressSnapshots: (data['orderAddressSnapshots'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      restrictionStatus: restriction['status'] as String? ?? 'none',
      restrictionReasonMessage: restriction['reasonMessage'] as String?,
      marketingConsent: data['marketingConsent'] as String? ?? 'notCaptured',
    );
  }
}

/// Thrown for an expected, non-exceptional-in-nature rejection — mirrors
/// `TrustedDeviceException`'s exact shape.
class TenantCustomerDirectoryException implements Exception {
  final String code;
  final String message;

  const TenantCustomerDirectoryException(this.code, this.message);

  @override
  String toString() => 'TenantCustomerDirectoryException($code): $message';
}

/// The one client-facing boundary onto the real, server-authoritative
/// tenant Customer Directory backend (`functions/src/customerDirectory.ts`)
/// — AP-3 continuation. Every read is permission-gated server-side
/// (`viewTenantCustomerDirectory`); a caller lacking it receives a
/// `permission-denied` [TenantCustomerDirectoryException], never a silent
/// empty result.
abstract interface class TenantCustomerDirectoryGateway {
  Future<TenantCustomerListPage> list({
    required String organizationId,
    String? namePrefix,
    String? cursor,
  });

  Future<List<TenantCustomerSearchResult>> search({
    required String organizationId,
    String? phoneNumber,
    String? namePrefix,
  });

  Future<TenantCustomerDetail> getDetail({
    required String organizationId,
    required String customerId,
  });

  /// `restrict: true` sets `status: "active"` (the customer IS currently
  /// restricted); `restrict: false` sets `status: "none"` (clears it).
  /// Mirrors `setTenantCustomerRestriction`'s own wire vocabulary — never
  /// touches the canonical global `customers/{uid}` record.
  Future<void> setRestriction({
    required String organizationId,
    required String customerId,
    required bool restrict,
    required String reasonCode,
    required String reasonMessage,
  });
}

class FirebaseTenantCustomerDirectoryGateway
    implements TenantCustomerDirectoryGateway {
  const FirebaseTenantCustomerDirectoryGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw TenantCustomerDirectoryException(
      error.code,
      error.message ?? 'İşlem gerçekleştirilemedi.',
    );
  }

  @override
  Future<TenantCustomerListPage> list({
    required String organizationId,
    String? namePrefix,
    String? cursor,
  }) async {
    final callable = functions.FirebaseFunctions.instance.httpsCallable(
      'listTenantCustomers',
    );
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        if (namePrefix != null && namePrefix.isNotEmpty)
          'namePrefix': namePrefix,
        if (cursor != null) 'cursor': cursor,
      });
      final data = result.data;
      return TenantCustomerListPage(
        customers: [
          for (final raw in (data['customers'] as List))
            TenantCustomerSummary.fromWire(Map<String, dynamic>.from(raw as Map)),
        ],
        nextCursor: data['nextCursor'] as String?,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<List<TenantCustomerSearchResult>> search({
    required String organizationId,
    String? phoneNumber,
    String? namePrefix,
  }) async {
    final callable = functions.FirebaseFunctions.instance.httpsCallable(
      'searchCustomersForPos',
    );
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        if (phoneNumber != null && phoneNumber.isNotEmpty)
          'phoneNumber': phoneNumber,
        if (namePrefix != null && namePrefix.isNotEmpty)
          'namePrefix': namePrefix,
      });
      final data = result.data;
      return [
        for (final raw in (data['customers'] as List))
          TenantCustomerSearchResult.fromWire(
              Map<String, dynamic>.from(raw as Map)),
      ];
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<TenantCustomerDetail> getDetail({
    required String organizationId,
    required String customerId,
  }) async {
    final callable = functions.FirebaseFunctions.instance.httpsCallable(
      'getTenantCustomerDetail',
    );
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'customerId': customerId,
      });
      return TenantCustomerDetail.fromWire(result.data);
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> setRestriction({
    required String organizationId,
    required String customerId,
    required bool restrict,
    required String reasonCode,
    required String reasonMessage,
  }) async {
    final callable = functions.FirebaseFunctions.instance.httpsCallable(
      'setTenantCustomerRestriction',
    );
    try {
      await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'customerId': customerId,
        'status': restrict ? 'active' : 'none',
        'reasonCode': reasonCode,
        'reasonMessage': reasonMessage,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

/// Fail-closed fallback — mirrors `UnavailableTrustedDeviceGateway`'s
/// exact shape, used whenever Firebase isn't ready.
class UnavailableTenantCustomerDirectoryGateway
    implements TenantCustomerDirectoryGateway {
  const UnavailableTenantCustomerDirectoryGateway();

  Never _unavailable() => throw const TenantCustomerDirectoryException(
        'unavailable',
        'Müşteri dizini şu anda kullanılamıyor.',
      );

  @override
  Future<TenantCustomerListPage> list({
    required String organizationId,
    String? namePrefix,
    String? cursor,
  }) async =>
      _unavailable();

  @override
  Future<List<TenantCustomerSearchResult>> search({
    required String organizationId,
    String? phoneNumber,
    String? namePrefix,
  }) async =>
      _unavailable();

  @override
  Future<TenantCustomerDetail> getDetail({
    required String organizationId,
    required String customerId,
  }) async =>
      _unavailable();

  @override
  Future<void> setRestriction({
    required String organizationId,
    required String customerId,
    required bool restrict,
    required String reasonCode,
    required String reasonMessage,
  }) async =>
      _unavailable();
}
