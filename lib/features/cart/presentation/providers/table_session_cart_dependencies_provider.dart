import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/table_session_cart_firestore_client.dart';

final tableSessionCartFirestoreClientProvider =
    Provider<TableSessionCartFirestoreClient>((ref) {
  return DefaultTableSessionCartFirestoreClient();
});
