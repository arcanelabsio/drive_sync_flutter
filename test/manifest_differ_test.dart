import 'package:test/test.dart';
import 'package:drive_sync_flutter/drive_sync_flutter.dart';

void main() {
  late ManifestDiffer differ;

  setUp(() {
    differ = ManifestDiffer();
  });

  SyncFileEntry entry(String path, {String sha = 'abc123'}) => SyncFileEntry(
    path: path,
    sha256: sha,
    lastModified: DateTime(2026, 4, 8),
  );

  SyncManifest manifest(List<SyncFileEntry> entries) => SyncManifest(
    files: {for (final e in entries) e.path: e},
    lastSynced: DateTime(2026, 4, 8),
  );

  group('ManifestDiffer', () {
    test('empty vs empty → no changes', () {
      final diff = differ.diff(SyncManifest.empty(), SyncManifest.empty());
      expect(diff.hasChanges, false);
      expect(diff.added, isEmpty);
      expect(diff.modified, isEmpty);
      expect(diff.deleted, isEmpty);
      expect(diff.unchanged, isEmpty);
    });

    test('source has files, target empty → all added', () {
      final source = manifest([
        entry('tracking/2026-04-08.json'),
        entry('tracking/2026-04-09.json'),
      ]);
      final diff = differ.diff(source, SyncManifest.empty());
      expect(diff.added, [
        'tracking/2026-04-08.json',
        'tracking/2026-04-09.json',
      ]);
      expect(diff.modified, isEmpty);
      expect(diff.deleted, isEmpty);
      expect(diff.unchanged, isEmpty);
    });

    test('source empty, target has files → all deleted', () {
      final target = manifest([
        entry('tracking/2026-04-08.json'),
        entry('profile.json'),
      ]);
      final diff = differ.diff(SyncManifest.empty(), target);
      expect(diff.added, isEmpty);
      expect(
        diff.deleted,
        unorderedEquals(['tracking/2026-04-08.json', 'profile.json']),
      );
      expect(diff.modified, isEmpty);
    });

    test('same files same sha → all unchanged', () {
      final a = manifest([
        entry('a.json', sha: 'same'),
        entry('b.json', sha: 'same'),
      ]);
      final b = manifest([
        entry('a.json', sha: 'same'),
        entry('b.json', sha: 'same'),
      ]);
      final diff = differ.diff(a, b);
      expect(diff.hasChanges, false);
      expect(diff.unchanged, unorderedEquals(['a.json', 'b.json']));
    });

    test('same path different sha → modified', () {
      final source = manifest([entry('data.json', sha: 'new_hash')]);
      final target = manifest([entry('data.json', sha: 'old_hash')]);
      final diff = differ.diff(source, target);
      expect(diff.modified, ['data.json']);
      expect(diff.added, isEmpty);
      expect(diff.deleted, isEmpty);
    });

    test('mixed: added + modified + deleted + unchanged', () {
      final source = manifest([
        entry('unchanged.json', sha: 'aaa'),
        entry('modified.json', sha: 'new'),
        entry('added.json', sha: 'bbb'),
      ]);
      final target = manifest([
        entry('unchanged.json', sha: 'aaa'),
        entry('modified.json', sha: 'old'),
        entry('deleted.json', sha: 'ccc'),
      ]);
      final diff = differ.diff(source, target);
      expect(diff.added, ['added.json']);
      expect(diff.modified, ['modified.json']);
      expect(diff.deleted, ['deleted.json']);
      expect(diff.unchanged, ['unchanged.json']);
      expect(diff.totalChanges, 3);
    });

    test('sorted output for deterministic results', () {
      final source = manifest([
        entry('z.json', sha: 'z'),
        entry('a.json', sha: 'a'),
        entry('m.json', sha: 'm'),
      ]);
      final diff = differ.diff(source, SyncManifest.empty());
      expect(diff.added, ['a.json', 'm.json', 'z.json']);
    });
  });
}
