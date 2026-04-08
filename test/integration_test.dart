import 'dart:convert';
import 'package:test/test.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:drive_sync_flutter/drive_sync_flutter.dart';

/// In-memory mock that simulates both local and remote storage,
/// so we can test the full sync flow end-to-end.
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
  Future<Map<String, RemoteFileInfo>> listFiles() async =>
      files.map((path, bytes) => MapEntry(
            path,
            RemoteFileInfo(
              path: path,
              lastModified: timestamps[path] ?? DateTime(2026, 4, 8),
              sizeBytes: bytes.length,
            ),
          ));

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

/// Simulates local storage for integration tests.
class LocalStore {
  final Map<String, List<int>> files = {};
  final Map<String, DateTime> timestamps = {};

  void write(String path, String content, {DateTime? modified}) {
    files[path] = utf8.encode(content);
    timestamps[path] = modified ?? DateTime(2026, 4, 8);
  }

  String? read(String path) {
    final bytes = files[path];
    return bytes != null ? utf8.decode(bytes) : null;
  }

  SyncManifest toManifest() {
    final entries = <String, SyncFileEntry>{};
    for (final path in files.keys) {
      entries[path] = SyncFileEntry(
        path: path,
        sha256: crypto.sha256.convert(files[path]!).toString(),
        lastModified: timestamps[path] ?? DateTime(2026, 4, 8),
      );
    }
    return SyncManifest(files: entries, lastSynced: DateTime(2026, 4, 7));
  }

  // Intentionally removed _simpleHash — use crypto.sha256 to match the engine
}

void main() {
  group('Full sync flow: differ → resolver → engine', () {
    test('first sync: local has data, remote is empty → push uploads all', () async {
      final remote = MockDriveAdapter();
      final local = LocalStore();
      local.write('tracking/2026-04-08.json', '{"date":"2026-04-08","weight":130}');
      local.write('tracking/2026-04-09.json', '{"date":"2026-04-09","weight":129}');
      local.write('profile.json', '{"name":"Ajit"}');

      final engine = SyncEngine(adapter: remote);
      final result = await engine.sync(
        localPath: '/data',
        localManifest: local.toManifest(),
        direction: SyncDirection.push,
        readLocalFile: (path) async => local.files[path]!,
      );

      expect(result.filesUploaded, 3);
      expect(result.errors, isEmpty);
      expect(remote.files.length, 3);
      expect(utf8.decode(remote.files['profile.json']!), '{"name":"Ajit"}');
    });

    test('first sync: remote has plans, local is empty → pull downloads all', () async {
      final remote = MockDriveAdapter();
      remote.seed('plans/week01.json', '{"week":1}');
      remote.seed('plans/week02.json', '{"week":2}');
      remote.seed('rules.json', '{"phase":1}');

      final local = LocalStore();
      final engine = SyncEngine(adapter: remote);

      final result = await engine.sync(
        localPath: '/data',
        localManifest: local.toManifest(),
        direction: SyncDirection.pull,
        writeLocalFile: (path, content) async => local.files[path] = content,
      );

      expect(result.filesDownloaded, 3);
      expect(local.read('plans/week01.json'), '{"week":1}');
      expect(local.read('rules.json'), '{"phase":1}');
    });

    test('bidirectional: local tracking + remote plans sync without conflict', () async {
      final remote = MockDriveAdapter();
      remote.seed('plans/week01.json', '{"week":1}');

      final local = LocalStore();
      local.write('tracking/2026-04-08.json', '{"date":"2026-04-08"}');

      final engine = SyncEngine(adapter: remote);

      final result = await engine.sync(
        localPath: '/data',
        localManifest: local.toManifest(),
        direction: SyncDirection.bidirectional,
        readLocalFile: (path) async => local.files[path]!,
        writeLocalFile: (path, content) async => local.files[path] = content,
      );

      // Local tracking pushed to remote
      expect(result.filesUploaded, 1);
      expect(remote.files.containsKey('tracking/2026-04-08.json'), true);
      // Remote plans pulled to local
      expect(result.filesDownloaded, 1);
      expect(local.read('plans/week01.json'), '{"week":1}');
    });

    test('conflict: same file modified on both sides → newerWins resolves', () async {
      final remote = MockDriveAdapter();
      remote.seed('shared.json', '{"v":"remote"}',
          modified: DateTime(2026, 4, 9, 14, 0)); // newer

      final local = LocalStore();
      local.write('shared.json', '{"v":"local"}',
          modified: DateTime(2026, 4, 9, 10, 0)); // older

      final engine = SyncEngine(
        adapter: remote,
        resolver: const ConflictResolver(strategy: ConflictStrategy.newerWins),
      );

      final result = await engine.sync(
        localPath: '/data',
        localManifest: local.toManifest(),
        direction: SyncDirection.bidirectional,
        readLocalFile: (path) async => local.files[path]!,
        writeLocalFile: (path, content) async => local.files[path] = content,
      );

      // Remote was newer, so local should be overwritten
      expect(local.read('shared.json'), '{"v":"remote"}');
      expect(result.filesDownloaded, 1);
    });

    test('conflict: same file modified on both sides → localWins keeps local', () async {
      final remote = MockDriveAdapter();
      remote.seed('shared.json', '{"v":"remote"}',
          modified: DateTime(2026, 4, 9, 14, 0)); // newer but doesn't matter

      final local = LocalStore();
      local.write('shared.json', '{"v":"local"}',
          modified: DateTime(2026, 4, 9, 10, 0)); // older but local wins

      final engine = SyncEngine(
        adapter: remote,
        resolver: const ConflictResolver(strategy: ConflictStrategy.localWins),
      );

      final result = await engine.sync(
        localPath: '/data',
        localManifest: local.toManifest(),
        direction: SyncDirection.bidirectional,
        readLocalFile: (path) async => local.files[path]!,
        writeLocalFile: (path, content) async => local.files[path] = content,
      );

      // Local wins: local stays as-is, remote gets overwritten
      expect(local.read('shared.json'), '{"v":"local"}');
      expect(result.filesUploaded, 1);
      expect(utf8.decode(remote.files['shared.json']!), '{"v":"local"}');
    });

    test('re-sync after no changes → no transfers', () async {
      final remote = MockDriveAdapter();
      remote.seed('data.json', '{"x":1}');

      final local = LocalStore();
      local.files['data.json'] = remote.files['data.json']!;
      local.timestamps['data.json'] = DateTime(2026, 4, 8);

      final engine = SyncEngine(adapter: remote);
      final result = await engine.sync(
        localPath: '/data',
        localManifest: local.toManifest(),
        direction: SyncDirection.bidirectional,
        readLocalFile: (path) async => local.files[path]!,
        writeLocalFile: (path, content) async => local.files[path] = content,
      );

      expect(result.filesUploaded, 0);
      expect(result.filesDownloaded, 0);
    });

    test('partial failure: one upload fails, others succeed', () async {
      final remote = _FailingAdapter(failOn: 'bad.json');
      final local = LocalStore();
      local.write('good.json', '{"ok":true}');
      local.write('bad.json', '{"ok":false}');

      final engine = SyncEngine(adapter: remote);
      final result = await engine.sync(
        localPath: '/data',
        localManifest: local.toManifest(),
        direction: SyncDirection.push,
        readLocalFile: (path) async => local.files[path]!,
      );

      expect(result.filesUploaded, 1); // good.json succeeded
      expect(result.errors.length, 1); // bad.json failed
      expect(result.errors.first, contains('bad.json'));
    });

    test('incremental sync: only changed files transfer', () async {
      final remote = MockDriveAdapter();
      remote.seed('unchanged.json', '{"v":1}');
      remote.seed('updated_remote.json', '{"v":"old"}',
          modified: DateTime(2026, 4, 7));

      final local = LocalStore();
      // unchanged.json has same content as remote
      local.files['unchanged.json'] = remote.files['unchanged.json']!;
      local.timestamps['unchanged.json'] = DateTime(2026, 4, 8);
      // new_local.json is local-only
      local.write('new_local.json', '{"v":"new"}');

      final engine = SyncEngine(adapter: remote);
      final result = await engine.sync(
        localPath: '/data',
        localManifest: local.toManifest(),
        direction: SyncDirection.bidirectional,
        readLocalFile: (path) async => local.files[path]!,
        writeLocalFile: (path, content) async => local.files[path] = content,
      );

      // new_local.json pushed, updated_remote.json pulled, unchanged.json skipped
      expect(result.filesUploaded, 1);
      expect(result.filesDownloaded, 1);
      expect(remote.files.containsKey('new_local.json'), true);
      expect(local.files.containsKey('updated_remote.json'), true);
    });

    test('manifest differ feeds directly into engine with correct semantics', () {
      // Verify the contract: differ output fields map correctly to engine actions
      final differ = ManifestDiffer();
      final local = SyncManifest(
        files: {
          'push_me.json': SyncFileEntry(path: 'push_me.json', sha256: 'a', lastModified: DateTime(2026, 4, 8)),
          'conflict.json': SyncFileEntry(path: 'conflict.json', sha256: 'local_v', lastModified: DateTime(2026, 4, 8)),
        },
        lastSynced: DateTime(2026, 4, 7),
      );
      final remoteManifest = SyncManifest(
        files: {
          'pull_me.json': SyncFileEntry(path: 'pull_me.json', sha256: 'b', lastModified: DateTime(2026, 4, 8)),
          'conflict.json': SyncFileEntry(path: 'conflict.json', sha256: 'remote_v', lastModified: DateTime(2026, 4, 9)),
        },
        lastSynced: DateTime(2026, 4, 7),
      );

      // local → remote diff: what local has that remote doesn't
      final pushDiff = differ.diff(local, remoteManifest);
      expect(pushDiff.added, ['push_me.json']); // engine should upload
      expect(pushDiff.modified, ['conflict.json']); // engine should handle conflict

      // remote → local diff: what remote has that local doesn't
      final pullDiff = differ.diff(remoteManifest, local);
      expect(pullDiff.added, ['pull_me.json']); // engine should download
      expect(pullDiff.modified, ['conflict.json']); // same conflict from other side
    });

    test('resolver output feeds correctly into engine file operations', () {
      final resolver = const ConflictResolver(strategy: ConflictStrategy.newerWins);

      // Simulate: local is older, remote is newer
      final conflict = SyncConflict(
        path: 'tracking.json',
        local: SyncFileEntry(path: 'tracking.json', sha256: 'old', lastModified: DateTime(2026, 4, 8)),
        remote: SyncFileEntry(path: 'tracking.json', sha256: 'new', lastModified: DateTime(2026, 4, 9)),
      );

      final resolution = resolver.resolve(conflict);
      expect(resolution, SyncConflictResolution.useRemote);
      // Engine contract: useRemote → download remote to local, do NOT upload local
      // useLocal → upload local to remote, do NOT download
      // skip → do nothing (askUser mode, app handles)
    });
  });

  group('Edge cases across components', () {
    test('empty file syncs correctly (0 bytes)', () async {
      final remote = MockDriveAdapter();
      final local = LocalStore();
      local.write('empty.json', '');

      final engine = SyncEngine(adapter: remote);
      final result = await engine.sync(
        localPath: '/data',
        localManifest: local.toManifest(),
        direction: SyncDirection.push,
        readLocalFile: (path) async => local.files[path]!,
      );

      expect(result.filesUploaded, 1);
      expect(remote.files['empty.json'], isEmpty);
    });

    test('files with same content but different paths are independent', () async {
      final remote = MockDriveAdapter();
      final local = LocalStore();
      local.write('a/data.json', '{"same":"content"}');
      local.write('b/data.json', '{"same":"content"}');

      final engine = SyncEngine(adapter: remote);
      final result = await engine.sync(
        localPath: '/data',
        localManifest: local.toManifest(),
        direction: SyncDirection.push,
        readLocalFile: (path) async => local.files[path]!,
      );

      expect(result.filesUploaded, 2);
      expect(remote.files.length, 2);
    });

    test('unicode content (Telugu/Hindi food names) roundtrips correctly', () async {
      final remote = MockDriveAdapter();
      final local = LocalStore();
      final content = '{"name":"కందిపప్పు","hindi":"तूर दाल","cal":322}';
      local.write('food.json', content);

      final engine = SyncEngine(adapter: remote);
      await engine.sync(
        localPath: '/data',
        localManifest: local.toManifest(),
        direction: SyncDirection.push,
        readLocalFile: (path) async => local.files[path]!,
      );

      // Pull it back
      local.files.clear();
      final pullResult = await engine.sync(
        localPath: '/data',
        localManifest: SyncManifest.empty(),
        direction: SyncDirection.pull,
        writeLocalFile: (path, bytes) async => local.files[path] = bytes,
      );

      expect(pullResult.filesDownloaded, 1);
      expect(local.read('food.json'), content);
    });
  });
}

/// Adapter that fails on a specific file, succeeds on others.
class _FailingAdapter implements DriveAdapter {
  final String failOn;
  final Map<String, List<int>> files = {};

  _FailingAdapter({required this.failOn});

  @override
  Future<void> ensureFolder() async {}

  @override
  Future<Map<String, RemoteFileInfo>> listFiles() async =>
      files.map((k, v) => MapEntry(k, RemoteFileInfo(path: k, lastModified: DateTime(2026, 4, 8))));

  @override
  Future<void> uploadFile(String path, List<int> content) async {
    if (path == failOn) throw Exception('Simulated upload failure on $path');
    files[path] = content;
  }

  @override
  Future<List<int>> downloadFile(String path) async {
    if (path == failOn) throw Exception('Simulated download failure on $path');
    return files[path]!;
  }

  @override
  Future<void> deleteFile(String path) async => files.remove(path);
}
