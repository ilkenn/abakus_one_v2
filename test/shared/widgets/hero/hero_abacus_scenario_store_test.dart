import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abakus_one_v2/shared/widgets/hero/hero_abacus_scenario_store.dart';

void main() {
  const store = SharedPreferencesHeroAbacusScenarioStore();

  group('SharedPreferencesHeroAbacusScenarioStore', () {
    test('reads 0 when nothing has been stored yet', () async {
      SharedPreferences.setMockInitialValues({});

      expect(await store.readScenarioIndex(), 0);
    });

    test('reads 0 when the stored value is out of the valid 0..11 range',
        () async {
      SharedPreferences.setMockInitialValues({
        'heroAbacusScenarioIndex': 12,
      });

      expect(await store.readScenarioIndex(), 0);
    });

    test('reads 0 when the stored value is negative', () async {
      SharedPreferences.setMockInitialValues({
        'heroAbacusScenarioIndex': -1,
      });

      expect(await store.readScenarioIndex(), 0);
    });

    test('reads back a valid stored value unchanged', () async {
      SharedPreferences.setMockInitialValues({
        'heroAbacusScenarioIndex': 5,
      });

      expect(await store.readScenarioIndex(), 5);
    });

    test('persistNextScenarioIndex advances by one', () async {
      SharedPreferences.setMockInitialValues({});

      await store.persistNextScenarioIndex(5);

      expect(await store.readScenarioIndex(), 6);
    });

    test('persistNextScenarioIndex wraps scenario 11 back to 0', () async {
      SharedPreferences.setMockInitialValues({});

      await store.persistNextScenarioIndex(11);

      expect(await store.readScenarioIndex(), 0);
    });
  });
}
