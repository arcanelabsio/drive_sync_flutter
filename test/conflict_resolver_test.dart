import 'package:test/test.dart';
import 'package:drive_sync_flutter/drive_sync_flutter.dart';

void main() {
  SyncConflict _conflict({
    required DateTime localTime,
    required DateTime remoteTime,
  }) =>
      SyncConflict(
        path: 'data.json',
        local: SyncFileEntry(
          path: 'data.json',
          sha256: 'local_hash',
          lastModified: localTime,
        ),
        remote: SyncFileEntry(
          path: 'data.json',
          sha256: 'remote_hash',
          lastModified: remoteTime,
        ),
      );

  group('ConflictResolver — newerWins', () {
    late ConflictResolver resolver;
    setUp(() => resolver = const ConflictResolver(strategy: ConflictStrategy.newerWins));

    test('local is newer → useLocal', () {
      final c = _conflict(
        localTime: DateTime(2026, 4, 8, 12, 0),
        remoteTime: DateTime(2026, 4, 8, 10, 0),
      );
      expect(resolver.resolve(c), SyncConflictResolution.useLocal);
    });

    test('remote is newer → useRemote', () {
      final c = _conflict(
        localTime: DateTime(2026, 4, 8, 10, 0),
        remoteTime: DateTime(2026, 4, 8, 12, 0),
      );
      expect(resolver.resolve(c), SyncConflictResolution.useRemote);
    });

    test('same timestamp → useLocal (tie-break)', () {
      final t = DateTime(2026, 4, 8, 12, 0);
      final c = _conflict(localTime: t, remoteTime: t);
      expect(resolver.resolve(c), SyncConflictResolution.useLocal);
    });
  });

  group('ConflictResolver — localWins', () {
    late ConflictResolver resolver;
    setUp(() => resolver = const ConflictResolver(strategy: ConflictStrategy.localWins));

    test('always returns useLocal regardless of timestamps', () {
      final c = _conflict(
        localTime: DateTime(2026, 1, 1),
        remoteTime: DateTime(2026, 12, 31),
      );
      expect(resolver.resolve(c), SyncConflictResolution.useLocal);
    });
  });

  group('ConflictResolver — remoteWins', () {
    late ConflictResolver resolver;
    setUp(() => resolver = const ConflictResolver(strategy: ConflictStrategy.remoteWins));

    test('always returns useRemote regardless of timestamps', () {
      final c = _conflict(
        localTime: DateTime(2026, 12, 31),
        remoteTime: DateTime(2026, 1, 1),
      );
      expect(resolver.resolve(c), SyncConflictResolution.useRemote);
    });
  });

  group('ConflictResolver — askUser', () {
    late ConflictResolver resolver;
    setUp(() => resolver = const ConflictResolver(strategy: ConflictStrategy.askUser));

    test('returns skip (unresolved, app must handle)', () {
      final c = _conflict(
        localTime: DateTime(2026, 4, 8),
        remoteTime: DateTime(2026, 4, 9),
      );
      expect(resolver.resolve(c), SyncConflictResolution.skip);
    });
  });

  group('ConflictResolver — resolveAll', () {
    test('resolves multiple conflicts with newerWins', () {
      final resolver = const ConflictResolver(strategy: ConflictStrategy.newerWins);
      final conflicts = [
        _conflict(localTime: DateTime(2026, 4, 10), remoteTime: DateTime(2026, 4, 8)),
        _conflict(localTime: DateTime(2026, 4, 5), remoteTime: DateTime(2026, 4, 9)),
      ];
      final resolved = resolver.resolveAll(conflicts);
      expect(resolved[0].resolution, SyncConflictResolution.useLocal);
      expect(resolved[1].resolution, SyncConflictResolution.useRemote);
    });
  });
}
