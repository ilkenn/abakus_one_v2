/// Centrally defined route paths — screens never hard-code a path string
/// directly; every navigation call site uses one of these constants.
abstract final class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String otp = '/otp';
  static const String main = '/main';
}
