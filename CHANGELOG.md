## 1.1.0

- **Sandboxed Drive access**: New `GoogleDriveAdapter.sandboxed()` constructor scopes all operations under `.app/{appName}/`. App name must be lowercase snake_case.
- **Path traversal protection**: Validates `appName` and `subPath` — rejects `..`, absolute paths, empty segments.
- **Query injection fix**: All Drive API query interpolations now escape single quotes to prevent query injection.
- **Deprecated old constructors**: `GoogleDriveAdapter()` and `GoogleDriveAdapter.withPath()` are deprecated in favor of `.sandboxed()`.
- **42 new tests**: Sandbox validator unit tests + integration tests covering constructor validation, path enforcement, and query injection prevention.

### Migration

Replace:
```dart
GoogleDriveAdapter.withPath(
  httpClient: authClient,
  folderPath: 'apps/myapp/data',
);
```

With:
```dart
GoogleDriveAdapter.sandboxed(
  httpClient: authClient,
  appName: 'myapp',
  subPath: 'data',
);
```

The old constructors still work but emit deprecation warnings.

## 1.0.1

- Enable automated publishing from GitHub Actions via OIDC
- Verify CI → pub.dev pipeline

## 1.0.0

- Bidirectional file sync between device storage and Google Drive
- SHA256-based change detection (only transfers modified files)
- Conflict resolution: newerWins, localWins, remoteWins, askUser
- `GoogleDriveAdapter` with nested folder path support (`apps/myapp/data`)
- Pluggable `DriveAdapter` interface for custom cloud providers
- `GoogleAuthClient` helper for wrapping `google_sign_in` auth headers
- `DriveSyncClient` high-level API: sync, push, pull, status
- 30 tests covering unit, integration, and cross-component flows
