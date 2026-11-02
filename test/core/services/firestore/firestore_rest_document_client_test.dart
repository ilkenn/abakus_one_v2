import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:abakus_one_v2/bootstrap/app_environment.dart';
import 'package:abakus_one_v2/core/services/firestore/firestore_rest_document_client.dart';

/// Covers `FirestoreRestDocumentClient`'s request construction and its
/// Firestore REST wire-value decoding, via an injected `MockClient` —
/// mirrors `rest_callable_client_test.dart`'s established pattern. This is
/// the Windows-desktop fix (2026-10-30) for `FirebasePlatformMemberRepository
/// .findById` under a pure-REST session — see that class's own doc
/// comment.
void main() {
  test('decodes a document with string/array/boolean/timestamp/integer fields',
      () async {
    final mockClient = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer fake-id-token');
      expect(request.url.host, 'firestore.googleapis.com');
      expect(
        request.url.path,
        '/v1/projects/proj-1/databases/(default)/documents/platformMembers/uid-1',
      );
      return http.Response(
        '{"fields":{'
        '"displayName":{"stringValue":"Ada"},'
        '"roles":{"arrayValue":{"values":[{"stringValue":"platformOwner"}]}},'
        '"isActive":{"booleanValue":true},'
        '"version":{"integerValue":"3"},'
        '"createdAt":{"timestampValue":"2026-01-01T00:00:00Z"}'
        '}}',
        200,
      );
    });
    final client = FirestoreRestDocumentClient(
      httpClient: mockClient,
      environmentOverride: AppEnvironment.staging,
    );

    final data = await client.getDocument(
      projectId: 'proj-1',
      collection: 'platformMembers',
      documentId: 'uid-1',
      idToken: 'fake-id-token',
    );

    expect(data, isNotNull);
    expect(data!['displayName'], 'Ada');
    expect(data['roles'], ['platformOwner']);
    expect(data['isActive'], true);
    expect(data['version'], 3);
    expect(data['createdAt'], DateTime.parse('2026-01-01T00:00:00Z'));
  });

  test('a 404 response returns null, never throws', () async {
    final mockClient = MockClient((request) async {
      return http.Response('{}', 404);
    });
    final client = FirestoreRestDocumentClient(
      httpClient: mockClient,
      environmentOverride: AppEnvironment.staging,
    );

    final data = await client.getDocument(
      projectId: 'proj-1',
      collection: 'platformMembers',
      documentId: 'does-not-exist',
      idToken: 'fake-id-token',
    );

    expect(data, isNull);
  });

  test('a permission-denied response throws FirestoreRestDocumentException',
      () async {
    final mockClient = MockClient((request) async {
      return http.Response('{"error":{"message":"PERMISSION_DENIED"}}', 403);
    });
    final client = FirestoreRestDocumentClient(
      httpClient: mockClient,
      environmentOverride: AppEnvironment.staging,
    );

    await expectLater(
      client.getDocument(
        projectId: 'proj-1',
        collection: 'platformMembers',
        documentId: 'uid-1',
        idToken: 'fake-id-token',
      ),
      throwsA(isA<FirestoreRestDocumentException>()),
    );
  });

  test(
      "Firestore's own error body (code/message) is parsed and surfaced on "
      'the thrown exception, never collapsed to just the HTTP status',
      () async {
    final mockClient = MockClient((request) async {
      return http.Response(
        '{"error":{"code":9,"message":"The query requires an index.",'
        '"status":"FAILED_PRECONDITION"}}',
        400,
      );
    });
    final client = FirestoreRestDocumentClient(
      httpClient: mockClient,
      environmentOverride: AppEnvironment.staging,
    );

    await expectLater(
      client.getDocument(
        projectId: 'proj-1',
        collection: 'platformMembers',
        documentId: 'uid-1',
        idToken: 'fake-id-token',
      ),
      throwsA(
        isA<FirestoreRestDocumentException>()
            .having((e) => e.code, 'code', 'FAILED_PRECONDITION')
            .having((e) => e.message, 'message',
                contains('The query requires an index.')),
      ),
    );
  });

  test('a transport-level failure is wrapped, never left raw', () async {
    final mockClient = MockClient((request) async {
      throw Exception('connection refused');
    });
    final client = FirestoreRestDocumentClient(
      httpClient: mockClient,
      environmentOverride: AppEnvironment.staging,
    );

    await expectLater(
      client.getDocument(
        projectId: 'proj-1',
        collection: 'platformMembers',
        documentId: 'uid-1',
        idToken: 'fake-id-token',
      ),
      throwsA(isA<FirestoreRestDocumentException>()),
    );
  });

  test('against development, targets the local Firestore Emulator host/path',
      () async {
    final mockClient = MockClient((request) async {
      expect(request.url.scheme, 'http');
      expect(
        request.url.path,
        '/v1/projects/proj-1/databases/(default)/documents/platformMembers/uid-1',
      );
      return http.Response('{"fields":{}}', 200);
    });
    final client = FirestoreRestDocumentClient(
      httpClient: mockClient,
      environmentOverride: AppEnvironment.development,
    );

    await client.getDocument(
      projectId: 'proj-1',
      collection: 'platformMembers',
      documentId: 'uid-1',
      idToken: 'fake-id-token',
    );
  });

  group('runQuery', () {
    test(
        'sends an AND-composite equality query with a descending orderBy, '
        'and decodes every matched document', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer fake-id-token');
        expect(
          request.url.path,
          '/v1/projects/proj-1/databases/(default)/documents:runQuery',
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final query = body['structuredQuery'] as Map<String, dynamic>;
        expect(query['from'], [
          {'collectionId': 'trustedDeviceRegistrations'}
        ]);
        final where = query['where'] as Map<String, dynamic>;
        final composite = where['compositeFilter'] as Map<String, dynamic>;
        expect(composite['op'], 'AND');
        expect((composite['filters'] as List).length, 2);
        final orderBy = (query['orderBy'] as List).single as Map;
        expect(orderBy['direction'], 'DESCENDING');

        return http.Response(
          jsonEncode([
            {
              'document': {
                'fields': {
                  'deviceId': {'stringValue': 'device-1'},
                },
              },
            },
            // A heartbeat/progress entry carries no `document` at all —
            // must never be mistaken for a zero-field match.
            {'readTime': '2026-01-01T00:00:00Z'},
          ]),
          200,
        );
      });
      final client = FirestoreRestDocumentClient(
        httpClient: mockClient,
        environmentOverride: AppEnvironment.staging,
      );

      final results = await client.runQuery(
        projectId: 'proj-1',
        collection: 'trustedDeviceRegistrations',
        whereEquals: {'organizationId': 'org-1', 'branchId': 'branch-1'},
        orderByField: 'registeredAt',
        idToken: 'fake-id-token',
      );

      expect(results, [
        {'deviceId': 'device-1'}
      ]);
    });

    test('an HTTP error is wrapped, never left raw', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"error":{"message":"PERMISSION_DENIED"}}', 403);
      });
      final client = FirestoreRestDocumentClient(
        httpClient: mockClient,
        environmentOverride: AppEnvironment.staging,
      );

      await expectLater(
        client.runQuery(
          projectId: 'proj-1',
          collection: 'trustedDeviceRegistrations',
          whereEquals: {'organizationId': 'org-1', 'branchId': 'branch-1'},
          orderByField: 'registeredAt',
          idToken: 'fake-id-token',
        ),
        throwsA(isA<FirestoreRestDocumentException>()),
      );
    });

    test('a transport-level failure is wrapped, never left raw', () async {
      final mockClient = MockClient((request) async {
        throw Exception('connection refused');
      });
      final client = FirestoreRestDocumentClient(
        httpClient: mockClient,
        environmentOverride: AppEnvironment.staging,
      );

      await expectLater(
        client.runQuery(
          projectId: 'proj-1',
          collection: 'trustedDeviceRegistrations',
          whereEquals: {'organizationId': 'org-1', 'branchId': 'branch-1'},
          orderByField: 'registeredAt',
          idToken: 'fake-id-token',
        ),
        throwsA(isA<FirestoreRestDocumentException>()),
      );
    });
  });
}
