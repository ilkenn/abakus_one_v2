import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../../../core/services/logging/logging_provider.dart';
import '../../../core/services/logging/logging_service.dart';
import '../domain/models/customer_gender.dart';
import '../domain/models/occupation_status.dart';
import 'customer_registration_diagnostics.dart';

class CustomerRegistrationGatewayException implements Exception {
  const CustomerRegistrationGatewayException(this.code, this.message);

  /// A `FirebaseFunctionsException.code` value —
  /// `'invalid-argument'`/`'permission-denied'`/`'unauthenticated'`/
  /// `'failed-precondition'`, or `'parse-error'`/`'unknown'` for a
  /// non-`FirebaseFunctionsException` failure. Callers branch on this,
  /// never on [message]'s text.
  final String code;
  final String message;

  @override
  String toString() => 'CustomerRegistrationGatewayException($code): $message';
}

class CompleteCustomerProfileResult {
  const CompleteCustomerProfileResult({
    required this.alreadyCompleted,
    required this.organizationId,
  });

  final bool alreadyCompleted;
  final String organizationId;
}

/// The narrow, safe classification `getCustomerProfileCompletionState`
/// returns — never the underlying `customers`/`tenantCustomers` document
/// contents. [reason] is a coarse, non-sensitive category
/// (`'customerMissing'`/`'profileFieldsIncomplete'`/`'membershipMissing'`),
/// `null` when [isComplete] is `true`.
class CustomerProfileCompletionResult {
  const CustomerProfileCompletionResult({
    required this.isComplete,
    this.reason,
  });

  final bool isComplete;
  final String? reason;
}

/// Profile Completion CR.1 — the customer-side bridge to
/// `functions/src/completeCustomerProfile.ts` and
/// `functions/src/getCustomerProfileCompletionState.ts`. **Never sends
/// `organizationId` or a `phoneNumber`** — both are resolved
/// server-side, exactly matching what each callable itself accepts (see
/// their own doc comments).
abstract interface class CustomerRegistrationGateway {
  Future<CompleteCustomerProfileResult> completeCustomerProfile({
    required String firstName,
    required String lastName,
    required String email,
    required OccupationStatus occupationStatus,
    String? workplaceName,
    String? educationalInstitutionName,
    required CustomerGender gender,

    /// Canonical `"YYYY-MM-DD"` — already normalized by the caller (see
    /// `formatCanonicalBirthDate`), never a raw [DateTime], mirroring how
    /// [email] arrives here already normalized via `normalizeEmail`.
    required String birthDate,
  });

  /// Server-authoritative — see `getCustomerProfileCompletionState.ts`'s
  /// own doc comment for exactly why this exists instead of the client
  /// reading `customers`/`tenantCustomers` directly (the latter is
  /// structurally impossible for `tenantCustomers`: its Firestore rule
  /// only ever grants staff read access, never a customer their own
  /// record).
  Future<CustomerProfileCompletionResult> getCompletionState();
}

/// Parses the callable's decoded response — a pure, top-level function
/// (not inlined) so the exact Function-to-Flutter return contract is
/// directly unit-testable, mirroring `parseCustomerPhotoUploadGrant`'s
/// established shape and its own hard-won lesson: never assume a wire
/// value's Dart runtime type without checking it explicitly (a callable
/// boolean/number can decode differently across platforms).
CompleteCustomerProfileResult parseCompleteCustomerProfileResult(
  Map<String, dynamic> data,
) {
  final alreadyCompleted = data['alreadyCompleted'];
  if (alreadyCompleted is! bool) {
    throw FormatException(
      'completeCustomerProfile response: alreadyCompleted must be a bool, '
      'got ${alreadyCompleted.runtimeType}',
    );
  }
  final organizationId = data['organizationId'];
  if (organizationId is! String) {
    throw FormatException(
      'completeCustomerProfile response: organizationId must be a string, '
      'got ${organizationId.runtimeType}',
    );
  }
  return CompleteCustomerProfileResult(
    alreadyCompleted: alreadyCompleted,
    organizationId: organizationId,
  );
}

/// Parses `getCustomerProfileCompletionState`'s decoded response — mirrors
/// [parseCompleteCustomerProfileResult]'s exact discipline. `state` must be
/// exactly `'complete'` or `'incomplete'`; anything else is a genuine
/// contract violation, never silently coerced.
CustomerProfileCompletionResult parseCustomerProfileCompletionResult(
  Map<String, dynamic> data,
) {
  final state = data['state'];
  if (state != 'complete' && state != 'incomplete') {
    throw FormatException(
      'getCustomerProfileCompletionState response: state must be '
      '"complete" or "incomplete", got $state',
    );
  }
  final reason = data['reason'];
  if (reason != null && reason is! String) {
    throw FormatException(
      'getCustomerProfileCompletionState response: reason must be a '
      'string when present, got ${reason.runtimeType}',
    );
  }
  return CustomerProfileCompletionResult(
    isComplete: state == 'complete',
    reason: reason as String?,
  );
}

class FirebaseCustomerRegistrationGateway
    implements CustomerRegistrationGateway {
  FirebaseCustomerRegistrationGateway({
    functions.FirebaseFunctions? functionsInstance,
    LoggingService? loggingService,
  })  : _functions = functionsInstance ?? functions.FirebaseFunctions.instance,
        _loggingService = loggingService ?? defaultLoggingService();

  final functions.FirebaseFunctions _functions;
  final LoggingService _loggingService;

  @override
  Future<CompleteCustomerProfileResult> completeCustomerProfile({
    required String firstName,
    required String lastName,
    required String email,
    required OccupationStatus occupationStatus,
    String? workplaceName,
    String? educationalInstitutionName,
    required CustomerGender gender,
    required String birthDate,
  }) async {
    final callable = _functions.httpsCallable('completeCustomerProfile');

    logRegistrationMilestone(
      _loggingService,
      'completeCustomerProfile callable invoke',
      {'occupationStatus': occupationStatus.name},
    );

    Map<String, dynamic> data;
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'occupationStatus': occupationStatus.name,
        if (workplaceName != null) 'workplaceName': workplaceName,
        if (educationalInstitutionName != null)
          'educationalInstitutionName': educationalInstitutionName,
        'gender': gender.name,
        'birthDate': birthDate,
      });
      data = result.data;
    } on functions.FirebaseFunctionsException catch (error) {
      logRegistrationMilestone(
        _loggingService,
        'completeCustomerProfile callable threw',
        {'code': error.code},
      );
      throw CustomerRegistrationGatewayException(
        error.code,
        error.message ?? 'Profil tamamlanamadı.',
      );
    }

    logRegistrationMilestone(
      _loggingService,
      'completeCustomerProfile raw response received',
    );

    try {
      final parsed = parseCompleteCustomerProfileResult(data);
      logRegistrationMilestone(
        _loggingService,
        'completeCustomerProfile response parsed',
        {'alreadyCompleted': parsed.alreadyCompleted},
      );
      return parsed;
    } catch (error) {
      logRegistrationMilestone(
        _loggingService,
        'completeCustomerProfile response parse failed',
        {'exceptionType': error.runtimeType.toString()},
      );
      throw const CustomerRegistrationGatewayException(
        'parse-error',
        'Profil tamamlanamadı.',
      );
    }
  }

  @override
  Future<CustomerProfileCompletionResult> getCompletionState() async {
    final callable =
        _functions.httpsCallable('getCustomerProfileCompletionState');

    logRegistrationMilestone(
      _loggingService,
      'getCustomerProfileCompletionState callable invoke',
    );

    Map<String, dynamic> data;
    try {
      final result = await callable.call<Map<String, dynamic>>();
      data = result.data;
    } on functions.FirebaseFunctionsException catch (error) {
      logRegistrationMilestone(
        _loggingService,
        'getCustomerProfileCompletionState callable threw',
        {'code': error.code},
      );
      throw CustomerRegistrationGatewayException(
        error.code,
        error.message ?? 'Hesap bilgilerine ulaşılamadı.',
      );
    }

    logRegistrationMilestone(
      _loggingService,
      'getCustomerProfileCompletionState raw response received',
    );

    try {
      final parsed = parseCustomerProfileCompletionResult(data);
      logRegistrationMilestone(
        _loggingService,
        'getCustomerProfileCompletionState response parsed',
        {'isComplete': parsed.isComplete, 'reason': parsed.reason},
      );
      return parsed;
    } catch (error) {
      logRegistrationMilestone(
        _loggingService,
        'getCustomerProfileCompletionState response parse failed',
        {'exceptionType': error.runtimeType.toString()},
      );
      throw const CustomerRegistrationGatewayException(
        'parse-error',
        'Hesap bilgilerine ulaşılamadı.',
      );
    }
  }
}
