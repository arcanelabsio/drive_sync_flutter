import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:drive_sync_flutter/drive_sync_flutter.dart';

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

  group('DriveScope enum', () {
    test('exposes three modes', () {
      expect(DriveScope.values, hasLength(3));
      expect(DriveScope.values, contains(DriveScope.fullDrive));
      expect(DriveScope.values, contains(DriveScope.driveFile));
      expect(DriveScope.values, contains(DriveScope.appData));
    });
  });

  group('GoogleDriveAdapter.userDrive', () {
    test('declares fullDrive scope', () {
      final adapter = GoogleDriveAdapter.userDrive(
        httpClient: mockClient,
        basePath: 'MyApp',
      );
      expect(adapter.scope, DriveScope.fullDrive);
    });

    test('accepts single-segment basePath', () {
      final adapter = GoogleDriveAdapter.userDrive(
        httpClient: mockClient,
        basePath: 'MyApp',
      );
      expect(adapter.folderPath, 'MyApp');
    });

    test('accepts multi-segment basePath', () {
      final adapter = GoogleDriveAdapter.userDrive(
        httpClient: mockClient,
        basePath: 'Longeviti/data',
      );
      expect(adapter.folderPath, 'Longeviti/data');
    });

    test('accepts .app/ style basePath (longeviti-compatible)', () {
      final adapter = GoogleDriveAdapter.userDrive(
        httpClient: mockClient,
        basePath: '.app/longeviti',
      );
      expect(adapter.folderPath, '.app/longeviti');
    });

    test('joins basePath and subPath', () {
      final adapter = GoogleDriveAdapter.userDrive(
        httpClient: mockClient,
        basePath: '.app/longeviti',
        subPath: 'plans',
      );
      expect(adapter.folderPath, '.app/longeviti/plans');
    });

    test('accepts uppercase segments in basePath (unlike appName)', () {
      final adapter = GoogleDriveAdapter.userDrive(
        httpClient: mockClient,
        basePath: 'MyCompany/MyApp',
      );
      expect(adapter.folderPath, 'MyCompany/MyApp');
    });

    test('accepts segments with spaces', () {
      final adapter = GoogleDriveAdapter.userDrive(
        httpClient: mockClient,
        basePath: 'My App',
        subPath: 'Weekly Plans',
      );
      expect(adapter.folderPath, 'My App/Weekly Plans');
    });

    test('rejects empty basePath', () {
      expect(
        () =>
            GoogleDriveAdapter.userDrive(httpClient: mockClient, basePath: ''),
        throwsArgumentError,
      );
    });

    test('rejects basePath with path traversal', () {
      expect(
        () => GoogleDriveAdapter.userDrive(
          httpClient: mockClient,
          basePath: '../hack',
        ),
        throwsArgumentError,
      );
      expect(
        () => GoogleDriveAdapter.userDrive(
          httpClient: mockClient,
          basePath: 'a/../b',
        ),
        throwsArgumentError,
      );
    });

    test('rejects absolute basePath', () {
      expect(
        () => GoogleDriveAdapter.userDrive(
          httpClient: mockClient,
          basePath: '/absolute',
        ),
        throwsArgumentError,
      );
    });

    test('rejects basePath with double slashes', () {
      expect(
        () => GoogleDriveAdapter.userDrive(
          httpClient: mockClient,
          basePath: 'a//b',
        ),
        throwsArgumentError,
      );
    });

    test('rejects basePath with trailing slash', () {
      expect(
        () => GoogleDriveAdapter.userDrive(
          httpClient: mockClient,
          basePath: 'MyApp/',
        ),
        throwsArgumentError,
      );
    });

    test('rejects subPath with traversal', () {
      expect(
        () => GoogleDriveAdapter.userDrive(
          httpClient: mockClient,
          basePath: 'MyApp',
          subPath: '../escape',
        ),
        throwsArgumentError,
      );
    });
  });

  group('GoogleDriveAdapter.appFiles', () {
    test('declares driveFile scope', () {
      final adapter = GoogleDriveAdapter.appFiles(
        httpClient: mockClient,
        folderName: 'MyApp',
      );
      expect(adapter.scope, DriveScope.driveFile);
    });

    test('accepts simple folder name', () {
      final adapter = GoogleDriveAdapter.appFiles(
        httpClient: mockClient,
        folderName: 'MyApp',
      );
      expect(adapter.folderPath, 'MyApp');
    });

    test('accepts folderName with subPath', () {
      final adapter = GoogleDriveAdapter.appFiles(
        httpClient: mockClient,
        folderName: 'MyApp',
        subPath: 'Backups',
      );
      expect(adapter.folderPath, 'MyApp/Backups');
    });

    test('accepts nested subPath', () {
      final adapter = GoogleDriveAdapter.appFiles(
        httpClient: mockClient,
        folderName: 'MyApp',
        subPath: 'data/2026',
      );
      expect(adapter.folderPath, 'MyApp/data/2026');
    });

    test('rejects empty folderName', () {
      expect(
        () =>
            GoogleDriveAdapter.appFiles(httpClient: mockClient, folderName: ''),
        throwsArgumentError,
      );
    });

    test('rejects folderName with slashes (must use subPath)', () {
      expect(
        () => GoogleDriveAdapter.appFiles(
          httpClient: mockClient,
          folderName: 'MyApp/Sub',
        ),
        throwsArgumentError,
      );
    });

    test('rejects folderName of "." or ".."', () {
      expect(
        () => GoogleDriveAdapter.appFiles(
          httpClient: mockClient,
          folderName: '.',
        ),
        throwsArgumentError,
      );
      expect(
        () => GoogleDriveAdapter.appFiles(
          httpClient: mockClient,
          folderName: '..',
        ),
        throwsArgumentError,
      );
    });

    test('rejects subPath with traversal', () {
      expect(
        () => GoogleDriveAdapter.appFiles(
          httpClient: mockClient,
          folderName: 'MyApp',
          subPath: '../hack',
        ),
        throwsArgumentError,
      );
    });
  });

  group('GoogleDriveAdapter.appData', () {
    test('declares appData scope', () {
      final adapter = GoogleDriveAdapter.appData(httpClient: mockClient);
      expect(adapter.scope, DriveScope.appData);
    });

    test('has empty folderPath when no subPath (appDataFolder root)', () {
      final adapter = GoogleDriveAdapter.appData(httpClient: mockClient);
      expect(adapter.folderPath, '');
    });

    test('accepts subPath for nesting within appDataFolder', () {
      final adapter = GoogleDriveAdapter.appData(
        httpClient: mockClient,
        subPath: 'cache',
      );
      expect(adapter.folderPath, 'cache');
    });

    test('accepts nested subPath', () {
      final adapter = GoogleDriveAdapter.appData(
        httpClient: mockClient,
        subPath: 'state/v2',
      );
      expect(adapter.folderPath, 'state/v2');
    });

    test('rejects subPath with traversal', () {
      expect(
        () => GoogleDriveAdapter.appData(
          httpClient: mockClient,
          subPath: '../escape',
        ),
        throwsArgumentError,
      );
    });

    test('rejects absolute subPath', () {
      expect(
        () =>
            GoogleDriveAdapter.appData(httpClient: mockClient, subPath: '/abs'),
        throwsArgumentError,
      );
    });
  });

  group('Backward compatibility — legacy constructors', () {
    test('.sandboxed() still works, declares fullDrive scope', () {
      // ignore: deprecated_member_use_from_same_package
      final adapter = GoogleDriveAdapter.sandboxed(
        httpClient: mockClient,
        appName: 'longeviti',
      );
      expect(adapter.scope, DriveScope.fullDrive);
      expect(adapter.folderPath, '.app/longeviti');
    });

    test('.sandboxed() with subPath preserves pre-1.2 behavior', () {
      // ignore: deprecated_member_use_from_same_package
      final adapter = GoogleDriveAdapter.sandboxed(
        httpClient: mockClient,
        appName: 'my_app',
        subPath: 'Plans',
      );
      expect(adapter.folderPath, '.app/my_app/Plans');
    });

    test('.sandboxed() still validates appName rules', () {
      expect(
        // ignore: deprecated_member_use_from_same_package
        () => GoogleDriveAdapter.sandboxed(
          httpClient: mockClient,
          appName: 'BadName',
        ),
        throwsArgumentError,
      );
    });

    test('.withPath() legacy constructor still works', () {
      // ignore: deprecated_member_use_from_same_package
      final adapter = GoogleDriveAdapter.withPath(
        httpClient: mockClient,
        folderPath: 'legacy/path',
      );
      expect(adapter.scope, DriveScope.fullDrive);
      expect(adapter.folderPath, 'legacy/path');
    });

    test('default constructor legacy still works', () {
      // ignore: deprecated_member_use_from_same_package
      final adapter = GoogleDriveAdapter(
        httpClient: mockClient,
        folderName: 'MyFolder',
      );
      expect(adapter.scope, DriveScope.fullDrive);
      expect(adapter.folderPath, 'MyFolder');
    });
  });

  group('SandboxValidator.validateBasePath', () {
    test('accepts simple names', () {
      expect(() => SandboxValidator.validateBasePath('MyApp'), returnsNormally);
      expect(() => SandboxValidator.validateBasePath('app'), returnsNormally);
    });

    test('accepts dotfile prefix', () {
      expect(
        () => SandboxValidator.validateBasePath('.app/longeviti'),
        returnsNormally,
      );
    });

    test('accepts mixed case and spaces', () {
      expect(
        () => SandboxValidator.validateBasePath('My Company/My App'),
        returnsNormally,
      );
    });

    test('rejects empty', () {
      expect(() => SandboxValidator.validateBasePath(''), throwsArgumentError);
    });

    test('rejects traversal', () {
      expect(
        () => SandboxValidator.validateBasePath('../hack'),
        throwsArgumentError,
      );
      expect(
        () => SandboxValidator.validateBasePath('a/..'),
        throwsArgumentError,
      );
    });

    test('rejects absolute', () {
      expect(
        () => SandboxValidator.validateBasePath('/abs'),
        throwsArgumentError,
      );
    });

    test('rejects trailing slash', () {
      expect(
        () => SandboxValidator.validateBasePath('path/'),
        throwsArgumentError,
      );
    });
  });

  group('SandboxValidator.validateFolderName', () {
    test('accepts simple names', () {
      expect(
        () => SandboxValidator.validateFolderName('MyApp'),
        returnsNormally,
      );
      expect(
        () => SandboxValidator.validateFolderName('Backups 2026'),
        returnsNormally,
      );
    });

    test('rejects empty, slashes, dot segments', () {
      expect(
        () => SandboxValidator.validateFolderName(''),
        throwsArgumentError,
      );
      expect(
        () => SandboxValidator.validateFolderName('a/b'),
        throwsArgumentError,
      );
      expect(
        () => SandboxValidator.validateFolderName('..'),
        throwsArgumentError,
      );
      expect(
        () => SandboxValidator.validateFolderName('.'),
        throwsArgumentError,
      );
    });
  });

  group('SandboxValidator.joinBasePath', () {
    test('joins base and subPath', () {
      expect(
        SandboxValidator.joinBasePath('MyApp', 'Backups'),
        'MyApp/Backups',
      );
    });

    test('returns base unchanged when subPath null/empty', () {
      expect(SandboxValidator.joinBasePath('MyApp', null), 'MyApp');
      expect(SandboxValidator.joinBasePath('MyApp', ''), 'MyApp');
    });

    test('validates both components', () {
      expect(
        () => SandboxValidator.joinBasePath('', 'sub'),
        throwsArgumentError,
      );
      expect(
        () => SandboxValidator.joinBasePath('MyApp', '../hack'),
        throwsArgumentError,
      );
    });
  });
}
