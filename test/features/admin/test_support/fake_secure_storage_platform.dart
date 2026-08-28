import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

/// An in-memory [FlutterSecureStoragePlatform] fake — installed as
/// `FlutterSecureStoragePlatform.instance` for any test exercising
/// [SecureDeviceKeyStore]/[DeviceSessionCache]'s real `FlutterSecureStorage`
/// usage, since the real platform channel implementation has no backing
/// plugin under `flutter test`. Deliberately duplicated across test files
/// rather than shared via a wider test harness, mirroring this codebase's
/// own established "each test file owns its fakes" convention.
class FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> _values = {};

  /// Set to force the next [read] to throw — simulates a corrupted/
  /// unreadable secure storage entry without needing to write genuinely
  /// malformed platform-channel data.
  Object? throwOnNextRead;

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    final pending = throwOnNextRead;
    if (pending != null) {
      throwOnNextRead = null;
      throw pending;
    }
    return _values[key];
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    return _values.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    return Map.of(_values);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _values.clear();
  }
}
