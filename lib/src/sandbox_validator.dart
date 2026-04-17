/// Path sandboxing and validation for Google Drive operations.
///
/// Two levels of validation:
/// - **Structural** (always on): rejects `..`, absolute paths, empty segments,
///   and escapes query strings. Applies in every mode.
/// - **App-name convention** (used by [GoogleDriveAdapter.sandboxed]): enforces
///   lowercase snake_case for the app namespace segment.
library;

class SandboxValidator {
  SandboxValidator._();

  static final _appNamePattern = RegExp(r'^[a-z][a-z0-9_]*$');

  /// Validate app name: lowercase snake_case, starts with letter, ASCII only.
  ///
  /// Valid: `'longeviti'`, `'my_app'`, `'app123'`
  /// Invalid: `''`, `'MyApp'`, `'my-app'`, `'../hack'`, `'123abc'`
  static void validateAppName(String appName) {
    if (appName.isEmpty) {
      throw ArgumentError.value(appName, 'appName', 'must not be empty');
    }
    if (!_appNamePattern.hasMatch(appName)) {
      throw ArgumentError.value(
        appName,
        'appName',
        'must be lowercase snake_case (a-z, 0-9, underscore), starting with a letter. '
            'Example: "my_app"',
      );
    }
  }

  /// Validate sub-path: no traversal, no absolute paths, no empty segments.
  ///
  /// Valid: `null`, `'Plans'`, `'Backups'`, `'deep/nested/path'`
  /// Invalid: `'../etc'`, `'/absolute'`, `'a//b'`, `'a/../../root'`
  static void validateSubPath(String? subPath) {
    if (subPath == null || subPath.isEmpty) return;
    _validatePathShape(subPath, 'subPath');
  }

  /// Validate an arbitrary Drive base path — used when the caller supplies
  /// their own prefix (e.g., `.app/longeviti` or `Longeviti/data` or `MyApp`).
  ///
  /// Rejects traversal, absolute paths, empty segments, trailing slashes.
  /// Does NOT enforce any naming convention — segments can contain spaces,
  /// uppercase, hyphens. Only structural safety is enforced.
  ///
  /// Valid: `'MyApp'`, `'.app/longeviti'`, `'Longeviti/data'`, `'folder-name'`
  /// Invalid: `''`, `'/abs'`, `'a/..'`, `'a//b'`, `'a/./b'`, `'path/'`
  static void validateBasePath(String basePath) {
    if (basePath.isEmpty) {
      throw ArgumentError.value(basePath, 'basePath', 'must not be empty');
    }
    _validatePathShape(basePath, 'basePath');
  }

  /// Validate a single folder name (no slashes, no traversal).
  ///
  /// Used by modes that take a single folder name rather than a multi-segment
  /// path (e.g., `GoogleDriveAdapter.appFiles(folderName:)`).
  static void validateFolderName(String folderName) {
    if (folderName.isEmpty) {
      throw ArgumentError.value(folderName, 'folderName', 'must not be empty');
    }
    if (folderName.contains('/')) {
      throw ArgumentError.value(
        folderName,
        'folderName',
        'must not contain slashes — use subPath for nested folders',
      );
    }
    if (folderName == '.' || folderName == '..') {
      throw ArgumentError.value(
        folderName,
        'folderName',
        'must not be "." or ".."',
      );
    }
  }

  static void _validatePathShape(String path, String name) {
    if (path.startsWith('/')) {
      throw ArgumentError.value(path, name, 'must not start with /');
    }
    if (path.endsWith('/')) {
      throw ArgumentError.value(path, name, 'must not end with /');
    }

    final segments = path.split('/');
    for (final segment in segments) {
      if (segment.isEmpty) {
        throw ArgumentError.value(
          path,
          name,
          'must not contain empty segments (double slashes)',
        );
      }
      if (segment == '..') {
        throw ArgumentError.value(
          path,
          name,
          'must not contain path traversal (..)',
        );
      }
      if (segment == '.') {
        throw ArgumentError.value(
          path,
          name,
          'must not contain current-directory references (.)',
        );
      }
    }
  }

  /// Build the sandboxed Drive folder path: `.app/{appName}` or
  /// `.app/{appName}/{subPath}`.
  ///
  /// Validates both arguments before building. Kept for backward compatibility
  /// with [GoogleDriveAdapter.sandboxed]. New code should use
  /// [joinBasePath] with an explicit prefix.
  static String buildSandboxPath(String appName, String? subPath) {
    validateAppName(appName);
    validateSubPath(subPath);

    if (subPath != null && subPath.isNotEmpty) {
      return '.app/$appName/$subPath';
    }
    return '.app/$appName';
  }

  /// Join a validated base path and an optional sub-path.
  ///
  /// Both components are validated. Returns `basePath` if `subPath` is
  /// null/empty, otherwise `'basePath/subPath'`.
  static String joinBasePath(String basePath, String? subPath) {
    validateBasePath(basePath);
    validateSubPath(subPath);
    if (subPath == null || subPath.isEmpty) return basePath;
    return '$basePath/$subPath';
  }

  /// Escape a value for use in Google Drive API query strings.
  ///
  /// Drive queries use single-quoted strings: `name = 'value'`.
  /// This escapes single quotes to prevent query injection.
  static String escapeDriveQuery(String value) {
    return value.replaceAll("'", "\\'");
  }
}
