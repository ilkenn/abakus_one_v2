import 'package:integration_test/integration_test_driver.dart';

/// Driver entry point for `flutter drive` against `integration_test/*.dart`
/// on Web — required for `staff_sign_in_e2e_test.dart` (AP-3) to run as a
/// real browser-driven test rather than only via manual Playwright
/// verification. Run with:
///
/// ```
/// flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/staff_sign_in_e2e_test.dart \
///   -d web-server --browser-name=chrome
/// ```
Future<void> main() => integrationDriver();
