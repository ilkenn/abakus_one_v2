import '../domain/customer/customer_admin_note.dart';

abstract interface class CustomerAdminNoteRepository {
  Future<void> append(CustomerAdminNote note);
  Future<List<CustomerAdminNote>> findByCustomerId(String customerId);
}

class InMemoryCustomerAdminNoteRepository
    implements CustomerAdminNoteRepository {
  final List<CustomerAdminNote> _notes = [];

  @override
  Future<void> append(CustomerAdminNote note) async {
    _notes.add(note);
  }

  @override
  Future<List<CustomerAdminNote>> findByCustomerId(String customerId) async {
    return List.unmodifiable(
      _notes.where((n) => n.customerId == customerId),
    );
  }
}
