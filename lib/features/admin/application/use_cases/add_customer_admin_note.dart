import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/customer_admin_note_repository.dart';
import '../../domain/customer/customer_admin_note.dart';
import '../identity/customer_admin_note_id_generator.dart';

/// Adds a staff note (optionally a risk/review flag) to a customer's
/// admin record — staff-authorized (`PosAuthorizedAction.viewCustomerAdmin`
/// covers day-to-day operational notes; account restriction itself is a
/// separate, manager-gated action — `SetCustomerAccountStatus`). Notes
/// are immutable and append-only — no edit/delete exists.
class AddCustomerAdminNote {
  const AddCustomerAdminNote({
    required PosAuthorizationPolicy authorizationPolicy,
    required CustomerAdminNoteIdGenerator idGenerator,
    required CustomerAdminNoteRepository repository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final CustomerAdminNoteIdGenerator _idGenerator;
  final CustomerAdminNoteRepository _repository;

  Future<CustomerAdminNote> call({
    required String customerId,
    required String body,
    bool isFlag = false,
    required String performedByStaffId,
    required DateTime createdAt,
  }) async {
    const action = PosAuthorizedAction.viewCustomerAdmin;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final note = CustomerAdminNote(
      id: _idGenerator.nextNoteId(),
      customerId: customerId,
      authorStaffId: performedByStaffId,
      body: body,
      isFlag: isFlag,
      createdAt: createdAt,
    );
    await _repository.append(note);
    return note;
  }
}
