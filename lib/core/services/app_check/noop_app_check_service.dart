import 'app_check_service.dart';

class NoOpAppCheckService implements AppCheckService {
  const NoOpAppCheckService();

  @override
  Future<void> initialize() async {}
}
