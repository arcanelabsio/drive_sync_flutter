import 'models.dart';

/// Compares two [SyncManifest]s and produces a [ManifestDiff].
class ManifestDiffer {
  /// Diff [source] against [target].
  /// - added: in source but not target
  /// - modified: in both but sha256 differs
  /// - deleted: in target but not source
  /// - unchanged: same sha256
  ManifestDiff diff(SyncManifest source, SyncManifest target) {
    final added = <String>[];
    final modified = <String>[];
    final unchanged = <String>[];
    final deleted = <String>[];

    for (final path in source.files.keys) {
      final targetEntry = target.files[path];
      if (targetEntry == null) {
        added.add(path);
      } else if (source.files[path]!.sha256 != targetEntry.sha256) {
        modified.add(path);
      } else {
        unchanged.add(path);
      }
    }

    for (final path in target.files.keys) {
      if (!source.files.containsKey(path)) {
        deleted.add(path);
      }
    }

    added.sort();
    modified.sort();
    deleted.sort();
    unchanged.sort();

    return ManifestDiff(
      added: added,
      modified: modified,
      deleted: deleted,
      unchanged: unchanged,
    );
  }
}
