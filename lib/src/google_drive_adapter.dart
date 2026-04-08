import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'drive_adapter.dart';

/// Google Drive implementation of [DriveAdapter].
///
/// Supports nested folder paths like `apps-data/Longeviti/Longevity Plans`.
/// Creates the full folder hierarchy if it doesn't exist.
class GoogleDriveAdapter implements DriveAdapter {
  final http.Client httpClient;
  final String folderPath; // e.g. "apps-data/Longeviti/Longevity Plans"
  final drive.DriveApi _driveApi;
  String? _folderId;

  /// Legacy constructor — single folder name.
  GoogleDriveAdapter({
    required this.httpClient,
    required String folderName,
  })  : folderPath = folderName,
        _driveApi = drive.DriveApi(httpClient);

  /// Constructor with explicit nested path.
  GoogleDriveAdapter.withPath({
    required this.httpClient,
    required this.folderPath,
  }) : _driveApi = drive.DriveApi(httpClient);

  @override
  Future<void> ensureFolder() async {
    if (_folderId != null) return;

    final segments = folderPath.split('/').where((s) => s.isNotEmpty).toList();
    String? parentId; // null = root of Drive

    for (final segment in segments) {
      final folderId = await _findOrCreateFolder(segment, parentId);
      parentId = folderId;
    }

    _folderId = parentId;
  }

  /// Find a folder by name under a parent, or create it.
  Future<String> _findOrCreateFolder(String name, String? parentId) async {
    final parentClause = parentId != null ? "'$parentId' in parents and " : '';
    final query = "${parentClause}name = '$name' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final result = await _driveApi.files.list(q: query, spaces: 'drive');

    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id!;
    }

    // Create folder
    final folder = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder';
    if (parentId != null) {
      folder.parents = [parentId];
    }
    final created = await _driveApi.files.create(folder);
    return created.id!;
  }

  @override
  Future<Map<String, RemoteFileInfo>> listFiles() async {
    await ensureFolder();
    final result = <String, RemoteFileInfo>{};

    String? pageToken;
    do {
      final query = "'$_folderId' in parents and trashed = false";
      final response = await _driveApi.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'nextPageToken, files(id, name, modifiedTime, size, md5Checksum)',
        pageToken: pageToken,
      );

      for (final file in response.files ?? []) {
        result[file.name!] = RemoteFileInfo(
          path: file.name!,
          lastModified: file.modifiedTime ?? DateTime.now(),
          sizeBytes: int.tryParse(file.size ?? '0') ?? 0,
        );
      }
      pageToken = response.nextPageToken;
    } while (pageToken != null);

    return result;
  }

  @override
  Future<void> uploadFile(String remotePath, List<int> content) async {
    await ensureFolder();

    // Check if file already exists (update vs create)
    final query = "name = '$remotePath' and '$_folderId' in parents and trashed = false";
    final existing = await _driveApi.files.list(q: query, spaces: 'drive');

    final media = drive.Media(Stream.value(content), content.length);

    if (existing.files != null && existing.files!.isNotEmpty) {
      // Update existing file
      await _driveApi.files.update(
        drive.File(),
        existing.files!.first.id!,
        uploadMedia: media,
      );
    } else {
      // Create new file
      final file = drive.File()
        ..name = remotePath
        ..parents = [_folderId!];
      await _driveApi.files.create(file, uploadMedia: media);
    }
  }

  @override
  Future<List<int>> downloadFile(String remotePath) async {
    await ensureFolder();

    final query = "name = '$remotePath' and '$_folderId' in parents and trashed = false";
    final result = await _driveApi.files.list(q: query, spaces: 'drive');

    if (result.files == null || result.files!.isEmpty) {
      throw Exception('File not found in Drive: $remotePath');
    }

    final fileId = result.files!.first.id!;
    final media = await _driveApi.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    await ensureFolder();

    final query = "name = '$remotePath' and '$_folderId' in parents and trashed = false";
    final result = await _driveApi.files.list(q: query, spaces: 'drive');

    if (result.files != null && result.files!.isNotEmpty) {
      await _driveApi.files.delete(result.files!.first.id!);
    }
  }
}
