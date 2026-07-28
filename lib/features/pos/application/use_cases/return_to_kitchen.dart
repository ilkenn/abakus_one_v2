import '../../../../core/errors/business_rule_violation.dart';
import '../../../orders/data/package_preparation_repository.dart';
import '../../../orders/domain/fulfillment/package_preparation.dart';
import '../../../orders/domain/fulfillment/package_preparation_status.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';

/// Sends a [PackagePreparationStatus.exception] package back to
/// [PackagePreparationStatus.preparing] with a required [reason] —
/// the correction path for a package that failed inspection or needs
/// remaking.
///
/// If the package had already reached [PackagePreparationStatus.packed]
/// (i.e. [PackagePreparation.preparationCompletedAt] is set) before
/// entering the exception state, this is a **completion override** and
/// requires [PosAuthorizedAction.packageCompletionOverride] to be granted
/// first — per the explicit requirement that overriding package
/// completion needs authorization. A package that never reached `packed`
/// requires no authorization; sending unpacked, still-in-progress work
/// back to the kitchen is routine.
///
/// Throws [UnknownRestaurantOperationsEntityViolation] if no
/// [PackagePreparation] exists, [InvalidPackagePreparationTransitionViolation]
/// if the package isn't currently in [PackagePreparationStatus.exception],
/// or [AuthorizationDeniedViolation] if a required authorization check is
/// denied.
class ReturnToKitchen {
  const ReturnToKitchen({
    required PosAuthorizationPolicy authorizationPolicy,
    required PackagePreparationRepository repository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final PackagePreparationRepository _repository;

  Future<PackagePreparation> call({
    required OrderId orderId,
    required String reason,
    required String performedByStaffId,
  }) async {
    final current = await _repository.findCurrentByOrderId(orderId);
    if (current == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'PackagePreparation',
        id: orderId.value,
      );
    }
    if (current.status != PackagePreparationStatus.exception) {
      throw InvalidPackagePreparationTransitionViolation(
        fromStatusName: current.status.name,
        toStatusName: PackagePreparationStatus.preparing.name,
      );
    }

    if (current.preparationCompletedAt != null) {
      final authResult = await _authorizationPolicy.authorize(
        action: PosAuthorizedAction.packageCompletionOverride,
        actorStaffId: performedByStaffId,
        context: {'orderId': orderId.value},
      );
      if (!authResult.granted) {
        throw AuthorizationDeniedViolation(
          actionName: PosAuthorizedAction.packageCompletionOverride.name,
        );
      }
    }

    final updated = current.copyWith(
      status: PackagePreparationStatus.preparing,
      correctionReason: reason,
      revision: current.revision + 1,
    );
    await _repository.save(updated);
    return updated;
  }
}
