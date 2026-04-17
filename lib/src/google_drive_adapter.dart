import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'drive_adapter.dart';
import 'drive_scope.dart';
import 'sandbox_validator.dart';

/// Google Drive implementation of [DriveAdapter].
///
/// Three construction modes, each mapped to a specific OAuth scope:
///
/// - [GoogleDriveAdapter.userDrive] — full `drive` scope. Arbitrary base
///   path in the user's Drive. Use when files are written by multiple
///   OAuth clients (mobile app + CLI + Drive Desktop).
/// - [GoogleDriveAdapter.appFiles] — `drive.file` scope. Scoped to a
///   folder the app created. No CASA required.
/// - [GoogleDriveAdapter.appData] — `drive.appdata` scope. Hidden
///   per-OAuth-client folder. No CASA required.
///
/// The legacy [GoogleDriveAdapter.sandboxed] is preserved for backward
/// compatibility and is equivalent to `userDrive(basePath: '.app/$appName')`.
class GoogleDriveAdapter implements DriveAdapter {
  final http.Client httpClient;

  /// The declared OAuth scope. Determines how Drive API calls are issued.
  final DriveScope scope;

  /// The Drive folder path this adapter operates in.
  ///
  /// For [DriveScope.fullDrive] and [DriveScope.driveFile], this is a
  /// slash-separated path under the user's Drive root (or the app's
  /// visible set, respectively).
  ///
  /// For [DriveScope.appData], this is the sub-path *within* the hidden
  /// `appDataFolder`. Empty string means the appDataFolder root itself.
  final String folderPath;

  final drive.DriveApi _driveApi;
  String? _folderId;

  GoogleDriveAdapter._({
    required this.httpClient,
    required this.scope,
    required this.folderPath,
  }) : _driveApi = drive.DriveApi(httpClient);

  /// Full `drive` scope. Consumer chooses the base path.
  ///
  /// [basePath] is validated for structure (no `..`, no `//`, no leading
  /// or trailing slash) but no naming convention is enforced — any
  /// segment characters are allowed. Example base paths:
  /// `'MyApp'`, `'.app/longeviti'`, `'Backups/2026'`.
  ///
  /// [subPath] is optional extra nesting, validated the same way.
  ///
  /// **Warning:** this mode uses the restricted `drive` scope, which
  /// requires Google OAuth verification and annual CASA for public
  /// distribution. See [DriveScope.fullDrive].
  factory GoogleDriveAdapter.userDrive({
    required http.Client httpClient,
    required String basePath,
    String? subPath,
  }) {
    final fullPath = SandboxValidator.joinBasePath(basePath, subPath);
    return GoogleDriveAdapter._(
      httpClient: httpClient,
      scope: DriveScope.fullDrive,
      folderPath: fullPath,
    );
  }

  /// `drive.file` scope. Only files this OAuth client created are visible.
  ///
  /// [folderName] is a single folder name (no slashes — use [subPath] for
  /// nesting). Created in the user's Drive root on first sync.
  ///
  /// [subPath] is optional extra nesting within the folder.
  ///
  /// The app can only see and modify files it created. Files dropped in
  /// by the user, by Drive Desktop, or by other OAuth clients will be
  /// invisible — even if they live in the same folder. See
  /// [DriveScope.driveFile].
  factory GoogleDriveAdapter.appFiles({
    required http.Client httpClient,
    required String folderName,
    String? subPath,
  }) {
    SandboxValidator.validateFolderName(folderName);
    SandboxValidator.validateSubPath(subPath);
    final fullPath = subPath == null || subPath.isEmpty
        ? folderName
        : '$folderName/$subPath';
    return GoogleDriveAdapter._(
      httpClient: httpClient,
      scope: DriveScope.driveFile,
      folderPath: fullPath,
    );
  }

  /// `drive.appdata` scope. Operates in a hidden per-OAuth-client folder.
  ///
  /// The user cannot see this folder in the Drive UI. Only this exact
  /// OAuth client ID can access it. Files do not count against the
  /// appDataFolder quota limit of 10GB per client.
  ///
  /// [subPath] is optional nesting within `appDataFolder`. If null or
  /// empty, files sync directly into the appDataFolder root.
  ///
  /// See [DriveScope.appData].
  factory GoogleDriveAdapter.appData({
    required http.Client httpClient,
    String? subPath,
  }) {
    SandboxValidator.validateSubPath(subPath);
    return GoogleDriveAdapter._(
      httpClient: httpClient,
      scope: DriveScope.appData,
      folderPath: subPath ?? '',
    );
  }

  /// Legacy sandboxed constructor — sandboxed under `.app/{appName}/{subPath}`
  /// with full `drive` scope.
  ///
  /// Equivalent to [GoogleDriveAdapter.userDrive] with
  /// `basePath: '.app/$appName'`. Preserved for backward compatibility.
  ///
  /// Prefer [GoogleDriveAdapter.userDrive] (for explicit base path),
  /// [GoogleDriveAdapter.appFiles] (to avoid CASA), or
  /// [GoogleDriveAdapter.appData] (for hidden app state) in new code.
  @Deprecated(
    'Use GoogleDriveAdapter.userDrive(basePath: ".app/\$appName") for the '
    'same behavior, or .appFiles()/.appData() to avoid the CASA audit '
    'requirement of the full drive scope.',
  )
  factory GoogleDriveAdapter.sandboxed({
    required http.Client httpClient,
    required String appName,
    String? subPath,
  }) {
    final path = SandboxValidator.buildSandboxPath(appName, subPath);
    return GoogleDriveAdapter._(
      httpClient: httpClient,
      scope: DriveScope.fullDrive,
      folderPath: path,
    );
  }

  /// Legacy constructor — single folder name, no sandboxing.
  @Deprecated(
    'Use GoogleDriveAdapter.userDrive() or .appFiles() for explicit scope control',
  )
  factory GoogleDriveAdapter({
    required http.Client httpClient,
    required String folderName,
  }) {
    return GoogleDriveAdapter._(
      httpClient: httpClient,
      scope: DriveScope.fullDrive,
      folderPath: folderName,
    );
  }

  /// Legacy constructor with explicit nested path, no sandboxing.
  @Deprecated(
    'Use GoogleDriveAdapter.userDrive() or .appFiles() for explicit scope control',
  )
  factory GoogleDriveAdapter.withPath({
    required http.Client httpClient,
    required String folderPath,
  }) {
    return GoogleDriveAdapter._(
      httpClient: httpClient,
      scope: DriveScope.fullDrive,
      folderPath: folderPath,
    );
  }

  // ---------- Scope helpers ----------

  /// Drive API `spaces` parameter for list queries.
  String get _spaces => scope == DriveScope.appData ? 'appDataFolder' : 'drive';

  /// Parent ID to use when creating a new top-level folder.
  ///
  /// In `appData` mode, top-level folders are parented to the
  /// `appDataFolder` alias. In other modes, top-level folders have no
  /// parent (i.e., live in the user's Drive root).
  String? get _topLevelParent =>
      scope == DriveScope.appData ? 'appDataFolder' : null;

  // ---------- Error mapping ----------

  /// Wrap a Drive API call so that scope-mismatch errors surface as
  /// [DriveScopeError] instead of raw [drive.DetailedApiRequestError].
  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 403 || e.status == 401) {
        throw DriveScopeError(
          declaredScope: scope,
          message:
              'Drive API returned ${e.status} (${e.message}). The auth '
              'client likely does not have the required OAuth scope for '
              'this adapter mode (declared: $scope). Verify the '
              'http.Client was obtained with the matching scope.',
          cause: e,
        );
      }
      rethrow;
    }
  }

  // ---------- DriveAdapter implementation ----------

  @override
  Future<void> ensureFolder() async {
    if (_folderId != null) return;

    if (scope == DriveScope.appData && folderPath.isEmpty) {
      _folderId = 'appDataFolder';
      return;
    }

    final segments = folderPath.split('/').where((s) => s.isNotEmpty).toList();
    String? parentId = _topLevelParent;

    for (final segment in segments) {
      parentId = await _findOrCreateFolder(segment, parentId);
    }

    _folderId = parentId;
  }

  Future<String> _findOrCreateFolder(String name, String? parentId) async {
    final escapedName = SandboxValidator.escapeDriveQuery(name);
    final parentClause = parentId != null ? "'$parentId' in parents and " : '';
    final query =
        "${parentClause}name = '$escapedName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";

    final result = await _guard(
      () => _driveApi.files.list(q: query, spaces: _spaces),
    );

    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id!;
    }

    final folder = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder';
    if (parentId != null) {
      folder.parents = [parentId];
    }
    final created = await _guard(() => _driveApi.files.create(folder));
    return created.id!;
  }

  @override
  Future<Map<String, RemoteFileInfo>> listFiles() async {
    await ensureFolder();
    final result = <String, RemoteFileInfo>{};

    String? pageToken;
    do {
      final query = "'$_folderId' in parents and trashed = false";
      final response = await _guard(
        () => _driveApi.files.list(
          q: query,
          spaces: _spaces,
          $fields:
              'nextPageToken, files(id, name, modifiedTime, size, md5Checksum)',
          pageToken: pageToken,
        ),
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
    final existing = await _guard(
      () => _driveApi.files.list(q: query, spaces: _spaces),
    );

    final media = drive.Media(Stream.value(content), content.length);

    if (existing.files != null && existing.files!.isNotEmpty) {
      await _guard(
        () => _driveApi.files.update(
          drive.File(),
          existing.files!.first.id!,
          uploadMedia: media,
        ),
      );
    } else {
      final file = drive.File()
        ..name = remotePath
        ..parents = [_folderId!];
      await _guard(() => _driveApi.files.create(file, uploadMedia: media));
    }
  }

  @override
  Future<List<int>> downloadFile(String remotePath) async {
    await ensureFolder();

    final escapedPath = SandboxValidator.escapeDriveQuery(remotePath);
    final query =
        "name = '$escapedPath' and '$_folderId' in parents and trashed = false";
    final result = await _guard(
      () => _driveApi.files.list(q: query, spaces: _spaces),
    );

    if (result.files == null || result.files!.isEmpty) {
      throw Exception('File not found in Drive: $remotePath');
    }

    final fileId = result.files!.first.id!;
    final media =
        await _guard(
              () => _driveApi.files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              ),
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
    final result = await _guard(
      () => _driveApi.files.list(q: query, spaces: _spaces),
    );

    if (result.files != null && result.files!.isNotEmpty) {
      await _guard(() => _driveApi.files.delete(result.files!.first.id!));
    }
  }
}
