import '../domain/device/admin_device_registration.dart';

abstract interface class AdminDeviceRegistrationRepository {
  Future<void> save(AdminDeviceRegistration registration);
  Future<AdminDeviceRegistration?> findById(String registrationId);

  /// Branch-scoped — never an unscoped "all registrations" query, so
  /// branch data never leaks across branches.
  Future<List<AdminDeviceRegistration>> findByBranchId(String branchId);
}

class InMemoryAdminDeviceRegistrationRepository
    implements AdminDeviceRegistrationRepository {
  final Map<String, AdminDeviceRegistration> _byId = {};

  @override
  Future<void> save(AdminDeviceRegistration registration) async =>
      _byId[registration.id] = registration;

  @override
  Future<AdminDeviceRegistration?> findById(String registrationId) async =>
      _byId[registrationId];

  @override
  Future<List<AdminDeviceRegistration>> findByBranchId(String branchId) async {
    return List.unmodifiable(
      _byId.values.where((r) => r.branchId == branchId),
    );
  }
}
