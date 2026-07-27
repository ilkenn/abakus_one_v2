import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/bootstrap/app_environment.dart';
import 'package:abakus_one_v2/core/config/firebase_options_selector.dart';

void main() {
  group('FirebaseOptionsSelector.forEnvironment', () {
    test('development resolves to the abakus-one-dev project only', () {
      final options =
          FirebaseOptionsSelector.forEnvironment(AppEnvironment.development);
      expect(options.projectId, 'abakus-one-dev');
    });

    test('staging resolves to the abakus-one-staging project only', () {
      final options =
          FirebaseOptionsSelector.forEnvironment(AppEnvironment.staging);
      expect(options.projectId, 'abakus-one-staging');
    });

    test('production resolves to the abakusone project only', () {
      final options =
          FirebaseOptionsSelector.forEnvironment(AppEnvironment.production);
      expect(options.projectId, 'abakusone');
    });

    test(
        'every environment resolves to a distinct project — none share a '
        'project ID with another', () {
      final projectIds = AppEnvironment.values
          .map(
            (environment) =>
                FirebaseOptionsSelector.forEnvironment(environment).projectId,
          )
          .toSet();

      expect(projectIds, hasLength(AppEnvironment.values.length));
    });

    test('development never resolves to the staging or production project ID',
        () {
      final options =
          FirebaseOptionsSelector.forEnvironment(AppEnvironment.development);
      expect(options.projectId, isNot('abakus-one-staging'));
      expect(options.projectId, isNot('abakusone'));
    });

    test('staging never resolves to the development or production project ID',
        () {
      final options =
          FirebaseOptionsSelector.forEnvironment(AppEnvironment.staging);
      expect(options.projectId, isNot('abakus-one-dev'));
      expect(options.projectId, isNot('abakusone'));
    });

    test(
        'production never resolves to the development or staging project '
        'ID', () {
      final options =
          FirebaseOptionsSelector.forEnvironment(AppEnvironment.production);
      expect(options.projectId, isNot('abakus-one-dev'));
      expect(options.projectId, isNot('abakus-one-staging'));
    });

    test(
        'an unrecognized --dart-define value never reaches production — '
        'it resolves through AppEnvironment.fromDefine to development '
        'first', () {
      final resolved = AppEnvironment.fromDefine('not_a_real_environment');
      expect(resolved, AppEnvironment.development);

      final options = FirebaseOptionsSelector.forEnvironment(resolved);
      expect(options.projectId, 'abakus-one-dev');
    });
  });
}
