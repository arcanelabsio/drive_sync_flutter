import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'drive_adapter.dart';
import 'sandbox_validator.dart';

/// Google Drive implementation of [DriveAdapter].
///
/// Use [GoogleDriveAdapter.sandboxed] (recommended) to create an adapter
/// scoped to `.app/{appName}/{subPath}` on the user's Drive.
class GoogleDriveAdapter implements DriveAdapter {
  final http.Client httpClient;
  final String folderPath;
  final drive.DriveApi _driveApi;
  String? _folderId;

  /// Create an adapter sandboxed under `.app/{appName}/{subPath}`.
  ///
  /// [appName] must be lowercase snake_case (e.g., `'longeviti'`, `'my_app'`).
  /// [subPath] is optional (e.g., `'Plans'`, `'Backups'`). Must not contain `..`.
  ///
  /// The resulting Drive folder path is `.app/{appName}` or `.app/{appName}/{subPath}`.
  GoogleDriveAdapter.sandboxed({
    required this.httpClient,
    required String appName,
    String? subPath,
  }) : folderPath = SandboxValidator.buildSandboxPath(appName, subPath),
       _driveApi = drive.DriveApi(httpClient);

  /// Legacy constructor — single folder name, no sandboxing.
  @Deprecated(
    'Use GoogleDriveAdapter.sandboxed() for safe, sandboxed Drive access',
  )
  GoogleDriveAdapter({required this.httpClient, required String folderName})
    : folderPath = folderName,
      _driveApi = drive.DriveApi(httpClient);

  /// Constructor with explicit nested path, no sandboxing.
  @Deprecated(
    'Use GoogleDriveAdapter.sandboxed() for safe, sandboxed Drive access',
  )
  GoogleDriveAdapter.withPath({
    required this.httpClient,
    required this.folderPath,
  }) : _driveApi = drive.DriveApi(httpClient);

  @override
  Future<void> ensureFolder() async {
    if (_folderId != null) return;

    final segments = folderPath.split('/').where((s) => s.isNotEmpty).toList();
    String? parentId;

    for (final segment in segments) {
      final folderId = await _findOrCreateFolder(segment, parentId);
      parentId = folderId;
    }

    _folderId = parentId;
  }

  Future<String> _findOrCreateFolder(String name, String? parentId) async {
    final escapedName = SandboxValidator.escapeDriveQuery(name);
    final parentClause = parentId != null ? "'$parentId' in parents and " : '';
    final query =
        "${parentClause}name = '$escapedName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final result = await _driveApi.files.list(q: query, spaces: 'drive');

    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id!;
    }

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
        $fields:
            'nextPageToken, files(id, name, modifiedTime, size, md5Checksum)',
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

    final escapedPath = SandboxValidator.escapeDriveQuery(remotePath);
    final query =
        "name = '$escapedPath' and '$_folderId' in parents and trashed = false";
    final existing = await _driveApi.files.list(q: query, spaces: 'drive');

    final media = drive.Media(Stream.value(content), content.length);

    if (existing.files != null && existing.files!.isNotEmpty) {
      await _driveApi.files.update(
        drive.File(),
        existing.files!.first.id!,
        uploadMedia: media,
      );
    } else {
      final file = drive.File()
        ..name = remotePath
        ..parents = [_folderId!];
      await _driveApi.files.create(file, uploadMedia: media);
    }
  }

  @override
  Future<List<int>> downloadFile(String remotePath) async {
    await ensureFolder();

    final escapedPath = SandboxValidator.escapeDriveQuery(remotePath);
    final query =
        "name = '$escapedPath' and '$_folderId' in parents and trashed = false";
    final result = await _driveApi.files.list(q: query, spaces: 'drive');

    if (result.files == null || result.files!.isEmpty) {
      throw Exception('File not found in Drive: $remotePath');
    }

    final fileId = result.files!.first.id!;
    final media =
        await _driveApi.files.get(
              fileId,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;

    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    await ensureFolder();

    final escapedPath = SandboxValidator.escapeDriveQuery(remotePath);
    final query =
        "name = '$escapedPath' and '$_folderId' in parents and trashed = false";
    final result = await _driveApi.files.list(q: query, spaces: 'drive');

    if (result.files != null && result.files!.isNotEmpty) {
      await _driveApi.files.delete(result.files!.first.id!);
    }
  }
}
