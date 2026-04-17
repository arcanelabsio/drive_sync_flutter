# drive_sync_flutter

Bidirectional file sync between device storage and Google Drive, with conflict resolution.

## Features

- **Three OAuth scope modes** — `drive` (full), `drive.file` (app-created files only), `drive.appdata` (hidden app folder). Consumer picks based on architecture and compliance needs — see [OAuth Scopes & Compliance](#oauth-scopes--compliance)
- **Push, pull, or bidirectional** sync of any local directory to a Google Drive folder
- **SHA256-based change detection** — only transfers files that actually changed
- **Conflict resolution** — newerWins, localWins, remoteWins, or askUser (return conflicts to your UI)
- **Path traversal + query injection protection** — always on, regardless of scope mode
- **Pluggable adapter interface** — Google Drive included; implement `DriveAdapter` for iCloud, S3, etc.
- **No database** — state tracked via a single JSON manifest file
- **Platform-agnostic** — sync engine uses callbacks for file I/O, no direct `dart:io` dependency

## Installation

```yaml
dependencies:
  drive_sync_flutter: ^1.2.0
```

## Quick Start

Pick a constructor that matches your OAuth scope. See [OAuth Scopes & Compliance](#oauth-scopes--compliance) below for the full comparison.

```dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:drive_sync_flutter/drive_sync_flutter.dart';

// 1. Authenticate with the scope that matches the adapter mode you want.
final googleSignIn = GoogleSignIn(scopes: [
  // Pick one:
  'https://www.googleapis.com/auth/drive',          // userDrive mode
  // 'https://www.googleapis.com/auth/drive.file',  // appFiles mode
  // 'https://www.googleapis.com/auth/drive.appdata' // appData mode
]);
final account = await googleSignIn.signIn();
final authClient = GoogleAuthClient(await account!.authHeaders);

// 2. Create an adapter. Three options — pick the one matching your scope.

// Option A: appFiles — drive.file scope. No CASA. App only sees files it created.
final adapter = GoogleDriveAdapter.appFiles(
  httpClient: authClient,
  folderName: 'MyApp',
  subPath: 'backups',
);

// Option B: userDrive — full drive scope. Arbitrary base path. Triggers CASA for public distribution.
// final adapter = GoogleDriveAdapter.userDrive(
//   httpClient: authClient,
//   basePath: '.app/longeviti',  // any path you choose
//   subPath: 'plans',
// );

// Option C: appData — drive.appdata scope. Hidden folder, invisible in Drive UI.
// final adapter = GoogleDriveAdapter.appData(
//   httpClient: authClient,
//   subPath: 'cache',
// );

// 3. Create a sync client and sync.
final client = DriveSyncClient(
  adapter: adapter,
  defaultStrategy: ConflictStrategy.newerWins,
);
final result = await client.sync(localPath: '/path/to/local/data');
print('${result.filesUploaded} uploaded, ${result.filesDownloaded} downloaded');
```

## OAuth Scopes & Compliance

The library supports all three Google Drive OAuth scopes. Your choice determines what files the app can see, whether you need CASA (annual security audit), and what tradeoffs you're making.

### At-a-glance comparison

| Constructor | OAuth scope | App sees | User sees | CASA needed? |
|---|---|---|---|---|
| `.userDrive()` | `drive` (full) | Everything in the user's Drive | Files visible in Drive UI | **Yes** for public distribution |
| `.appFiles()` | `drive.file` | Only files this app created | Files visible in Drive UI | No |
| `.appData()` | `drive.appdata` | Only contents of hidden `appDataFolder` | **Nothing** (folder is hidden) | No |

### Which one should I pick?

**Use `.appFiles()` if:** Your app is the only writer. No CLI tool, no companion web app, no Drive Desktop drops, no manual user uploads to the sync folder. This is the 80% case and the lowest compliance burden.

**Use `.userDrive()` if:** Files in the sync folder are written by more than one OAuth client — for example, a CLI tool on a laptop plus a mobile app, or Drive Desktop drops that the app needs to read. Full `drive` scope is the only way for the app to see files created by other identities. This is a *restricted* scope; public distribution on Play Store / App Store requires Google OAuth verification **plus** annual CASA ([details below](#casa-and-the-restricted-scope-tax)).

**Use `.appData()` if:** You're syncing internal state the user should never see — app config, caches, encrypted blobs. The `appDataFolder` is invisible in the Drive UI, quota-separate from the user's Drive, and strictly scoped to this OAuth client ID.

### The visibility trap with `.appFiles()`

`drive.file` is scoped by **creating OAuth client ID**, not by path. If *any* actor other than your Flutter app writes into the folder — the user manually, Google Drive Desktop syncing up a local file, a companion CLI tool — those files are **invisible** to your app's `listFiles()` call, even if they live in the same folder.

If your architecture has multiple writers (common for "sync my CLI output to my phone" patterns), `.appFiles()` will silently hide the other writers' files. You'll only discover this in production, when a user says "where are my plans?"

### CASA and the restricted-scope tax

`.userDrive()` uses the `drive` scope, which Google classifies as *restricted*. Public distribution requires:

1. **Google OAuth verification** — one-time review, free, takes 1–4 weeks. Brand/domain verification + privacy policy review + scope-justification video.
2. **Annual CASA** (Cloud Application Security Assessment) — third-party security audit by a Google-approved lab (Bishop Fox, Leviathan, NCC Group, Security Innovation, etc.). Tier 2 is the common minimum: ~$5K–$20K/year. Includes pen test, SAST/DAST scan, token-storage review, deletion-flow review.

**Can you skip CASA?** Yes, if you keep your OAuth client in **Testing** publishing status. Constraints:

- Up to 100 test users (listed by Gmail address)
- Users see a "Google hasn't verified this app" warning on first sign-in (one-time per user)
- Refresh tokens for restricted scopes expire every 7 days — users re-sign-in weekly

Testing mode is the legitimate path for personal apps, family tools, and small-circle distribution. The 100-user cap is the hard ceiling. Distribution channel (direct APK, TestFlight, sideload, `flutter run`) is orthogonal to CASA — only the Consent Screen publishing status matters.

**Workspace escape hatch:** If you have a Google Workspace domain and all users have accounts on it, you can set the Consent Screen user type to `Internal`. Internal apps skip verification entirely — no CASA, no 100-user cap, no 7-day re-auth. Only works if your user base is inside a Workspace org.

## Security

### Path Validation (always on)

Every mode validates all path arguments before construction. These rules apply uniformly across `.userDrive()`, `.appFiles()`, `.appData()`, and the legacy `.sandboxed()`:

- **No path traversal** — `..` segments rejected
- **No absolute paths** — leading `/` rejected
- **No empty segments** — `//` rejected
- **No trailing slash** — `path/` rejected
- **No dot segments** — `.` rejected
- **Query injection prevention** — all file names and folder names escaped before interpolation into Drive API queries

Invalid arguments throw `ArgumentError` before any adapter instance is created — no Drive API calls are made until you try to sync.

### Scope-mismatch error mapping

If the auth client's actual scope doesn't match the adapter's declared scope, the first Drive API call will 403. The library catches this and re-raises as `DriveScopeError` with a clear remediation message:

```
DriveScopeError(declared=DriveScope.fullDrive): Drive API returned 403 (...).
The auth client likely does not have the required OAuth scope for this
adapter mode (declared: DriveScope.fullDrive). Verify the http.Client was
obtained with the matching scope.
```

### Drive folder layouts

```
.userDrive(basePath: '.app/longeviti', subPath: 'plans')
└── User's Google Drive
    └── .app/
        └── longeviti/
            └── plans/            ← synced files here

.appFiles(folderName: 'MyApp', subPath: 'backups')
└── User's Google Drive
    └── MyApp/
        └── backups/              ← synced files here (visible to user;
                                     app can only see what it created)

.appData(subPath: 'cache')
└── Hidden appDataFolder (invisible to user)
    └── cache/                    ← synced files here
```

### Deprecated constructors

`.sandboxed()`, the default `GoogleDriveAdapter()`, and `.withPath()` are all deprecated. They still work with zero behavior changes — migration is optional. The recommended replacements:

| Old | New | Notes |
|---|---|---|
| `GoogleDriveAdapter.sandboxed(appName: 'longeviti', subPath: 'x')` | `GoogleDriveAdapter.userDrive(basePath: '.app/longeviti', subPath: 'x')` | Same behavior, explicit scope |
| `GoogleDriveAdapter(folderName: 'x')` | `GoogleDriveAdapter.userDrive(basePath: 'x')` or `.appFiles(folderName: 'x')` | Pick based on scope you want |
| `GoogleDriveAdapter.withPath(folderPath: 'a/b/c')` | `GoogleDriveAdapter.userDrive(basePath: 'a/b/c')` | Same behavior, explicit scope |

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

Handles Google Drive file operations. Three constructors, one per OAuth scope.

```dart
// drive.file — recommended default. No CASA. App sees only its own files.
final adapter = GoogleDriveAdapter.appFiles(
  httpClient: authClient,
  folderName: 'MyApp',
  subPath: 'data',
);

// Full drive — when multiple OAuth clients write to the same folder.
final adapter = GoogleDriveAdapter.userDrive(
  httpClient: authClient,
  basePath: '.app/longeviti',   // any path — no fixed prefix
  subPath: 'plans',
);

// drive.appdata — hidden per-client folder, invisible to user.
final adapter = GoogleDriveAdapter.appData(
  httpClient: authClient,
  subPath: 'cache',
);

// Multiple adapters for the same app are fine — they don't interfere.
final plans = GoogleDriveAdapter.appFiles(
  httpClient: authClient, folderName: 'MyApp', subPath: 'plans',
);
final backups = GoogleDriveAdapter.appFiles(
  httpClient: authClient, folderName: 'MyApp', subPath: 'backups',
);
```

Inspect the declared scope on an existing adapter:

```dart
final adapter = GoogleDriveAdapter.appFiles(httpClient: c, folderName: 'MyApp');
print(adapter.scope);        // DriveScope.driveFile
print(adapter.folderPath);   // 'MyApp'
```

### GoogleAuthClient

Convenience wrapper that injects Google auth headers into HTTP requests. Bridges `google_sign_in` with `googleapis`.

```dart
final account = await GoogleSignIn(scopes: ['drive']).signIn();
final authClient = GoogleAuthClient(await account!.authHeaders);
// Pass authClient to GoogleDriveAdapter.appFiles() / .userDrive() / .appData()
```

### SandboxValidator

Utility class for path validation. Used internally by every `GoogleDriveAdapter` constructor, also available for custom validation in your own code.

```dart
// Structural validation — always on regardless of scope mode
SandboxValidator.validateBasePath('.app/longeviti');  // passes
SandboxValidator.validateBasePath('MyApp/data');      // passes
SandboxValidator.validateBasePath('../hack');         // throws ArgumentError
SandboxValidator.validateBasePath('/absolute');       // throws ArgumentError

SandboxValidator.validateSubPath('Plans');            // passes
SandboxValidator.validateSubPath(null);               // passes (optional)
SandboxValidator.validateSubPath('a/../b');           // throws ArgumentError

SandboxValidator.validateFolderName('MyApp');         // passes
SandboxValidator.validateFolderName('a/b');           // throws ArgumentError (use subPath)

SandboxValidator.joinBasePath('MyApp', 'data');       // 'MyApp/data'

// Naming convention — only used by legacy .sandboxed()
SandboxValidator.validateAppName('my_app');   // passes (lowercase snake_case)
SandboxValidator.validateAppName('MyApp');     // throws ArgumentError

// Query injection prevention — applied automatically inside the adapter
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
- **Validates all paths structurally** — rejects traversal, absolute paths, empty segments, and escapes query strings — regardless of scope mode

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

117 tests covering manifest diffing, conflict resolution, sync engine flows, all three scope modes (`userDrive`, `appFiles`, `appData`), path validation, query injection prevention, backward compatibility with legacy constructors, and the full DriveSyncClient lifecycle.

## License

MIT
