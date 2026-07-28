import '../../../../core/errors/business_rule_violation.dart';
import '../../../qr/domain/models/restaurant_table.dart';
import '../../data/restaurant_table_repository.dart';

/// Updates a [RestaurantTable]'s [TableStatus] — e.g. staff marking a
/// table `occupied`/`cleaning`/`disabled` from the live floor map.
///
/// A pure status change: no other field is touched. Throws
/// [UnknownRestaurantOperationsEntityViolation] if [tableId] doesn't
/// resolve.
class SetTableStatus {
  const SetTableStatus({required RestaurantTableRepository repository})
      : _repository = repository;

  final RestaurantTableRepository _repository;

  Future<RestaurantTable> call({
    required String tableId,
    required TableStatus status,
  }) async {
    final table = await _repository.findById(tableId);
    if (table == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'RestaurantTable',
        id: tableId,
      );
    }
    final updated = table.copyWith(status: status);
    await _repository.save(updated);
    return updated;
  }
}
