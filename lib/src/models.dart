/// Direction of sync operation.
enum SyncDirection { push, pull, bidirectional }

/// Strategy for resolving conflicts when both local and remote changed.
enum ConflictStrategy { newerWins, localWins, remoteWins, askUser }

/// Represents a single file entry in a sync manifest.
class SyncFileEntry {
  final String path;
  final String sha256;
  final DateTime lastModified;

  const SyncFileEntry({
    required this.path,
    required this.sha256,
    required this.lastModified,
  });

  SyncFileEntry copyWith({String? sha256, DateTime? lastModified}) =>
      SyncFileEntry(
        path: path,
        sha256: sha256 ?? this.sha256,
        lastModified: lastModified ?? this.lastModified,
      );

  Map<String, dynamic> toJson() => {
    'path': path,
    'sha256': sha256,
    'lastModified': lastModified.toIso8601String(),
  };

  factory SyncFileEntry.fromJson(Map<String, dynamic> json) => SyncFileEntry(
    path: json['path'] as String,
    sha256: json['sha256'] as String,
    lastModified: DateTime.parse(json['lastModified'] as String),
  );

  @override
  bool operator ==(Object other) =>
      other is SyncFileEntry && other.path == path && other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(path, sha256);

  @override
  String toString() =>
      'SyncFileEntry($path, sha256=${sha256.substring(0, 8)}...)';
}

/// A manifest tracking all synced files and their state.
class SyncManifest {
  final Map<String, SyncFileEntry> files;
  final DateTime lastSynced;

  const SyncManifest({required this.files, required this.lastSynced});

  factory SyncManifest.empty() => SyncManifest(
    files: {},
    lastSynced: DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'files': files.map((k, v) => MapEntry(k, v.toJson())),
    'lastSynced': lastSynced.toIso8601String(),
  };

  factory SyncManifest.fromJson(Map<String, dynamic> json) {
    final filesMap = (json['files'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, SyncFileEntry.fromJson(v as Map<String, dynamic>)),
    );
    return SyncManifest(
      files: filesMap,
      lastSynced: DateTime.parse(json['lastSynced'] as String),
    );
  }
}

/// Result of diffing two manifests.
class ManifestDiff {
  final List<String> added; // in source but not target
  final List<String> modified; // in both, different sha256
  final List<String> deleted; // in target but not source
  final List<String> unchanged; // same sha256

  const ManifestDiff({
    required this.added,
    required this.modified,
    required this.deleted,
    required this.unchanged,
  });

  bool get hasChanges =>
      added.isNotEmpty || modified.isNotEmpty || deleted.isNotEmpty;

  int get totalChanges => added.length + modified.length + deleted.length;
}

/// A conflict between local and remote versions of a file.
class SyncConflict {
  final String path;
  final SyncFileEntry local;
  final SyncFileEntry remote;
  SyncConflictResolution? resolution;

  SyncConflict({
    required this.path,
    required this.local,
    required this.remote,
    this.resolution,
  });
}

/// How a conflict was resolved.
enum SyncConflictResolution { useLocal, useRemote, skip }

/// Result of a sync operation.
class SyncResult {
  final int filesUploaded;
  final int filesDownloaded;
  final int filesDeleted;
  final int conflicts;
  final List<SyncConflict> unresolvedConflicts;
  final DateTime syncedAt;
  final List<String> errors;

  const SyncResult({
    required this.filesUploaded,
    required this.filesDownloaded,
    this.filesDeleted = 0,
    this.conflicts = 0,
    this.unresolvedConflicts = const [],
    required this.syncedAt,
    this.errors = const [],
  });

  bool get success => errors.isEmpty && unresolvedConflicts.isEmpty;
}

/// Current sync status.
class SyncStatus {
  final DateTime? lastSynced;
  final int localFiles;
  final int remoteFiles;
  final ManifestDiff? pendingChanges;

  const SyncStatus({
    this.lastSynced,
    required this.localFiles,
    required this.remoteFiles,
    this.pendingChanges,
  });
}
