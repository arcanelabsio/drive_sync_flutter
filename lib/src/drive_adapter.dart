/// Abstract interface for cloud storage operations.
/// Concrete implementations: [GoogleDriveAdapter].
/// Tests use mock implementations.
abstract class DriveAdapter {
  /// List all files in the remote sync folder.
  /// Returns map of path → {sha256, lastModified}.
  Future<Map<String, RemoteFileInfo>> listFiles();

  /// Upload a file to the remote sync folder.
  Future<void> uploadFile(String remotePath, List<int> content);

  /// Download a file from the remote sync folder.
  Future<List<int>> downloadFile(String remotePath);

  /// Delete a file from the remote sync folder.
  Future<void> deleteFile(String remotePath);

  /// Ensure the sync folder exists in remote storage.
  Future<void> ensureFolder();
}

/// Metadata for a file in remote storage.
class RemoteFileInfo {
  final String path;
  final String? sha256;
  final DateTime lastModified;
  final int sizeBytes;

  const RemoteFileInfo({
    required this.path,
    this.sha256,
    required this.lastModified,
    this.sizeBytes = 0,
  });
}
