import 'package:crypto/crypto.dart';
import 'models.dart';
import 'drive_adapter.dart';
import 'manifest_differ.dart';
import 'conflict_resolver.dart';

/// Callback to read a local file's bytes.
typedef ReadLocalFile = Future<List<int>> Function(String path);

/// Callback to write bytes to a local file.
typedef WriteLocalFile = Future<void> Function(String path, List<int> content);

/// Core sync engine. Orchestrates manifest diffing, conflict resolution,
/// and file transfer via a [DriveAdapter].
class SyncEngine {
  final DriveAdapter adapter;
  final ManifestDiffer differ;
  final ConflictResolver resolver;

  SyncEngine({
    required this.adapter,
    ManifestDiffer? differ,
    ConflictResolver? resolver,
  })  : differ = differ ?? ManifestDiffer(),
        resolver = resolver ?? const ConflictResolver();

  /// Build a remote manifest, computing sha256 by downloading content
  /// when the adapter doesn't provide checksums.
  Future<SyncManifest> _buildRemoteManifest() async {
    await adapter.ensureFolder();
    final remoteFiles = await adapter.listFiles();
    final entries = <String, SyncFileEntry>{};

    for (final entry in remoteFiles.entries) {
      String hash = entry.value.sha256 ?? '';
      if (hash.isEmpty) {
        // Adapter didn't provide hash — download and compute
        final bytes = await adapter.downloadFile(entry.key);
        hash = sha256.convert(bytes).toString();
      }
      entries[entry.key] = SyncFileEntry(
        path: entry.key,
        sha256: hash,
        lastModified: entry.value.lastModified,
      );
    }
    return SyncManifest(files: entries, lastSynced: DateTime.now());
  }

  /// Run a full sync cycle.
  ///
  /// [readLocalFile] and [writeLocalFile] are callbacks so the engine
  /// doesn't depend on dart:io (testable + platform-agnostic).
  Future<SyncResult> sync({
    required String localPath,
    required SyncManifest localManifest,
    SyncDirection direction = SyncDirection.bidirectional,
    ReadLocalFile? readLocalFile,
    WriteLocalFile? writeLocalFile,
  }) async {
    final remoteManifest = await _buildRemoteManifest();
    final errors = <String>[];
    var uploaded = 0;
    var downloaded = 0;
    var deleted = 0;

    // Identify files that exist in both with different hashes (conflicts)
    final conflictPaths = <String>{};

    if (direction == SyncDirection.bidirectional) {
      // Find files modified on both sides
      for (final path in localManifest.files.keys) {
        final remote = remoteManifest.files[path];
        if (remote != null && remote.sha256 != localManifest.files[path]!.sha256) {
          conflictPaths.add(path);
        }
      }

      // Resolve all conflicts upfront
      for (final path in conflictPaths) {
        final conflict = SyncConflict(
          path: path,
          local: localManifest.files[path]!,
          remote: remoteManifest.files[path]!,
        );
        final resolution = resolver.resolve(conflict);

        if (resolution == SyncConflictResolution.useLocal) {
          // Upload local version to remote
          try {
            final content = await readLocalFile!(path);
            await adapter.uploadFile(path, content);
            uploaded++;
          } catch (e) {
            errors.add('Upload (conflict) $path: $e');
          }
        } else if (resolution == SyncConflictResolution.useRemote) {
          // Download remote version to local
          try {
            final content = await adapter.downloadFile(path);
            await writeLocalFile!(path, content);
            downloaded++;
          } catch (e) {
            errors.add('Download (conflict) $path: $e');
          }
        }
        // skip: do nothing
      }
    }

    // Push: upload files that are local-only (not conflicts, not unchanged)
    if (direction == SyncDirection.push || direction == SyncDirection.bidirectional) {
      final localToRemote = differ.diff(localManifest, remoteManifest);

      for (final path in localToRemote.added) {
        try {
          final content = await readLocalFile!(path);
          await adapter.uploadFile(path, content);
          uploaded++;
        } catch (e) {
          errors.add('Upload $path: $e');
        }
      }

      // For push-only mode, also upload modified files (no conflict resolution)
      if (direction == SyncDirection.push) {
        for (final path in localToRemote.modified) {
          try {
            final content = await readLocalFile!(path);
            await adapter.uploadFile(path, content);
            uploaded++;
          } catch (e) {
            errors.add('Upload $path: $e');
          }
        }
      }
    }

    // Pull: download files that are remote-only (not conflicts, not unchanged)
    if (direction == SyncDirection.pull || direction == SyncDirection.bidirectional) {
      final remoteToLocal = differ.diff(remoteManifest, localManifest);

      for (final path in remoteToLocal.added) {
        try {
          final content = await adapter.downloadFile(path);
          await writeLocalFile!(path, content);
          downloaded++;
        } catch (e) {
          errors.add('Download $path: $e');
        }
      }

      // For pull-only mode, also download modified files (no conflict resolution)
      if (direction == SyncDirection.pull) {
        for (final path in remoteToLocal.modified) {
          try {
            final content = await adapter.downloadFile(path);
            await writeLocalFile!(path, content);
            downloaded++;
          } catch (e) {
            errors.add('Download $path: $e');
          }
        }
      }
    }

    return SyncResult(
      filesUploaded: uploaded,
      filesDownloaded: downloaded,
      filesDeleted: deleted,
      syncedAt: DateTime.now(),
      errors: errors,
    );
  }
}
