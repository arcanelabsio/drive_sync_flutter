import 'models.dart';

/// Resolves conflicts between local and remote file versions.
class ConflictResolver {
  final ConflictStrategy strategy;

  const ConflictResolver({this.strategy = ConflictStrategy.newerWins});

  /// Resolve a single conflict. Returns the resolution.
  SyncConflictResolution resolve(SyncConflict conflict) {
    switch (strategy) {
      case ConflictStrategy.localWins:
        return SyncConflictResolution.useLocal;
      case ConflictStrategy.remoteWins:
        return SyncConflictResolution.useRemote;
      case ConflictStrategy.askUser:
        return SyncConflictResolution.skip;
      case ConflictStrategy.newerWins:
        if (conflict.local.lastModified.isAfter(conflict.remote.lastModified)) {
          return SyncConflictResolution.useLocal;
        } else if (conflict.remote.lastModified.isAfter(
          conflict.local.lastModified,
        )) {
          return SyncConflictResolution.useRemote;
        }
        // Tie: prefer local (device is source of truth for tracking data)
        return SyncConflictResolution.useLocal;
    }
  }

  /// Resolve a list of conflicts. Sets each conflict's resolution field.
  List<SyncConflict> resolveAll(List<SyncConflict> conflicts) {
    for (final c in conflicts) {
      c.resolution = resolve(c);
    }
    return conflicts;
  }
}
