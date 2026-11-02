import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../bootstrap/app_environment.dart';
import '../../../bootstrap/firebase_firestore_emulator_config.dart';

class FirestoreRestDocumentException implements Exception {
  const FirestoreRestDocumentException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'FirestoreRestDocumentException($code): $message';
}

/// 2026-10-30 — reads exactly one Firestore document via the Firestore
/// REST API (`GET .../documents/{collection}/{documentId}`), attaching an
/// explicit `Authorization: Bearer <idToken>` header per request.
///
/// **Why this exists, specifically**: `RestEmailPasswordAuthClient`'s own
/// doc comment already discloses that a REST-obtained token cannot
/// populate the native `firebase_auth`/`cloud_firestore` plugins' shared
/// ambient session state — so a *direct* native Firestore read (e.g.
/// `FirebaseFirestore.instance.collection(...).doc(...).get()`) still sees
/// `request.auth == null` server-side under a pure-REST Windows session,
/// regardless of how valid the REST token itself is. This class sidesteps
/// that specific gap for the one read that genuinely needs it
/// (`FirebasePlatformMemberRepository.findById`, gating whether a signed-
/// in Platform member can even reach the Platform Console at all on
/// Windows) by attaching the token explicitly, the exact same "stateless,
/// per-call auth" shape `RestCallableClient` already uses for Cloud
/// Functions.
///
/// **Deliberately narrow** — not a general `cloud_firestore` replacement.
/// Only single-document `GET`, only the handful of Firestore value-wire
/// types this app's own documents actually use
/// (`stringValue`/`integerValue`/`booleanValue`/`timestampValue`/
/// `arrayValue`/`mapValue`/`nullValue`) are decoded; anything else is
/// left out of the decoded map rather than guessed.
class FirestoreRestDocumentClient {
  FirestoreRestDocumentClient({
    http.Client? httpClient,
    AppEnvironment? environmentOverride,
  })  : _injectedClient = httpClient,
        _environmentOverride = environmentOverride;

  final http.Client? _injectedClient;
  final AppEnvironment? _environmentOverride;

  static const _timeout = Duration(seconds: 20);

  AppEnvironment get _environment =>
      _environmentOverride ?? AppEnvironment.current;

  /// `null` if the document doesn't exist — mirrors
  /// `DocumentSnapshot.exists == false`, never throws for "not found."
  Future<Map<String, dynamic>?> getDocument({
    required String projectId,
    required String collection,
    required String documentId,
    required String idToken,
  }) async {
    final useEmulator =
        FirebaseFirestoreEmulatorConfig.shouldUseEmulator(_environment);
    final uri = useEmulator
        ? Uri.http(
            '${FirebaseFirestoreEmulatorConfig.host}:${FirebaseFirestoreEmulatorConfig.port}',
            '/v1/projects/$projectId/databases/(default)/documents/$collection/$documentId',
          )
        : Uri.https(
            'firestore.googleapis.com',
            '/v1/projects/$projectId/databases/(default)/documents/$collection/$documentId',
          );

    final client = _injectedClient ?? http.Client();
    try {
      final response = await client.get(uri,
          headers: {'Authorization': 'Bearer $idToken'}).timeout(_timeout);

      if (response.statusCode == 404) return null;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FirestoreRestDocumentException(
          _errorStatus(response.body),
          'Could not read "$collection/$documentId" '
          '(HTTP ${response.statusCode}): ${_errorMessage(response.body)}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FirestoreRestDocumentException(
          'unknown',
          'Unexpected Firestore REST response shape.',
        );
      }
      final fields = decoded['fields'];
      if (fields is! Map<String, dynamic>) return const {};
      return _decodeFields(fields);
    } on FirestoreRestDocumentException {
      rethrow;
    } catch (error) {
      throw FirestoreRestDocumentException(
        'unknown',
        'Could not reach "$uri": $error',
      );
    } finally {
      if (_injectedClient == null) client.close();
    }
  }

  /// Runs a structured query (`POST .../documents:runQuery`) — narrowly
  /// scoped to what `FirestoreTrustedDeviceRepository`'s Windows-REST
  /// polling path needs (AND-equality filters + one descending `orderBy`),
  /// not a general query builder. Same per-request Bearer-token shape as
  /// [getDocument], for the identical reason.
  Future<List<Map<String, dynamic>>> runQuery({
    required String projectId,
    required String collection,
    required Map<String, String> whereEquals,
    required String orderByField,
    bool descending = true,
    required String idToken,
  }) async {
    final useEmulator =
        FirebaseFirestoreEmulatorConfig.shouldUseEmulator(_environment);
    final uri = useEmulator
        ? Uri.http(
            '${FirebaseFirestoreEmulatorConfig.host}:${FirebaseFirestoreEmulatorConfig.port}',
            '/v1/projects/$projectId/databases/(default)/documents:runQuery',
          )
        : Uri.https(
            'firestore.googleapis.com',
            '/v1/projects/$projectId/databases/(default)/documents:runQuery',
          );

    final filters = [
      for (final entry in whereEquals.entries)
        {
          'fieldFilter': {
            'field': {'fieldPath': entry.key},
            'op': 'EQUAL',
            'value': {'stringValue': entry.value},
          },
        },
    ];

    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': collection},
        ],
        'where': filters.length == 1
            ? filters.single
            : {
                'compositeFilter': {'op': 'AND', 'filters': filters},
              },
        'orderBy': [
          {
            'field': {'fieldPath': orderByField},
            'direction': descending ? 'DESCENDING' : 'ASCENDING',
          },
        ],
      },
    });

    final client = _injectedClient ?? http.Client();
    try {
      final response = await client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FirestoreRestDocumentException(
          _errorStatus(response.body),
          'Could not query "$collection" '
          '(HTTP ${response.statusCode}): ${_errorMessage(response.body)}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FirestoreRestDocumentException(
          'unknown',
          'Unexpected Firestore REST runQuery response shape.',
        );
      }
      final results = <Map<String, dynamic>>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        final document = entry['document'];
        if (document is! Map<String, dynamic>) {
          // A heartbeat/progress entry with no `document` — not a match.
          continue;
        }
        final fields = document['fields'];
        results.add(
          fields is Map<String, dynamic> ? _decodeFields(fields) : const {},
        );
      }
      return results;
    } on FirestoreRestDocumentException {
      rethrow;
    } catch (error) {
      throw FirestoreRestDocumentException(
        'unknown',
        'Could not reach "$uri": $error',
      );
    } finally {
      if (_injectedClient == null) client.close();
    }
  }

  /// Firestore's own error body is `{"error":{"code":9,"message":"The
  /// query requires an index...","status":"FAILED_PRECONDITION"}}` (or a
  /// bare array wrapping that same shape for some endpoints) — without
  /// this, every non-2xx response collapsed to "(HTTP 400)" with the one
  /// piece of information (a missing composite index, an auth/claims
  /// problem, a malformed query) that actually explains *why* thrown
  /// away. Falls back to the raw body, truncated, if it isn't JSON at all
  /// — still strictly more informative than nothing.
  Map<String, dynamic>? _errorBody(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      final body =
          decoded is List && decoded.isNotEmpty ? decoded.first : decoded;
      if (body is Map<String, dynamic> && body['error'] is Map) {
        return (body['error'] as Map).cast<String, dynamic>();
      }
    } catch (_) {
      // Not JSON — _errorMessage below falls back to the raw body text.
    }
    return null;
  }

  String _errorStatus(String responseBody) {
    final status = _errorBody(responseBody)?['status'];
    return status is String ? status : 'unknown';
  }

  String _errorMessage(String responseBody) {
    final message = _errorBody(responseBody)?['message'];
    if (message is String) return message;
    return responseBody.length > 500
        ? '${responseBody.substring(0, 500)}…'
        : responseBody;
  }

  Map<String, dynamic> _decodeFields(Map<String, dynamic> fields) {
    return {
      for (final entry in fields.entries)
        entry.key: _decodeValue(entry.value as Map<String, dynamic>),
    };
  }

  dynamic _decodeValue(Map<String, dynamic> value) {
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('integerValue')) {
      return int.tryParse(value['integerValue'] as String);
    }
    if (value.containsKey('doubleValue')) return value['doubleValue'];
    if (value.containsKey('booleanValue')) return value['booleanValue'];
    if (value.containsKey('timestampValue')) {
      return DateTime.tryParse(value['timestampValue'] as String);
    }
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('arrayValue')) {
      final values = (value['arrayValue'] as Map?)?['values'] as List?;
      return values == null
          ? const []
          : [for (final v in values) _decodeValue(v as Map<String, dynamic>)];
    }
    if (value.containsKey('mapValue')) {
      final mapFields = (value['mapValue'] as Map?)?['fields'];
      return mapFields is Map<String, dynamic>
          ? _decodeFields(mapFields)
          : const {};
    }
    return null;
  }
}
