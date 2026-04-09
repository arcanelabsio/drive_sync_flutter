/// Path sandboxing and validation for Google Drive operations.
///
/// Enforces that all Drive operations are scoped under `.app/{appName}/`.
/// Prevents path traversal, query injection, and invalid app names.
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

    if (subPath.startsWith('/')) {
      throw ArgumentError.value(subPath, 'subPath', 'must not start with /');
    }

    final segments = subPath.split('/');
    for (final segment in segments) {
      if (segment.isEmpty) {
        throw ArgumentError.value(subPath, 'subPath', 'must not contain empty segments (double slashes)');
      }
      if (segment == '..') {
        throw ArgumentError.value(subPath, 'subPath', 'must not contain path traversal (..)');
      }
      if (segment == '.') {
        throw ArgumentError.value(subPath, 'subPath', 'must not contain current-directory references (.)');
      }
    }
  }

  /// Build the sandboxed Drive folder path: `.app/{appName}` or `.app/{appName}/{subPath}`.
  ///
  /// Validates both arguments before building.
  static String buildSandboxPath(String appName, String? subPath) {
    validateAppName(appName);
    validateSubPath(subPath);

    if (subPath != null && subPath.isNotEmpty) {
      return '.app/$appName/$subPath';
    }
    return '.app/$appName';
  }

  /// Escape a value for use in Google Drive API query strings.
  ///
  /// Drive queries use single-quoted strings: `name = 'value'`.
  /// This escapes single quotes to prevent query injection.
  static String escapeDriveQuery(String value) {
    return value.replaceAll("'", "\\'");
  }
}
