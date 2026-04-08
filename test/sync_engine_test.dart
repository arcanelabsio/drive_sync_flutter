import 'dart:convert';
import 'package:test/test.dart';
import 'package:drive_sync_flutter/drive_sync_flutter.dart';

/// Mock DriveAdapter that operates on an in-memory file map.
class MockDriveAdapter implements DriveAdapter {
  final Map<String, List<int>> files = {};
  final Map<String, DateTime> timestamps = {};

  void seed(String path, String content, {DateTime? modified}) {
    files[path] = utf8.encode(content);
    timestamps[path] = modified ?? DateTime(2026, 4, 8);
  }

  @override
  Future<void> ensureFolder() async {}

  @override
  Future<Map<String, RemoteFileInfo>> listFiles() async {
    return files.map((path, bytes) => MapEntry(
          path,
          RemoteFileInfo(
            path: path,
            lastModified: timestamps[path] ?? DateTime(2026, 4, 8),
            sizeBytes: bytes.length,
          ),
        ));
  }

  @override
  Future<void> uploadFile(String remotePath, List<int> content) async {
    files[remotePath] = content;
    timestamps[remotePath] = DateTime.now();
  }

  @override
  Future<List<int>> downloadFile(String remotePath) async {
    if (!files.containsKey(remotePath)) throw Exception('Not found: $remotePath');
    return files[remotePath]!;
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    files.remove(remotePath);
    timestamps.remove(remotePath);
  }
}

void main() {
  group('SyncEngine — push', () {
    test('uploads new local files to empty remote', () async {
      final adapter = MockDriveAdapter();
      final engine = SyncEngine(adapter: adapter);

      final localManifest = SyncManifest(
        files: {
          'a.json': SyncFileEntry(path: 'a.json', sha256: 'aaa', lastModified: DateTime(2026, 4, 8)),
        },
        lastSynced: DateTime(2026, 4, 7),
      );

      final result = await engine.sync(
        localPath: '/tmp/test',
        localManifest: localManifest,
        direction: SyncDirection.push,
        readLocalFile: (path) async => utf8.encode('{"data":"a"}'),
      );

      expect(result.filesUploaded, 1);
      expect(adapter.files.containsKey('a.json'), true);
    });
  });

  group('SyncEngine — pull', () {
    test('downloads new remote files to local', () async {
      final adapter = MockDriveAdapter();
      adapter.seed('b.json', '{"data":"b"}');

      final engine = SyncEngine(adapter: adapter);
      final writes = <String, List<int>>{};

      final result = await engine.sync(
        localPath: '/tmp/test',
        localManifest: SyncManifest.empty(),
        direction: SyncDirection.pull,
        writeLocalFile: (path, content) async {
          writes[path] = content;
        },
      );

      expect(result.filesDownloaded, 1);
      expect(writes.containsKey('b.json'), true);
    });
  });

  group('SyncEngine — bidirectional', () {
    test('uploads local-only and downloads remote-only', () async {
      final adapter = MockDriveAdapter();
      adapter.seed('remote_only.json', '{"r":1}');

      final engine = SyncEngine(adapter: adapter);
      final writes = <String, List<int>>{};

      final localManifest = SyncManifest(
        files: {
          'local_only.json': SyncFileEntry(
            path: 'local_only.json',
            sha256: 'loc',
            lastModified: DateTime(2026, 4, 8),
          ),
        },
        lastSynced: DateTime(2026, 4, 7),
      );

      final result = await engine.sync(
        localPath: '/tmp/test',
        localManifest: localManifest,
        direction: SyncDirection.bidirectional,
        readLocalFile: (path) async => utf8.encode('{"l":1}'),
        writeLocalFile: (path, content) async {
          writes[path] = content;
        },
      );

      expect(result.filesUploaded, 1);
      expect(result.filesDownloaded, 1);
      expect(adapter.files.containsKey('local_only.json'), true);
      expect(writes.containsKey('remote_only.json'), true);
    });
  });
}
