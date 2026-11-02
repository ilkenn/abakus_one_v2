import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/config/app_environment_config.dart';
import '../../../core/services/auth/identity_toolkit_rest_auth_client.dart';
import '../../../core/services/auth/windows_rest_auth_session.dart';
import '../../../core/services/firestore/firestore_rest_document_client.dart';
import '../../../core/services/logging/log_level.dart';
import '../../../core/services/logging/logging_provider.dart';
import '../../../core/services/logging/logging_service.dart';
import '../domain/trusted_device/trusted_device.dart';

/// AP-2 final wiring — direct Firestore reads staff are already permitted
/// to make (`trustedDeviceRegistrations`'s own rule:
/// `isOrgMember(...) && hasBranchAccess(...)`, unchanged this pass). No
/// list/read callable exists or is needed — mirrors
/// `AdminReservationRepository`'s exact "read the canonical backend-written
/// document directly" shape.
abstract interface class TrustedDeviceRepository {
  /// A live stream of every device registered for this branch, most
  /// recently registered first. Backend-unavailable (no Firebase, or the
  /// read itself fails) surfaces as a stream error — the caller is
  /// expected to render this as an explicit "backend unavailable" state,
  /// never a silent empty list.
  Stream<List<TrustedDevice>> watchDevicesForBranch({
    required String organizationId,
    required String branchId,
  });
}

class FirestoreTrustedDeviceRepository implements TrustedDeviceRepository {
  FirestoreTrustedDeviceRepository({
    fs.FirebaseFirestore? firestore,
    FirestoreRestDocumentClient? restDocumentClient,
    LoggingService? logging,
  })  : _providedFirestore = firestore,
        _restDocumentClient =
            restDocumentClient ?? FirestoreRestDocumentClient(),
        _logging = logging ?? defaultLoggingService();

  // Lazily resolved — see `FirebasePlatformMemberRepository`'s identical
  // doc comment for why construction alone must never require a real
  // `Firebase.initializeApp()`.
  final fs.FirebaseFirestore? _providedFirestore;
  final FirestoreRestDocumentClient _restDocumentClient;
  final LoggingService _logging;
  fs.FirebaseFirestore get _firestore =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  /// How often the Windows-REST polling path below re-queries — mirrors
  /// `DineInLineApprovalSection`'s existing 6-second `Timer`-based polling
  /// convention (`dine_in_line_approval_section.dart`), this codebase's
  /// one other precedent for "live" staff-facing data without a native
  /// Firestore stream underneath it.
  static const _pollInterval = Duration(seconds: 6);

  @override
  Stream<List<TrustedDevice>> watchDevicesForBranch({
    required String organizationId,
    required String branchId,
  }) {
    final useRestFirestore = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        fb.FirebaseAuth.instance.currentUser == null &&
        WindowsRestAuthSession.isActive;

    if (useRestFirestore) {
      return _watchViaRestPolling(
        organizationId: organizationId,
        branchId: branchId,
      );
    }

    return _firestore
        .collection('trustedDeviceRegistrations')
        .where('organizationId', isEqualTo: organizationId)
        .where('branchId', isEqualTo: branchId)
        .orderBy('registeredAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            [for (final doc in snapshot.docs) _mapDevice(doc.data())]);
  }

  /// 2026-10-30 — the native `cloud_firestore` `.snapshots()` stream above
  /// relies on the plugin's own ambient auth session, which a pure-REST
  /// Windows sign-in (`RestEmailPasswordAuthClient`) never populates — see
  /// `FirestoreRestDocumentClient`'s own doc comment for why. There is no
  /// REST equivalent of a Firestore *listen* stream reachable from plain
  /// HTTP, so this polls the same query instead via `:runQuery`, on the
  /// same cadence `DineInLineApprovalSection` already established for
  /// "live enough" staff-facing data. Stops polling the moment the stream
  /// is cancelled (the controller disposes/cancels its subscription on
  /// every state transition — see `TrustedDeviceSessionController
  /// .dispose`/`_watchDeviceStatus`), never leaking a timer.
  Stream<List<TrustedDevice>> _watchViaRestPolling({
    required String organizationId,
    required String branchId,
  }) {
    late StreamController<List<TrustedDevice>> controller;
    Timer? timer;

    Future<void> poll() async {
      try {
        final idToken = await WindowsRestAuthSession.currentIdToken(
          client: DefaultIdentityToolkitRestAuthClient(),
        );
        if (idToken == null) {
          controller.addError(
            StateError('No Windows REST session is active.'),
          );
          return;
        }
        final results = await _restDocumentClient.runQuery(
          projectId: AppEnvironmentConfig.current.firebaseProjectId,
          collection: 'trustedDeviceRegistrations',
          whereEquals: {
            'organizationId': organizationId,
            'branchId': branchId,
          },
          orderByField: 'registeredAt',
          idToken: idToken,
        );
        controller.add([for (final data in results) _mapDevice(data)]);
      } catch (error, stackTrace) {
        // 2026-10-30 — `DeviceRegistryScreen`'s `ErrorView` deliberately
        // shows only a generic Turkish message (never a raw exception to
        // the end user, `CLAUDE.md` §9) — this is the one place the real
        // cause (e.g. Firestore's own `FAILED_PRECONDITION` "requires an
        // index" body, surfaced by `FirestoreRestDocumentException`'s own
        // real-error-body parsing) is actually visible, in the console a
        // developer doing staging QA is already watching.
        _logging.log(
          LogLevel.error,
          '[TRUSTED-DEVICE-REST-POLL] query failed for '
          'org=$organizationId branch=$branchId',
          error: error,
          stackTrace: stackTrace,
        );
        controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<List<TrustedDevice>>(
      onListen: () {
        unawaited(poll());
        timer = Timer.periodic(_pollInterval, (_) => unawaited(poll()));
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );
    return controller.stream;
  }

  /// Accepts either a native `fs.Timestamp` (the direct-Firestore-read
  /// path) or an already-decoded [DateTime] (`FirestoreRestDocumentClient`
  /// decodes `timestampValue` to [DateTime] itself) — mirrors
  /// `FirebasePlatformMemberRepository._mapMember`'s identical dual-shape
  /// handling, the one field whose wire shape genuinely differs between
  /// the two read paths.
  DateTime? _timestamp(dynamic value) {
    if (value is fs.Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  TrustedDevice _mapDevice(Map<String, dynamic> data) {
    return TrustedDevice(
      deviceId: data['deviceId'] as String,
      organizationId: data['organizationId'] as String,
      branchId: data['branchId'] as String,
      platform: trustedDevicePlatformFromWire(data['platform'] as String),
      capabilities: [
        for (final c in (data['capabilities'] as List))
          trustedDeviceCapabilityFromWire(c as String),
      ],
      status: trustedDeviceStatusFromWire(data['status'] as String),
      trustTier: trustedDeviceTrustTierFromWire(data['trustTier'] as String),
      registeredByUid: data['registeredByUid'] as String,
      registeredAt: _timestamp(data['registeredAt'])!,
      activatedAt: _timestamp(data['activatedAt']),
      lastSeenAt: _timestamp(data['lastSeenAt']),
      revokedAt: _timestamp(data['revokedAt']),
      revokedReason: data['revokedReason'] as String?,
      version: data['version'] as int,
    );
  }
}

/// `firebaseReadyProvider` is false — an explicit, disclosed "backend
/// unavailable" stream rather than an empty list, so the UI renders a real
/// error state instead of a silently-empty (and misleading) device roster.
class UnavailableTrustedDeviceRepository implements TrustedDeviceRepository {
  const UnavailableTrustedDeviceRepository();

  @override
  Stream<List<TrustedDevice>> watchDevicesForBranch({
    required String organizationId,
    required String branchId,
  }) {
    return Stream.error(
        StateError('Trusted device backend is not available in this build.'));
  }
}
