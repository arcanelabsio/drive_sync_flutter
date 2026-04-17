# drive_sync_flutter

Bidirectional file sync between device storage and Google Drive, with conflict resolution.

## Features

- **Sandboxed Drive access** — all operations scoped to `.app/{appName}/`, preventing path traversal
- **Push, pull, or bidirectional** sync of any local directory to a Google Drive folder
- **SHA256-based change detection** — only transfers files that actually changed
- **Conflict resolution** — newerWins, localWins, remoteWins, or askUser (return conflicts to your UI)
- **Query injection protection** — all Drive API queries are escaped
- **Pluggable adapter interface** — Google Drive included; implement `DriveAdapter` for iCloud, S3, etc.
- **No database** — state tracked via a single JSON manifest file
- **Platform-agnostic** — sync engine uses callbacks for file I/O, no direct `dart:io` dependency

## Installation

```yaml
dependencies:
  drive_sync_flutter:
    git:
      url: https://github.com/arcanelabsio/drive_sync_flutter.git
```

## Quick Start

```dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:drive_sync_flutter/drive_sync_flutter.dart';

// 1. Authenticate with Google
final googleSignIn = GoogleSignIn(scopes: ['https://www.googleapis.com/auth/drive']);
final account = await googleSignIn.signIn();
final authClient = GoogleAuthClient(await account!.authHeaders);

// 2. Create a sandboxed adapter — scoped to .app/my_app/backups on Drive
final adapter = GoogleDriveAdapter.sandboxed(
  httpClient: authClient,
  appName: 'my_app',       // lowercase snake_case, required
  subPath: 'backups',      // optional subfolder
);

// 3. Create a sync client
final client = DriveSyncClient(
  adapter: adapter,
  defaultStrategy: ConflictStrategy.newerWins,
);

// 4. Sync!
final result = await client.sync(localPath: '/path/to/local/data');
print('${result.filesUploaded} uploaded, ${result.filesDownloaded} downloaded');
```

## Security

### Sandboxed Drive Access

`GoogleDriveAdapter.sandboxed()` enforces that all file operations are scoped under `.app/{appName}/` on the user's Google Drive. This prevents:

- **Path traversal** — `..` segments in `appName` or `subPath` are rejected at construction time
- **Arbitrary folder creation** — the `.app/` prefix is mandatory and cannot be bypassed
- **Query injection** — all values interpolated into Drive API queries are escaped

The `appName` parameter must be lowercase snake_case (`^[a-z][a-z0-9_]*$`). This is validated eagerly — an invalid name throws `ArgumentError` before any adapter instance is created.

```dart
// Valid
GoogleDriveAdapter.sandboxed(httpClient: client, appName: 'my_app');
GoogleDriveAdapter.sandboxed(httpClient: client, appName: 'my_app', subPath: 'Backups');

// Throws ArgumentError
GoogleDriveAdapter.sandboxed(httpClient: client, appName: 'MyApp');      // uppercase
GoogleDriveAdapter.sandboxed(httpClient: client, appName: '../hack');    // traversal
GoogleDriveAdapter.sandboxed(httpClient: client, appName: '');           // empty
```

### Drive Folder Structure

```
User's Google Drive
└── .app/
    └── my_app/
        ├── backups/        ← subPath: 'backups'
        │   ├── file1.json
        │   └── file2.json
        └── plans/          ← subPath: 'plans'
            ├── week1.json
            └── week2.json
```

### Deprecated Constructors

The unsandboxed constructors (`GoogleDriveAdapter()` and `GoogleDriveAdapter.withPath()`) are deprecated. They still work but emit deprecation warnings. Use `.sandboxed()` for all new code.

## API

### DriveSyncClient

The high-level API for syncing a local directory with a remote folder.

```dart
final client = DriveSyncClient(adapter: adapter);

// Bidirectional sync (default) — new files go both ways, conflicts resolved by strategy
final result = await client.sync(localPath: '/data');

// Push only — local overwrites remote
await client.push(localPath: '/data');

// Pull only — remote overwrites local
await client.pull(localPath: '/data');

// Check what would change without syncing
final status = await client.status(localPath: '/data');
print('Pending: ${status.pendingChanges?.totalChanges ?? 0}');
```

### GoogleDriveAdapter

Handles Google Drive file operations. The `.sandboxed()` constructor is the recommended way to create an adapter.

```dart
// Sandboxed (recommended) — scoped to .app/my_app/data on Drive
final adapter = GoogleDriveAdapter.sandboxed(
  httpClient: authClient,
  appName: 'my_app',
  subPath: 'data',
);

// Multiple folders for the same app
final plans = GoogleDriveAdapter.sandboxed(
  httpClient: authClient,
  appName: 'my_app',
  subPath: 'plans',    // .app/my_app/plans
);
final backups = GoogleDriveAdapter.sandboxed(
  httpClient: authClient,
  appName: 'my_app',
  subPath: 'backups',  // .app/my_app/backups
);
```

### GoogleAuthClient

Convenience wrapper that injects Google auth headers into HTTP requests. Bridges `google_sign_in` with `googleapis`.

```dart
final account = await GoogleSignIn(scopes: ['drive']).signIn();
final authClient = GoogleAuthClient(await account!.authHeaders);
// Pass authClient to GoogleDriveAdapter.sandboxed()
```

### SandboxValidator

Utility class for path validation. Used internally by `GoogleDriveAdapter.sandboxed()` but also available for custom validation.

```dart
SandboxValidator.validateAppName('my_app');   // passes
SandboxValidator.validateAppName('MyApp');     // throws ArgumentError

SandboxValidator.validateSubPath('Plans');     // passes
SandboxValidator.validateSubPath('../etc');    // throws ArgumentError

SandboxValidator.buildSandboxPath('my_app', 'data');  // returns '.app/my_app/data'

SandboxValidator.escapeDriveQuery("it's");    // returns "it\\'s"
```

### Conflict Resolution

When both local and remote have modified the same file, the library **picks one version** — it does NOT merge content. There is no three-way merge, no content-aware diffing. It compares SHA256 checksums (to detect changes) and `lastModified` timestamps (to pick a winner). This works equally well for JSON, binary, or encrypted files since it never reads file contents.

| Strategy | Behavior |
|----------|----------|
| `newerWins` | Most recent `lastModified` wins. Ties go to local. |
| `localWins` | Always keep the local version (remote is overwritten). |
| `remoteWins` | Always keep the remote version (local is overwritten). |
| `askUser` | Skips the file and returns it in `result.unresolvedConflicts` for your UI to handle. |

**Important:** The losing version is overwritten. If you need to preserve both versions, use `askUser` and implement your own merge or backup logic.

```dart
final client = DriveSyncClient(
  adapter: adapter,
  defaultStrategy: ConflictStrategy.remoteWins, // plans folder: remote is truth
);
```

### Custom Adapters

Implement `DriveAdapter` to sync with any cloud provider:

```dart
class S3Adapter implements DriveAdapter {
  @override
  Future<void> ensureFolder() async { /* create bucket/prefix */ }

  @override
  Future<Map<String, RemoteFileInfo>> listFiles() async { /* list objects */ }

  @override
  Future<void> uploadFile(String path, List<int> content) async { /* PUT object */ }

  @override
  Future<List<int>> downloadFile(String path) async { /* GET object */ }

  @override
  Future<void> deleteFile(String path) async { /* DELETE object */ }
}
```

## Architecture

```
DriveSyncClient          <- High-level API (sync/push/pull/status)
    |
    +-- SyncEngine       <- Orchestrates diff -> resolve -> transfer
          |
          +-- ManifestDiffer     <- Compares file states (added/modified/deleted/unchanged)
          +-- ConflictResolver   <- Applies conflict strategy
          +-- DriveAdapter       <- File I/O interface
                |
                +-- GoogleDriveAdapter  <- Google Drive v3 implementation
                      |
                      +-- SandboxValidator  <- Path validation + query escaping
```

**Manifest**: A JSON file (`_sync_manifest.json`) stored alongside your local data tracks `{path, sha256, lastModified}` for each synced file. Only files that changed since the last sync are transferred.

## Scope and Boundaries

### What this library does

- Syncs **files** (any format: JSON, YAML, images, binary, encrypted blobs) between a local directory and a Google Drive folder
- Detects changes via SHA256 checksums — only transfers files that actually differ
- Resolves conflicts when the same file is modified locally and remotely
- Creates nested folder hierarchies on Drive automatically
- Tracks sync state via a local manifest file (`_sync_manifest.json`)
- **Sandboxes all operations** under `.app/{appName}/` to prevent path traversal

### What this library does NOT do

- **No encryption.** Files are transferred as-is. If you need encryption, encrypt before syncing and decrypt after pulling.
- **No content merging.** Conflict resolution picks one version (local or remote) — it never merges file contents.
- **No authentication.** You must provide an authenticated `http.Client` (e.g., via `google_sign_in`).
- **No background sync.** Sync is triggered explicitly by your code.
- **No partial/resumable uploads.** Files are uploaded/downloaded in full. Not suitable for files larger than ~50MB.
- **No file locking or concurrency control.** Designed for single-device use.

### Developer responsibility

| Concern | Who handles it |
|---------|---------------|
| OAuth flow (sign-in, token refresh) | **You** — use `google_sign_in` or equivalent |
| Providing an authenticated HTTP client | **You** — wrap with `GoogleAuthClient` or your own |
| Encryption of sensitive data | **You** — encrypt before sync, decrypt after pull |
| File format and schema validation | **You** — library treats files as opaque bytes |
| Retry logic on network failure | **You** — library returns errors in `SyncResult.errors` |
| Background/periodic sync scheduling | **You** — call `sync()` when appropriate |
| Google Cloud project setup (OAuth consent, client IDs) | **You** — required for `google_sign_in` to work |

### Library responsibility

| Concern | Who handles it |
|---------|---------------|
| Change detection (SHA256) | **Library** |
| Manifest tracking | **Library** |
| Conflict resolution | **Library** (configurable strategy) |
| Google Drive CRUD (list, upload, download, delete) | **Library** (`GoogleDriveAdapter`) |
| Folder creation on Drive | **Library** (nested paths supported) |
| Path sandboxing and validation | **Library** (`SandboxValidator`) |
| Query injection prevention | **Library** (escaped query values) |
| Error reporting per file | **Library** (via `SyncResult.errors`) |

## Permissions

Your app needs:
- **Google Drive scope**: `https://www.googleapis.com/auth/drive` (full) or `https://www.googleapis.com/auth/drive.file` (app-created files only)
- **Internet access**
- **Device storage** (read/write local files)

## Testing

```bash
dart test
```

72 tests covering manifest diffing, conflict resolution, sync engine flows, sandbox validation, path enforcement, query injection prevention, and the full DriveSyncClient lifecycle.

## License

MIT
