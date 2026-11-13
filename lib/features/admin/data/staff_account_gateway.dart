import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';
import '../../pos/domain/authorization/staff_role.dart';

/// A refused staff-account command, already translated into a Turkish
/// message the screen can show as is — never the server's raw text.
class StaffAccountException implements Exception {
  const StaffAccountException(this.message);
  final String message;
  @override
  String toString() => 'StaffAccountException: $message';
}

/// ADR-085 (revision) — the panel's staff-account commands: "Personel
/// Ekle", set a staff member's password, change roles/branches/status.
/// Each maps to one callable in `functions/src/staffAccounts.ts`, which
/// enforces who may manage whom; this client never decides that.
abstract interface class StaffAccountGateway {
  Future<void> createStaffAccount({
    required String organizationId,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String password,
    required Set<StaffRole> roles,
    required Set<String> branchAccess,
  });

  Future<void> setStaffPassword({
    required String organizationId,
    required String targetUid,
    required String password,
  });

  Future<void> updateStaffMember({
    required String organizationId,
    required String targetUid,
    Set<StaffRole>? roles,
    bool? active,
  });
}

/// The real gateway. Windows has no `cloud_functions` plugin, so calls go
/// through [RestCallableClient] there, like every other staff gateway.
class FirebaseStaffAccountGateway implements StaffAccountGateway {
  FirebaseStaffAccountGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  /// Turkish message for a refused call, by callable error code.
  static String messageFor(String code) {
    switch (code) {
      case 'permission-denied':
        return 'Bu işlem için yetkiniz yok.';
      case 'already-exists':
        return 'Bu telefon numarası zaten personel olarak kayıtlı.';
      case 'invalid-argument':
        return 'Bilgileri kontrol edin: ad, soyad, geçerli bir telefon '
            'numarası ve en az 8 karakterli şifre gerekli.';
      case 'failed-precondition':
        return 'Bu numaraya bağlı hesap personel olarak eklenemiyor.';
      case 'not-found':
        return 'Personel bulunamadı.';
      case 'unauthenticated':
        return 'Oturumunuz sona ermiş. Lütfen tekrar giriş yapın.';
      default:
        return 'İşlem tamamlanamadı. Bağlantınızı kontrol edip tekrar deneyin.';
    }
  }

  Future<void> _call(String name, Map<String, dynamic> data) async {
    final useRest = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    if (useRest) {
      try {
        await _restClient.call(name, data);
        return;
      } on RestCallableException catch (error) {
        throw StaffAccountException(messageFor(error.code));
      }
    }
    try {
      await functions.FirebaseFunctions.instance
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data);
    } on functions.FirebaseFunctionsException catch (error) {
      throw StaffAccountException(messageFor(error.code));
    }
  }

  @override
  Future<void> createStaffAccount({
    required String organizationId,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String password,
    required Set<StaffRole> roles,
    required Set<String> branchAccess,
  }) =>
      _call('createStaffAccount', {
        'organizationId': organizationId,
        'firstName': firstName,
        'lastName': lastName,
        'phoneNumber': phoneNumber,
        'password': password,
        'roles': [for (final role in roles) role.name],
        'branchAccess': branchAccess.toList(),
      });

  @override
  Future<void> setStaffPassword({
    required String organizationId,
    required String targetUid,
    required String password,
  }) =>
      _call('setStaffPassword', {
        'organizationId': organizationId,
        'targetUid': targetUid,
        'password': password,
      });

  @override
  Future<void> updateStaffMember({
    required String organizationId,
    required String targetUid,
    Set<StaffRole>? roles,
    bool? active,
  }) =>
      _call('updateStaffMember', {
        'organizationId': organizationId,
        'targetUid': targetUid,
        if (roles != null) 'roles': [for (final role in roles) role.name],
        if (active != null) 'status': active ? 'active' : 'suspended',
      });
}

/// Selected whenever Firebase isn't ready — every command fails honestly.
class UnavailableStaffAccountGateway implements StaffAccountGateway {
  const UnavailableStaffAccountGateway();

  static const _unavailable = StaffAccountException(
    'Personel işlemleri şu anda kullanılamıyor.',
  );

  @override
  Future<void> createStaffAccount({
    required String organizationId,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String password,
    required Set<StaffRole> roles,
    required Set<String> branchAccess,
  }) async =>
      throw _unavailable;

  @override
  Future<void> setStaffPassword({
    required String organizationId,
    required String targetUid,
    required String password,
  }) async =>
      throw _unavailable;

  @override
  Future<void> updateStaffMember({
    required String organizationId,
    required String targetUid,
    Set<StaffRole>? roles,
    bool? active,
  }) async =>
      throw _unavailable;
}
