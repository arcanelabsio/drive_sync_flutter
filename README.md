# drive_sync_flutter

Bidirectional file sync between device storage and Google Drive, with conflict resolution.

## Features

- **Push, pull, or bidirectional** sync of any local directory to a Google Drive folder
- **SHA256-based change detection** — only transfers files that actually changed
- **Conflict resolution** — newerWins, localWins, remoteWins, or askUser (return conflicts to your UI)
- **Nested folder paths** — `apps/myapp/data` creates the full hierarchy automatically
- **Pluggable adapter interface** — Google Drive included; implement `DriveAdapter` for iCloud, S3, etc.
- **No database** — state tracked via a single JSON manifest file
- **Platform-agnostic** — sync engine uses callbacks for file I/O, no direct `dart:io` dependency

## Installation

```yaml
dependencies:
  drive_sync_flutter:
    git:
      url: https://github.com/ajitgunturi/drive_sync_flutter.git
```

## Quick Start

```dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:drive_sync_flutter/drive_sync_flutter.dart';

// 1. Authenticate with Google
final googleSignIn = GoogleSignIn(scopes: ['https://www.googleapis.com/auth/drive']);
final account = await googleSignIn.signIn();
final authClient = GoogleAuthClient(await account!.authHeaders);

// 2. Create an adapter pointing at your Drive folder
final adapter = GoogleDriveAdapter.withPath(
  httpClient: authClient,
  folderPath: 'apps/myapp/backups',
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

Handles Google Drive file operations. Supports nested folder paths — creates the full hierarchy if it doesn't exist.

```dart
// Single folder
final adapter = GoogleDriveAdapter(httpClient: authClient, folderName: 'Backups');

// Nested path (creates apps/ → myapp/ → data/ on Drive)
final adapter = GoogleDriveAdapter.withPath(
  httpClient: authClient,
  folderPath: 'apps/myapp/data',
);
```

### GoogleAuthClient

Convenience wrapper that injects Google auth headers into HTTP requests. Bridges `google_sign_in` with `googleapis`.

```dart
final account = await GoogleSignIn(scopes: ['drive']).signIn();
final authClient = GoogleAuthClient(await account!.authHeaders);
// Pass authClient to GoogleDriveAdapter
```

### Conflict Resolution

When both local and remote have modified the same file:

| Strategy | Behavior |
|----------|----------|
| `newerWins` | Most recent `lastModified` wins. Ties go to local. |
| `localWins` | Always keep the local version. |
| `remoteWins` | Always keep the remote version. |
| `askUser` | Skips the file and returns it in `result.unresolvedConflicts` for your UI to handle. |

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
DriveSyncClient          ← High-level API (sync/push/pull/status)
    │
    └── SyncEngine       ← Orchestrates diff → resolve → transfer
          │
          ├── ManifestDiffer     ← Compares file states (added/modified/deleted/unchanged)
          ├── ConflictResolver   ← Applies conflict strategy
          └── DriveAdapter       ← File I/O interface
                │
                └── GoogleDriveAdapter  ← Google Drive v3 implementation
```

**Manifest**: A JSON file (`.sync_manifest.json`) stored alongside your local data tracks `{path, sha256, lastModified}` for each synced file. Only files that changed since the last sync are transferred.

## Scope and Boundaries

### What this library does

- Syncs **files** (any format: JSON, YAML, images, binary, encrypted blobs) between a local directory and a Google Drive folder
- Detects changes via SHA256 checksums — only transfers files that actually differ
- Resolves conflicts when the same file is modified locally and remotely
- Creates nested folder hierarchies on Drive automatically
- Tracks sync state via a local manifest file (`.sync_manifest.json`)

### What this library does NOT do

- **No encryption.** Files are transferred as-is. If you need encryption, encrypt before syncing and decrypt after pulling. The library treats file contents as opaque bytes.
- **No authentication.** You must provide an authenticated `http.Client` (e.g., via `google_sign_in`). The library includes `GoogleAuthClient` as a convenience wrapper but does not manage OAuth flows, tokens, or refresh.
- **No background sync.** Sync is triggered explicitly by your code. No periodic timers, no push notifications, no wake locks.
- **No partial/resumable uploads.** Files are uploaded/downloaded in full. Not suitable for files larger than ~50MB.
- **No file locking or concurrency control.** Designed for single-device use. If multiple devices sync the same folder simultaneously, conflicts are resolved by strategy but race conditions are possible.
- **No subfolder recursion.** Syncs files in a single Drive folder (flat). Nested local directories are not traversed — you manage one folder per `DriveSyncClient`.

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

30 tests covering manifest diffing, conflict resolution, sync engine flows, and the full DriveSyncClient lifecycle.

## License

MIT
