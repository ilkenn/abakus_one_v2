import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../../../bootstrap/app_environment.dart';
import '../../../core/services/logging/log_level.dart';
import '../../../core/services/logging/logging_provider.dart';
import '../../../core/services/logging/logging_service.dart';
import '../../../shared/models/customer_photo.dart';
import '../../../shared/models/customer_photo_status.dart';
import 'customer_photo_upload_diagnostics.dart';

/// The server-issued upload authorization — the ONE thing that ever tells
/// the client where it may write bytes. Mirrors
/// `functions/src/customerPhotoUploadGrants.ts`'s own
/// `RequestUploadGrantResult` shape.
class CustomerPhotoUploadGrant {
  const CustomerPhotoUploadGrant({
    required this.grantId,
    required this.objectPath,
    required this.contentType,
    required this.expiresAt,
  });

  final String grantId;
  final String objectPath;
  final String contentType;
  final DateTime expiresAt;
}

/// Parses `requestCustomerPhotoUploadGrant`'s decoded callable response
/// (`result.data`) into a [CustomerPhotoUploadGrant] — kept as a pure,
/// top-level function (not inlined in [FirebaseCustomerPhotoGateway]) so
/// the exact Function-to-Flutter return contract is directly unit-testable
/// without a real callable/platform channel.
///
/// **`expiresAtMillis` is read as [num], not cast directly as `int`.**
/// `functions/src/customerPhotoUploadGrants.ts` returns it as a plain JS
/// `number` (via `Timestamp.toMillis()`), which is callable-safe, but the
/// native Android callable SDK's generic JSON decoding does not guarantee
/// a whole-number JSON value survives as a Dart `int` — it can arrive as
/// a `double` (a well-known category of Gson-style "every JSON number
/// decodes to `Double` when the target type is generic `Object`"
/// behavior). A direct `data['expiresAtMillis'] as int` throws a `TypeError`
/// in exactly that case — uncaught by `requestUploadGrant`'s own
/// `on FirebaseFunctionsException` clause, since a cast failure is not one
/// — which silently stops the upload flow with no error shown, no log
/// line, and no further milestone ("upload grant received" never fires
/// even though the callable itself completed successfully server-side).
/// `(x as num).toInt()` already exists as the established, precedent
/// pattern for exactly this class of value elsewhere in this codebase —
/// see `check_delivery_eligibility_gateway.dart`'s `minimumOrderMinorUnits`
/// parsing — this mirrors it rather than inventing a new approach.
CustomerPhotoUploadGrant parseCustomerPhotoUploadGrant(
  Map<String, dynamic> data,
) {
  final expiresAtMillis = data['expiresAtMillis'];
  if (expiresAtMillis is! num) {
    throw FormatException(
      'requestCustomerPhotoUploadGrant response: expiresAtMillis must be a '
      'number, got ${expiresAtMillis.runtimeType}',
    );
  }
  return CustomerPhotoUploadGrant(
    grantId: data['grantId'] as String,
    objectPath: data['objectPath'] as String,
    contentType: data['contentType'] as String,
    expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMillis.toInt()),
  );
}

/// Builds the DEVELOPMENT-ONLY structural breadcrumb logged immediately
/// after the raw callable response resolves — **safe structural
/// information only**: the runtime type of the decoded payload, its map
/// keys (field names, not values), and the runtime type of each field this
/// parser actually reads. Never the field values themselves — a grantId or
/// objectPath value is already treated as safe-to-log elsewhere in this
/// feature, but this function deliberately logs even less than that,
/// since its only purpose is diagnosing a *shape* mismatch, not a value
/// one.
Map<String, Object?> buildGrantCallableResponseLogContext(Object? data) {
  final map = data is Map ? data : const {};
  Object? typeOfField(String key) {
    if (!map.containsKey(key)) return 'missing';
    return map[key]?.runtimeType.toString() ?? 'null';
  }

  return {
    'dataRuntimeType': data.runtimeType.toString(),
    'mapKeys': map.keys.map((k) => k.toString()).toList(),
    'grantIdType': typeOfField('grantId'),
    'objectPathType': typeOfField('objectPath'),
    'contentTypeType': typeOfField('contentType'),
    'expiresAtMillisType': typeOfField('expiresAtMillis'),
  };
}

class CustomerPhotoGatewayException implements Exception {
  const CustomerPhotoGatewayException(this.code, this.message);

  /// A `FirebaseFunctionsException.code` value — `'resource-exhausted'`
  /// (max-10 reached), `'permission-denied'`, `'failed-precondition'`,
  /// `'unauthenticated'`, etc. Callers branch on this, never on
  /// [message]'s text.
  final String code;
  final String message;

  @override
  String toString() => 'CustomerPhotoGatewayException($code): $message';
}

/// Profile P.4.3A — the customer-side bridge to the real photo backend
/// (P.4.2B1/B2/B2.1, `bea00b0`). **Never creates, updates, or deletes a
/// `customerPhotos` Firestore document itself** — [watchGallery] only
/// reads; every write happens server-side (the upload-grant callable, the
/// Storage finalize trigger, the selection callable). No
/// `customerPublicProfiles`/`customers.profilePicturePath` write exists
/// anywhere in this file either.
abstract interface class CustomerPhotoGateway {
  /// A live view of every `customerPhotos` record the backend permits
  /// this signed-in customer to see for [organizationId] — every status,
  /// including `rejected`/`removed` (the owner-read rule in
  /// `firestore.rules` already permits all of them; filtering what counts
  /// toward the active-10 total is the caller's job, via
  /// `CustomerPhoto.countsTowardEligibleLimit`).
  Stream<List<CustomerPhoto>> watchGallery({
    required String organizationId,
    required String customerId,
  });

  /// Calls `requestCustomerPhotoUploadGrant`. Throws
  /// [CustomerPhotoGatewayException] with `code == 'resource-exhausted'`
  /// when the max-10 (including outstanding grants) is already reached —
  /// server-authoritative, independent of whatever the client's own
  /// gallery snapshot currently shows.
  ///
  /// [purpose] — CR.1.2 — an optional, narrow upload-intent declaration
  /// (today only `'profileOnboarding'`, for the photo offered during
  /// first-time registration). `null` for every other caller (e.g. the
  /// ordinary "Profil Fotoğraflarım" flow). The server validates this
  /// against its own closed enum and stores it on the grant; the client
  /// never asserts approval/selection through it.
  Future<CustomerPhotoUploadGrant> requestUploadGrant({
    required String organizationId,
    required String contentType,
    String? purpose,
  });

  /// Calls `selectCustomerProfilePhoto`. Selection UI itself may not be
  /// wired to this yet (P.4.3B) — the gateway method exists now so the
  /// callable integration is proven end-to-end at the data layer.
  Future<void> selectProfilePhoto({
    required String organizationId,
    required String photoId,
  });

  /// P.4.3B — a live view of the customer's own canonical PUBLIC photo
  /// selection, read directly from `customerPublicProfiles/{organizationId}_{customerId}`
  /// (`.selectedProfilePhotoRef`, `null` if no document/field exists yet).
  /// This is the ONE authoritative source for "what other users see" —
  /// deliberately never derived from `CustomerPhoto.isSelectedAsProfilePhoto`
  /// (a per-photo mirror field, not the projection itself). Read-only;
  /// nothing in this file ever writes this collection — selection remains
  /// exclusively server-authoritative (`selectCustomerProfilePhoto`,
  /// `moderateCustomerPhoto`'s auto-selection).
  Stream<String?> watchSelectedProfilePhotoRef({
    required String organizationId,
    required String customerId,
  });
}

class FirebaseCustomerPhotoGateway implements CustomerPhotoGateway {
  FirebaseCustomerPhotoGateway({
    fs.FirebaseFirestore? firestore,
    functions.FirebaseFunctions? functionsInstance,
    LoggingService? loggingService,
  })  : _firestore = firestore ?? fs.FirebaseFirestore.instance,
        _functions = functionsInstance ?? functions.FirebaseFunctions.instance,
        _loggingService = loggingService ?? defaultLoggingService();

  final fs.FirebaseFirestore _firestore;
  final functions.FirebaseFunctions _functions;
  final LoggingService _loggingService;

  @override
  Stream<List<CustomerPhoto>> watchGallery({
    required String organizationId,
    required String customerId,
  }) {
    return _firestore
        .collection('customerPhotos')
        .where('customerId', isEqualTo: customerId)
        .where('organizationId', isEqualTo: organizationId)
        .snapshots()
        .map((snapshot) => [
              for (final doc in snapshot.docs) _mapPhoto(doc.id, doc.data()),
            ]);
  }

  CustomerPhoto _mapPhoto(String id, Map<String, dynamic> data) {
    return CustomerPhoto(
      id: id,
      customerId: data['customerId'] as String,
      organizationId: data['organizationId'] as String,
      photoRef: data['photoRef'] as String,
      status: CustomerPhotoStatus.values.byName(data['status'] as String),
      isSelectedAsProfilePhoto:
          data['isSelectedAsProfilePhoto'] as bool? ?? false,
      uploadedAt: (data['uploadedAt'] as fs.Timestamp).toDate(),
      reviewedByStaffId: data['reviewedByStaffId'] as String?,
      reviewedAt: (data['reviewedAt'] as fs.Timestamp?)?.toDate(),
      rejectionReason: data['rejectionReason'] as String?,
      revision: data['revision'] as int? ?? 1,
      purpose: data['purpose'] as String?,
    );
  }

  @override
  Future<CustomerPhotoUploadGrant> requestUploadGrant({
    required String organizationId,
    required String contentType,
    String? purpose,
  }) async {
    final callable =
        _functions.httpsCallable('requestCustomerPhotoUploadGrant');

    logUploadMilestone(_loggingService, 'grant callable invoke', {
      'organizationId': organizationId,
      'contentType': contentType,
      'purpose': purpose,
    });

    functions.HttpsCallableResult<Map<String, dynamic>> result;
    try {
      // The bounded hang diagnostic wraps ONLY this Future — never the
      // parsing below — specifically so a future physical-device run can
      // tell apart "the callable itself never resolved" from "it resolved
      // but parsing the response failed."
      result = await withUploadHangDiagnostic(
        _loggingService,
        'requestCustomerPhotoUploadGrant callable',
        callable.call<Map<String, dynamic>>({
          'organizationId': organizationId,
          'contentType': contentType,
          if (purpose != null) 'purpose': purpose,
        }),
      );
    } on functions.FirebaseFunctionsException catch (error, stackTrace) {
      _logGrantCallableFailure(
        error: error,
        stackTrace: stackTrace,
        stage: 'callable',
      );
      throw CustomerPhotoGatewayException(
        error.code,
        error.message ?? 'Yükleme izni alınamadı.',
      );
    } catch (error, stackTrace) {
      _logGrantCallableFailure(
        error: error,
        stackTrace: stackTrace,
        stage: 'callable',
      );
      throw const CustomerPhotoGatewayException(
        'unknown',
        'Yükleme izni alınamadı.',
      );
    }

    final data = result.data;
    logUploadMilestone(
      _loggingService,
      'grant callable raw response received',
      buildGrantCallableResponseLogContext(data),
    );

    try {
      logUploadMilestone(_loggingService, 'grant response parse started');
      final grant = parseCustomerPhotoUploadGrant(data);
      logUploadMilestone(_loggingService, 'grant response parse succeeded', {
        'grantId': grant.grantId,
      });
      return grant;
    } catch (error, stackTrace) {
      _logGrantCallableFailure(
        error: error,
        stackTrace: stackTrace,
        stage: 'parse',
      );
      throw const CustomerPhotoGatewayException(
        'parse-error',
        'Yükleme izni alınamadı.',
      );
    }
  }

  /// DEVELOPMENT-ONLY. Logs the exception's runtime type,
  /// `FirebaseFunctionsException.plugin`/`.code`/`.message` when
  /// applicable, and the stack trace, through the existing
  /// `LoggingService`/`LogRedactor` boundary. Never logs auth/App Check
  /// tokens or any callable request/response payload value.
  void _logGrantCallableFailure({
    required Object error,
    required StackTrace stackTrace,
    required String stage,
  }) {
    if (AppEnvironment.current != AppEnvironment.development) return;
    _loggingService.log(
      LogLevel.error,
      '[CustomerPhotoUpload] grant callable failed ($stage)',
      error: error,
      stackTrace: stackTrace,
      context: {
        'stage': stage,
        'exceptionType': error.runtimeType.toString(),
        'firebaseFunctionsExceptionPlugin':
            error is functions.FirebaseFunctionsException ? error.plugin : null,
        'firebaseFunctionsExceptionCode':
            error is functions.FirebaseFunctionsException ? error.code : null,
        'firebaseFunctionsExceptionMessage':
            error is functions.FirebaseFunctionsException
                ? error.message
                : null,
      },
    );
  }

  @override
  Future<void> selectProfilePhoto({
    required String organizationId,
    required String photoId,
  }) async {
    final callable = _functions.httpsCallable('selectCustomerProfilePhoto');
    try {
      await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'photoId': photoId,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      throw CustomerPhotoGatewayException(
        error.code,
        error.message ?? 'Fotoğraf seçilemedi.',
      );
    }
  }

  @override
  Stream<String?> watchSelectedProfilePhotoRef({
    required String organizationId,
    required String customerId,
  }) {
    return _firestore
        .collection('customerPublicProfiles')
        .doc('${organizationId}_$customerId')
        .snapshots()
        .map((snapshot) =>
            snapshot.data()?['selectedProfilePhotoRef'] as String?);
  }
}
