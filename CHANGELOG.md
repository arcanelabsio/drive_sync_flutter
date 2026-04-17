## 1.2.0

- **Three OAuth scope modes**: `GoogleDriveAdapter` now supports all three Google Drive scopes via explicit named constructors. The consumer chooses the compliance posture.
  - `GoogleDriveAdapter.userDrive(basePath:, subPath:)` — full `drive` scope. Arbitrary base path. Required when files are written by multiple OAuth clients (mobile + CLI + Drive Desktop). Triggers Google OAuth verification + annual CASA.
  - `GoogleDriveAdapter.appFiles(folderName:, subPath:)` — `drive.file` scope. App sees only files it created. Non-sensitive scope, no CASA.
  - `GoogleDriveAdapter.appData(subPath:)` — `drive.appdata` scope. Hidden per-OAuth-client folder inside `appDataFolder`. Non-sensitive scope, no CASA.
- **`DriveScope` enum** exported so consumers can inspect `adapter.scope`.
- **`DriveScopeError`** — 401/403 Drive API errors are now translated into a clear scope-mismatch error with a remediation message instead of raw `DetailedApiRequestError`.
- **`SandboxValidator` refactor** — split structural path validation (always on) from the `.app/{appName}` naming convention. Added `validateBasePath`, `validateFolderName`, and `joinBasePath`. Existing methods retained for backward compatibility.
- **45 new tests** — covering all three modes, path validation variants, and legacy constructor backward compatibility.

### Backward compatibility

All existing constructors (`GoogleDriveAdapter.sandboxed()`, `GoogleDriveAdapter()`, `GoogleDriveAdapter.withPath()`) still work exactly as before. `.sandboxed()` now emits a deprecation warning pointing to the new API. Migration is a 1:1 call-site rewrite:

```dart
// Before (still works, deprecated):
GoogleDriveAdapter.sandboxed(
  httpClient: authClient,
  appName: 'longeviti',
  subPath: 'plans',
);

// After — same behavior, explicit scope:
GoogleDriveAdapter.userDrive(
  httpClient: authClient,
  basePath: '.app/longeviti',
  subPath: 'plans',
);
```

### Choosing a scope

| Use case | Constructor | CASA required? |
|---|---|---|
| Mobile app + CLI tool + Drive Desktop all write files | `.userDrive()` | Yes, annually (~$5K–$20K) |
| Mobile app is the only writer, public distribution | `.appFiles()` | No — standard OAuth verification only |
| Hidden app state/config, no user visibility needed | `.appData()` | No — standard OAuth verification only |

See the README "OAuth Scopes & Compliance" section for the full comparison and the CASA tradeoff discussion.

## 1.1.1

- Fix dart format compliance for pub.dev CI
- Fix dangling library doc comment lint

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
