import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;

import 'models.dart';
import 'drive_adapter.dart';
import 'sync_engine.dart';
import 'conflict_resolver.dart';
import 'manifest_differ.dart';

/// High-level client for syncing a local directory with Google Drive.
///
/// ```dart
/// final client = DriveSyncClient(adapter: myAdapter);
/// final result = await client.sync(localPath: '/data/tracking');
/// ```
class DriveSyncClient {
  final DriveAdapter adapter;
  final ConflictStrategy defaultStrategy;
  late final SyncEngine _engine;

  DriveSyncClient({
    required this.adapter,
    this.defaultStrategy = ConflictStrategy.newerWins,
  }) {
    _engine = SyncEngine(
      adapter: adapter,
      resolver: ConflictResolver(strategy: defaultStrategy),
    );
  }

  /// Build a local manifest by scanning files in [localPath].
  Future<SyncManifest> _buildLocalManifest(String localPath) async {
    final dir = Directory(localPath);
    if (!await dir.exists()) {
      return SyncManifest.empty();
    }

    final entries = <String, SyncFileEntry>{};
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final relativePath = entity.path.substring(localPath.length + 1);
        // Skip hidden files and manifest
        if (relativePath.startsWith('.')) continue;
        if (relativePath == '_sync_manifest.json') continue;

        final bytes = await entity.readAsBytes();
        final hash = crypto.sha256.convert(bytes).toString();
        final stat = await entity.stat();

        entries[relativePath] = SyncFileEntry(
          path: relativePath,
          sha256: hash,
          lastModified: stat.modified,
        );
      }
    }

    // Try to load last sync time from stored manifest
    final manifestFile = File('$localPath/_sync_manifest.json');
    DateTime lastSynced = DateTime.fromMillisecondsSinceEpoch(0);
    if (await manifestFile.exists()) {
      try {
        final stored = json.decode(await manifestFile.readAsString());
        lastSynced = DateTime.parse(stored['lastSynced']);
      } catch (_) {}
    }

    return SyncManifest(files: entries, lastSynced: lastSynced);
  }

  /// Save the local manifest after sync.
  Future<void> _saveLocalManifest(String localPath, SyncManifest manifest) async {
    final file = File('$localPath/_sync_manifest.json');
    await file.writeAsString(json.encode(manifest.toJson()));
  }

  /// Sync local directory with remote Drive folder.
  Future<SyncResult> sync({
    required String localPath,
    SyncDirection direction = SyncDirection.bidirectional,
    ConflictStrategy? onConflict,
  }) async {
    final localManifest = await _buildLocalManifest(localPath);

    final result = await _engine.sync(
      localPath: localPath,
      localManifest: localManifest,
      direction: direction,
      readLocalFile: (path) => File('$localPath/$path').readAsBytes(),
      writeLocalFile: (path, content) async {
        final file = File('$localPath/$path');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(content);
      },
    );

    // Update stored manifest after successful sync
    if (result.success) {
      final updated = await _buildLocalManifest(localPath);
      await _saveLocalManifest(localPath, updated);
    }

    return result;
  }

  /// Force push local → remote (overwrite remote).
  Future<SyncResult> push({required String localPath}) =>
      sync(localPath: localPath, direction: SyncDirection.push);

  /// Force pull remote → local (overwrite local).
  Future<SyncResult> pull({required String localPath}) =>
      sync(localPath: localPath, direction: SyncDirection.pull);

  /// Check sync status without transferring files.
  Future<SyncStatus> status({required String localPath}) async {
    final localManifest = await _buildLocalManifest(localPath);
    final remoteFiles = await adapter.listFiles();

    final remoteManifest = SyncManifest(
      files: remoteFiles.map((k, v) => MapEntry(
            k,
            SyncFileEntry(
              path: k,
              sha256: v.sha256 ?? '',
              lastModified: v.lastModified,
            ),
          )),
      lastSynced: DateTime.now(),
    );

    final diff = ManifestDiffer().diff(localManifest, remoteManifest);

    return SyncStatus(
      lastSynced: localManifest.lastSynced.millisecondsSinceEpoch > 0
          ? localManifest.lastSynced
          : null,
      localFiles: localManifest.files.length,
      remoteFiles: remoteManifest.files.length,
      pendingChanges: diff.hasChanges ? diff : null,
    );
  }
}
