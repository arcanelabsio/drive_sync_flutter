import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:drive_sync_flutter/drive_sync_flutter.dart';

/// Minimal mock HTTP client — constructor validation doesn't make HTTP calls.
class _NoOpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError('Should not be called in validation tests');
  }
}

void main() {
  late http.Client mockClient;

  setUp(() {
    mockClient = _NoOpClient();
  });

  group('GoogleDriveAdapter.sandboxed — constructor validation', () {
    test('succeeds with valid appName and subPath', () {
      final adapter = GoogleDriveAdapter.sandboxed(
        httpClient: mockClient,
        appName: 'longeviti',
        subPath: 'Plans',
      );
      expect(adapter.folderPath, '.app/longeviti/Plans');
    });

    test('succeeds with valid appName and no subPath', () {
      final adapter = GoogleDriveAdapter.sandboxed(
        httpClient: mockClient,
        appName: 'my_app',
      );
      expect(adapter.folderPath, '.app/my_app');
    });

    test('succeeds with nested subPath', () {
      final adapter = GoogleDriveAdapter.sandboxed(
        httpClient: mockClient,
        appName: 'my_app',
        subPath: 'deep/nested/path',
      );
      expect(adapter.folderPath, '.app/my_app/deep/nested/path');
    });

    test('succeeds with spaces in subPath', () {
      final adapter = GoogleDriveAdapter.sandboxed(
        httpClient: mockClient,
        appName: 'longeviti',
        subPath: 'Longevity Plans',
      );
      expect(adapter.folderPath, '.app/longeviti/Longevity Plans');
    });

    test('rejects empty appName', () {
      expect(
        () => GoogleDriveAdapter.sandboxed(httpClient: mockClient, appName: ''),
        throwsArgumentError,
      );
    });

    test('rejects uppercase appName', () {
      expect(
        () => GoogleDriveAdapter.sandboxed(httpClient: mockClient, appName: 'MyApp'),
        throwsArgumentError,
      );
    });

    test('rejects appName with path traversal', () {
      expect(
        () => GoogleDriveAdapter.sandboxed(httpClient: mockClient, appName: '../traversal'),
        throwsArgumentError,
      );
    });

    test('rejects appName with slashes', () {
      expect(
        () => GoogleDriveAdapter.sandboxed(httpClient: mockClient, appName: 'app/hack'),
        throwsArgumentError,
      );
    });

    test('rejects appName with hyphens', () {
      expect(
        () => GoogleDriveAdapter.sandboxed(httpClient: mockClient, appName: 'my-app'),
        throwsArgumentError,
      );
    });

    test('rejects appName starting with digit', () {
      expect(
        () => GoogleDriveAdapter.sandboxed(httpClient: mockClient, appName: '123app'),
        throwsArgumentError,
      );
    });

    test('rejects subPath with traversal', () {
      expect(
        () => GoogleDriveAdapter.sandboxed(
          httpClient: mockClient,
          appName: 'valid_app',
          subPath: '../../escape',
        ),
        throwsArgumentError,
      );
    });

    test('rejects subPath with absolute path', () {
      expect(
        () => GoogleDriveAdapter.sandboxed(
          httpClient: mockClient,
          appName: 'valid_app',
          subPath: '/root',
        ),
        throwsArgumentError,
      );
    });

    test('rejects subPath with empty segments', () {
      expect(
        () => GoogleDriveAdapter.sandboxed(
          httpClient: mockClient,
          appName: 'valid_app',
          subPath: 'a//b',
        ),
        throwsArgumentError,
      );
    });
  });

  group('GoogleDriveAdapter.sandboxed — folder path enforcement', () {
    test('folderPath always starts with .app/', () {
      final adapter = GoogleDriveAdapter.sandboxed(
        httpClient: mockClient,
        appName: 'test_app',
        subPath: 'data',
      );
      expect(adapter.folderPath, startsWith('.app/'));
    });

    test('folderPath contains appName as second segment', () {
      final adapter = GoogleDriveAdapter.sandboxed(
        httpClient: mockClient,
        appName: 'test_app',
        subPath: 'data',
      );
      final segments = adapter.folderPath.split('/');
      expect(segments[0], '.app');
      expect(segments[1], 'test_app');
      expect(segments[2], 'data');
    });

    test('cannot escape .app prefix via appName', () {
      // All traversal attempts in appName are caught by validation
      for (final attack in ['..', '../..', 'a/..', '.', '../root']) {
        expect(
          () => GoogleDriveAdapter.sandboxed(httpClient: mockClient, appName: attack),
          throwsArgumentError,
          reason: 'appName "$attack" should be rejected',
        );
      }
    });

    test('cannot escape sandbox via subPath', () {
      for (final attack in ['..', '../..', 'a/../..', '../../etc', '/root']) {
        expect(
          () => GoogleDriveAdapter.sandboxed(
            httpClient: mockClient,
            appName: 'safe_app',
            subPath: attack,
          ),
          throwsArgumentError,
          reason: 'subPath "$attack" should be rejected',
        );
      }
    });
  });

  group('Query injection prevention', () {
    test('escapeDriveQuery handles malicious folder names', () {
      final injected = "test' or 1=1 or name='hack";
      final escaped = SandboxValidator.escapeDriveQuery(injected);
      expect(escaped, "test\\' or 1=1 or name=\\'hack");
      // When used in query: name = 'test\' or 1=1 or name=\'hack'
      // This is now a literal string match, not an injection
    });

    test('escapeDriveQuery handles nested quotes', () {
      final nested = "it's a 'test'";
      final escaped = SandboxValidator.escapeDriveQuery(nested);
      expect(escaped, "it\\'s a \\'test\\'");
    });
  });
}
