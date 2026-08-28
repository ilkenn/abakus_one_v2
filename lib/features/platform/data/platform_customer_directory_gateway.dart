import 'package:cloud_functions/cloud_functions.dart' as functions;

/// One row in the platform-wide customer list/search result — AP-3
/// continuation. Every registered customer appears here exactly once,
/// including one with no tenant relationship at all — this is the ONLY
/// correct source for "every registered customer" (`customerDirectoryEntries`
/// duplicates per-tenant and excludes a no-tenant customer entirely; see
/// `functions/src/customerDirectoryConfig.ts`'s own doc comment).
class PlatformCustomerSummary {
  final String id;
  final String displayName;
  final DateTime registrationDate;
  final String accountState;

  const PlatformCustomerSummary({
    required this.id,
    required this.displayName,
    required this.registrationDate,
    required this.accountState,
  });

  factory PlatformCustomerSummary.fromWire(Map<String, dynamic> data) {
    return PlatformCustomerSummary(
      id: data['id'] as String,
      displayName: data['displayName'] as String,
      registrationDate: DateTime.parse(data['registrationDate'] as String),
      accountState: data['accountState'] as String,
    );
  }
}

class PlatformCustomerListPage {
  final List<PlatformCustomerSummary> customers;
  final String? nextCursor;

  const PlatformCustomerListPage({
    required this.customers,
    required this.nextCursor,
  });
}

/// A `getPlatformCustomerDetail` result. `relatedOrganizationIds` is the
/// tenant-relationship summary — real membership evidence
/// (`tenantCustomers` documents), never invented. `marketingConsent` is
/// always the literal `"notCaptured"` string today, shown honestly.
class PlatformCustomerDetail {
  final String uid;
  final String displayName;
  final String phoneMasked;
  final DateTime registrationDate;
  final String accountState;
  final List<String> relatedOrganizationIds;
  final String restrictionStatus;
  final String? restrictionReasonMessage;
  final String marketingConsent;

  const PlatformCustomerDetail({
    required this.uid,
    required this.displayName,
    required this.phoneMasked,
    required this.registrationDate,
    required this.accountState,
    required this.relatedOrganizationIds,
    required this.restrictionStatus,
    required this.restrictionReasonMessage,
    required this.marketingConsent,
  });

  bool get isRestricted => restrictionStatus == 'active';

  factory PlatformCustomerDetail.fromWire(Map<String, dynamic> data) {
    final rawRestriction = data['platformRestriction'];
    final restriction = rawRestriction is Map
        ? Map<String, dynamic>.from(rawRestriction)
        : <String, dynamic>{'status': 'none'};
    return PlatformCustomerDetail(
      uid: data['uid'] as String,
      displayName: data['displayName'] as String,
      phoneMasked: data['phoneMasked'] as String,
      registrationDate: DateTime.parse(data['registrationDate'] as String),
      accountState: data['accountState'] as String,
      relatedOrganizationIds: List<String>.from(
          data['relatedOrganizationIds'] as List? ?? const []),
      restrictionStatus: restriction['status'] as String? ?? 'none',
      restrictionReasonMessage: restriction['reasonMessage'] as String?,
      marketingConsent: data['marketingConsent'] as String? ?? 'notCaptured',
    );
  }
}

class PlatformCustomerDirectoryException implements Exception {
  const PlatformCustomerDirectoryException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'PlatformCustomerDirectoryException($code): $message';
}

/// The Platform Owner's real, capability-gated boundary onto the global
/// Customer Directory (`functions/src/customerDirectory.ts`) — AP-3
/// continuation. Every method requires a named `PlatformCapability`
/// server-side (`customerDirectory.listAllRegistered`/
/// `.revealFullAddressBook`/`.globalRestriction`) — this client never
/// re-derives that check, only surfaces the backend's own denial, mirroring
/// `EntitlementAdminGateway`'s own established convention exactly.
abstract interface class PlatformCustomerDirectoryGateway {
  Future<PlatformCustomerListPage> list({String? namePrefix, String? cursor});

  Future<List<PlatformCustomerSummary>> searchByPhone(String phoneNumber);

  Future<PlatformCustomerDetail> getDetail(String uid);

  /// The ONLY path to a customer's full saved address book — always
  /// mandatory-reason, always server-audited
  /// (`auditEvents`, type `customerDirectory.fullAddressBookRevealed`).
  /// Returns the raw address documents (id + fields) — no client-side
  /// reshaping beyond what display needs.
  Future<List<Map<String, dynamic>>> revealFullAddressBook({
    required String uid,
    required String reason,
  });

  Future<void> setRestriction({
    required String uid,
    required bool restrict,
    required String reasonCode,
    required String reasonMessage,
  });
}

class FirebasePlatformCustomerDirectoryGateway
    implements PlatformCustomerDirectoryGateway {
  const FirebasePlatformCustomerDirectoryGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw PlatformCustomerDirectoryException(
      error.code,
      error.message ?? 'İşlem gerçekleştirilemedi.',
    );
  }

  @override
  Future<PlatformCustomerListPage> list({
    String? namePrefix,
    String? cursor,
  }) async {
    final callable = functions.FirebaseFunctions.instance.httpsCallable(
      'listPlatformCustomers',
    );
    try {
      final result = await callable.call<Map<String, dynamic>>({
        if (namePrefix != null && namePrefix.isNotEmpty)
          'namePrefix': namePrefix,
        if (cursor != null) 'cursor': cursor,
      });
      final data = result.data;
      return PlatformCustomerListPage(
        customers: [
          for (final raw in (data['customers'] as List))
            PlatformCustomerSummary.fromWire(
                Map<String, dynamic>.from(raw as Map)),
        ],
        nextCursor: data['nextCursor'] as String?,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<List<PlatformCustomerSummary>> searchByPhone(
    String phoneNumber,
  ) async {
    final callable = functions.FirebaseFunctions.instance.httpsCallable(
      'searchPlatformCustomersByPhone',
    );
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'phoneNumber': phoneNumber,
      });
      final data = result.data;
      return [
        for (final raw in (data['customers'] as List))
          PlatformCustomerSummary.fromWire(
              Map<String, dynamic>.from(raw as Map)),
      ];
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<PlatformCustomerDetail> getDetail(String uid) async {
    final callable = functions.FirebaseFunctions.instance.httpsCallable(
      'getPlatformCustomerDetail',
    );
    try {
      final result = await callable.call<Map<String, dynamic>>({'uid': uid});
      return PlatformCustomerDetail.fromWire(result.data);
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> revealFullAddressBook({
    required String uid,
    required String reason,
  }) async {
    final callable = functions.FirebaseFunctions.instance.httpsCallable(
      'revealCustomerFullAddressBook',
    );
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'uid': uid,
        'reason': reason,
      });
      return (result.data['addresses'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> setRestriction({
    required String uid,
    required bool restrict,
    required String reasonCode,
    required String reasonMessage,
  }) async {
    final callable = functions.FirebaseFunctions.instance.httpsCallable(
      'setPlatformCustomerRestriction',
    );
    try {
      await callable.call<Map<String, dynamic>>({
        'uid': uid,
        'status': restrict ? 'active' : 'none',
        'reasonCode': reasonCode,
        'reasonMessage': reasonMessage,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

/// Fail-closed fallback — mirrors this codebase's established "no in-memory
/// fallback for a real backend-wired feature" convention.
class UnavailablePlatformCustomerDirectoryGateway
    implements PlatformCustomerDirectoryGateway {
  const UnavailablePlatformCustomerDirectoryGateway();

  Never _unavailable() => throw const PlatformCustomerDirectoryException(
        'unavailable',
        'Müşteri dizini şu anda kullanılamıyor.',
      );

  @override
  Future<PlatformCustomerListPage> list({
    String? namePrefix,
    String? cursor,
  }) async =>
      _unavailable();

  @override
  Future<List<PlatformCustomerSummary>> searchByPhone(
    String phoneNumber,
  ) async =>
      _unavailable();

  @override
  Future<PlatformCustomerDetail> getDetail(String uid) async => _unavailable();

  @override
  Future<List<Map<String, dynamic>>> revealFullAddressBook({
    required String uid,
    required String reason,
  }) async =>
      _unavailable();

  @override
  Future<void> setRestriction({
    required String uid,
    required bool restrict,
    required String reasonCode,
    required String reasonMessage,
  }) async =>
      _unavailable();
}
