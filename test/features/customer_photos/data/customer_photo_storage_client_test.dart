import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_storage_client.dart';

void main() {
  group('buildUploadFailureLogContext', () {
    test('extracts every FirebaseException field for a FirebaseException', () {
      final error = FirebaseException(
        plugin: 'firebase_storage',
        code: 'unauthorized',
        message: 'User is not authorized to perform the desired action.',
      );

      final context = buildUploadFailureLogContext(
        error: error,
        objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/p1',
        contentType: 'image/jpeg',
        byteLength: 123456,
        storageEmulatorActive: true,
      );

      expect(context['exceptionType'], 'FirebaseException');
      expect(context['firebaseExceptionPlugin'], 'firebase_storage');
      expect(context['firebaseExceptionCode'], 'unauthorized');
      expect(
        context['firebaseExceptionMessage'],
        'User is not authorized to perform the desired action.',
      );
      expect(
        context['objectPath'],
        'tenants/org-1/customerPhotos/customer-uid-1/p1',
      );
      expect(context['contentType'], 'image/jpeg');
      expect(context['byteLength'], 123456);
      expect(context['storageEmulatorActive'], true);
    });

    test(
        'still populates the non-Firebase fields — with null '
        'FirebaseException fields — for a non-FirebaseException error, '
        'e.g. a raw connection failure from a missing adb reverse binding', () {
      final context = buildUploadFailureLogContext(
        error: Exception('Connection refused'),
        objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/p2',
        contentType: 'image/png',
        byteLength: 42,
        storageEmulatorActive: true,
      );

      expect(context['exceptionType'], '_Exception');
      expect(context['firebaseExceptionPlugin'], isNull);
      expect(context['firebaseExceptionCode'], isNull);
      expect(context['firebaseExceptionMessage'], isNull);
      expect(
        context['objectPath'],
        'tenants/org-1/customerPhotos/customer-uid-1/p2',
      );
      expect(context['contentType'], 'image/png');
      expect(context['byteLength'], 42);
      expect(context['storageEmulatorActive'], true);
    });

    test('reflects storageEmulatorActive: false when passed', () {
      final context = buildUploadFailureLogContext(
        error: Exception('boom'),
        objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/p3',
        contentType: 'image/jpeg',
        byteLength: 1,
        storageEmulatorActive: false,
      );

      expect(context['storageEmulatorActive'], false);
    });

    test(
        'never emits an auth/App Check token, an upload-grant secret, or '
        'raw image bytes — only the opaque objectPath and a byte count', () {
      final context = buildUploadFailureLogContext(
        error: Exception('boom'),
        objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/p4',
        contentType: 'image/jpeg',
        byteLength: 999,
        storageEmulatorActive: true,
      );

      expect(context.keys, hasLength(8));
      expect(
        context.keys,
        containsAll(<String>[
          'exceptionType',
          'firebaseExceptionPlugin',
          'firebaseExceptionCode',
          'firebaseExceptionMessage',
          'objectPath',
          'contentType',
          'byteLength',
          'storageEmulatorActive',
        ]),
      );
      // byteLength is a count (an int), never the actual byte content.
      expect(context['byteLength'], isA<int>());
    });
  });
}
